#if os(macOS)

    import AppKit
    import Foundation
    import Libbox
    import Library
    import os
    import SwiftUI

    private let logger = Logger(category: "UpdateManager")

    @MainActor
    public class UpdateManager: ObservableObject {
        private static let minimumSemver = "0.0.0-0"

        @Published public var updateInfo: UpdateInfo?
        @Published public var isUpdateSheetPresented = false
        @Published public var isChecking = false
        @Published public var isDownloading = false
        @Published public var downloadProgress: Double = 0
        @Published public var alert: AlertState?

        public init() {}

        public func updateTrackChanged(to track: UpdateTrack) async {
            await SharedPreferences.updateTrack.set(track.rawValue)
            guard let updateInfo, !track.allows(updateInfo) else {
                return
            }
            await setUpdateInfo(nil)
        }

        @discardableResult
        public func loadCachedUpdate() async -> Bool {
            let cached = await SharedPreferences.cachedUpdateInfo.get()
            guard !cached.isEmpty,
                  let data = cached.data(using: .utf8),
                  let info = try? JSONDecoder().decode(UpdateInfo.self, from: data)
            else {
                return false
            }

            let track = await currentTrack()
            guard track.allows(info),
                  shouldKeepCachedUpdate(info.versionName, track: track, currentVersion: Bundle.main.version)
            else {
                await setUpdateInfo(nil)
                return false
            }

            updateInfo = info
            return await shouldAutomaticallyPresent(info)
        }

        @discardableResult
        public func checkForUpdate(presentIfFound: Bool = false, force: Bool = false, showsAlertOnFailure: Bool = true) async -> Bool {
            do {
                guard let info = try await refreshUpdateInfo(force: force, showsAlertOnFailure: showsAlertOnFailure) else {
                    return false
                }
                guard presentIfFound else {
                    return false
                }
                return await shouldAutomaticallyPresent(info)
            } catch {
                return false
            }
        }

        public func showUpdateSheet() async {
            guard let updateInfo else { return }
            await SharedPreferences.lastShownUpdateVersion.set(updateInfo.versionName)
            isUpdateSheetPresented = true
        }

        public func dismissUpdateSheet() {
            guard isUpdateSheetPresented else { return }
            isUpdateSheetPresented = false
        }

        public func downloadAndInstall(environments: ExtensionEnvironments) async {
            guard let updateInfo else { return }

            isDownloading = true
            downloadProgress = 0
            alert = nil

            do {
                let pkgURL = try await PKGDownloader.download(from: updateInfo.downloadURL, expectedSize: updateInfo.fileSize) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                let authRef = try PKGInstaller.authorize()
                try await Task.detached {
                    try PKGInstaller.install(pkgPath: pkgURL.path, authorization: authRef)
                }.value

                var profile = environments.extensionProfile
                if profile == nil {
                    await environments.reload()
                    profile = environments.extensionProfile
                }
                if let profile, profile.status.isConnected {
                    try? await profile.stop()
                    var waitCount = 0
                    while profile.status != .disconnected, waitCount < 10 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        waitCount += 1
                    }
                }

                do {
                    try PKGInstaller.scheduleInstalledApplicationRelaunch()
                } catch {
                    logger.warning("relaunch failed: \(error.localizedDescription)")
                }
                exit(0)
            } catch PKGInstallerError.authorizationCancelled {
                isDownloading = false
            } catch {
                isDownloading = false
                logger.error("update failed: \(error.localizedDescription)")
                alert = AlertState(action: "install update", error: error)
            }
        }

        func refreshUpdateInfo(force: Bool = false, showsAlertOnFailure: Bool = true) async throws -> UpdateInfo? {
            guard !isChecking else {
                throw CancellationError()
            }
            isChecking = true
            if showsAlertOnFailure {
                alert = nil
            }
            defer { isChecking = false }

            do {
                let track = await currentTrack()
                let info = try await GitHubUpdateChecker.checkAsync(track: track, force: force)
                let currentTrack = await currentTrack()
                guard track == currentTrack else {
                    throw CancellationError()
                }
                await setUpdateInfo(info)
                return info
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.error("check for update failed: \(error.localizedDescription)")
                if showsAlertOnFailure {
                    alert = AlertState(action: "check for update", error: error)
                }
                throw error
            }
        }

        private func currentTrack() async -> UpdateTrack {
            let trackString = await SharedPreferences.updateTrack.get()
            return UpdateTrack.resolved(from: trackString)
        }

        private func shouldAutomaticallyPresent(_ updateInfo: UpdateInfo) async -> Bool {
            let lastShownVersion = await SharedPreferences.lastShownUpdateVersion.get()
            return lastShownVersion != updateInfo.versionName
        }

        private func shouldKeepCachedUpdate(_ version: String, track: UpdateTrack, currentVersion: String) -> Bool {
            guard Self.isValidSemver(version) else {
                return false
            }
            if LibboxCompareSemver(version, currentVersion) {
                return true
            }
            return track == .stable && Self.isValidPrereleaseSemver(currentVersion)
        }

        private static func isValidSemver(_ version: String) -> Bool {
            let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedVersion == minimumSemver || LibboxCompareSemver(trimmedVersion, minimumSemver)
        }

        private static func isValidPrereleaseSemver(_ version: String) -> Bool {
            let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedVersion.contains("-") && isValidSemver(trimmedVersion)
        }

        private func setUpdateInfo(_ updateInfo: UpdateInfo?) async {
            self.updateInfo = updateInfo

            guard let updateInfo,
                  let data = try? JSONEncoder().encode(updateInfo)
            else {
                dismissUpdateSheet()
                await SharedPreferences.cachedUpdateInfo.set("")
                await SharedPreferences.lastShownUpdateVersion.set("")
                return
            }
            await SharedPreferences.cachedUpdateInfo.set(String(decoding: data, as: UTF8.self))
        }
    }

#endif
