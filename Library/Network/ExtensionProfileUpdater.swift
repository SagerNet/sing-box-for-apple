#if os(iOS) || os(tvOS)
    import Foundation
    import Libbox

    final class ExtensionProfileUpdater {
        private unowned let provider: ExtensionProvider
        private let queue = DispatchQueue(label: "io.nekohasekai.sfamt.profile-updater")
        private var generation = 0
        private var timer: DispatchSourceTimer?
        private var task: Task<Void, Never>?
        private var retryProfileID: Int64?
        private var retryDate: Date?

        init(_ provider: ExtensionProvider) {
            self.provider = provider
        }

        func check() {
            queue.async { [self] in
                if task != nil {
                    return
                }
                timer?.cancel()
                timer = nil
                let generation = generation
                task = Task {
                    let nextDate = await run(generation)
                    queue.async { [self] in
                        guard generation == self.generation else {
                            return
                        }
                        task = nil
                        if let nextDate {
                            schedule(nextDate)
                        }
                    }
                }
            }
        }

        func cancel() {
            queue.sync {
                generation += 1
                task?.cancel()
                task = nil
                timer?.cancel()
                timer = nil
            }
        }

        private func schedule(_ date: Date) {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(wallDeadline: .now() + date.timeIntervalSinceNow)
            timer.setEventHandler { [unowned self] in
                check()
            }
            timer.resume()
            self.timer = timer
        }

        private func currentProfileID() -> Int64? {
            (provider.tunnelOptions?["profileID"] as? NSNumber)?.int64Value
        }

        private func isCurrent(_ generation: Int) -> Bool {
            queue.sync {
                generation == self.generation
            }
        }

        private func ensureCurrent(_ generation: Int, _ profileID: Int64) throws {
            try Task.checkCancellation()
            guard isCurrent(generation), provider.commandServer != nil, currentProfileID() == profileID else {
                throw CancellationError()
            }
        }

        private func run(_ generation: Int) async -> Date? {
            guard let profileID = currentProfileID() else {
                return nil
            }
            let profile: Profile
            do {
                guard let loadedProfile = try await ProfileManager.get(profileID) else {
                    return nil
                }
                profile = loadedProfile
            } catch {
                provider.writeMessage("(profile-updater) load profile: \(error.localizedDescription)")
                return Date(timeIntervalSinceNow: Profile.minAutoUpdateInterval)
            }
            guard profile.type == .remote, profile.autoUpdate else {
                return nil
            }
            let retryDate = queue.sync {
                retryProfileID == profileID ? self.retryDate : nil
            }
            if let retryDate, retryDate > Date() {
                return retryDate
            }
            let interval = profile.autoUpdateIntervalOrDefault
            if let lastUpdated = profile.lastUpdated, lastUpdated.addingTimeInterval(interval) > Date() {
                return lastUpdated.addingTimeInterval(interval)
            }
            do {
                try await update(profile, generation: generation)
                queue.sync {
                    retryProfileID = nil
                    self.retryDate = nil
                }
                return Date(timeIntervalSinceNow: interval)
            } catch is CancellationError {
                return nil
            } catch {
                provider.writeMessage("(profile-updater) update profile \(profile.name): \(error.localizedDescription)")
                let nextDate = Date(timeIntervalSinceNow: Profile.minAutoUpdateInterval)
                queue.sync {
                    retryProfileID = profileID
                    self.retryDate = nextDate
                }
                return nextDate
            }
        }

        private func update(_ profile: Profile, generation: Int) async throws {
            let profileID = profile.mustID
            let remoteContent = try await fetch(profile.remoteURL)
            try ensureCurrent(generation, profileID)
            try await BlockingIO.run {
                var error: NSError?
                LibboxParseConfig(remoteContent, &error)
                if let error {
                    throw error
                }
            }
            guard let latestProfile = try await ProfileManager.get(profileID), latestProfile.autoUpdate, latestProfile.remoteURL == profile.remoteURL else {
                throw CancellationError()
            }
            let oldContent = try await latestProfile.readAsync()
            if oldContent != remoteContent {
                try ensureCurrent(generation, profileID)
                try await latestProfile.writeAsync(remoteContent)
                do {
                    try await provider.reloadService(configContent: remoteContent, profileID: profileID) { [self] in
                        isCurrent(generation)
                    }
                } catch is CancellationError {
                    if try await latestProfile.readAsync() == remoteContent {
                        try await latestProfile.writeAsync(oldContent)
                    }
                    throw CancellationError()
                } catch {
                    provider.writeMessage("(profile-updater) start updated profile \(profile.name): \(error.localizedDescription), rolling back")
                    try? await latestProfile.writeAsync(oldContent)
                    try await provider.reloadService(configContent: oldContent, profileID: profileID) { [self] in
                        isCurrent(generation)
                    }
                    throw error
                }
                provider.writeMessage("(profile-updater) profile \(profile.name) updated", level: .info)
            }
            try await ProfileManager.updateLastUpdated(profileID, Date())
        }

        private func fetch(_ url: String?) async throws -> String {
            if let commandServer = provider.commandServer {
                do {
                    return try await BlockingIO.run {
                        try HTTPClient(commandServer.newHTTPClient()!).getString(url)
                    }
                } catch {
                    provider.writeMessage("(profile-updater) fetch profile through tunnel: \(error.localizedDescription), retrying directly", level: .warn)
                }
            }
            return try await HTTPClient.getStringAsync(url)
        }
    }
#endif
