import BackgroundTasks
import Foundation
import Library

#if os(iOS) || os(tvOS)
    public class UIProfileUpdateTask: BGAppRefreshTask {
        private static let taskSchedulerPermittedIdentifier = "\(FilePath.packageName).update_profiles"
        
        private static var registered = false

        public static func configure() async throws {
            if !registered {
                let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskSchedulerPermittedIdentifier, using: nil) { task in
                    NSLog("profile update task started")
                    Task {
                        await getAndupdateProfiles(task)
                    }
                }
                if !success {
                    throw NSError(domain: "register failed", code: 0)
                }
                registered = true
            }
            BGTaskScheduler.shared.cancelAllTaskRequests()
            let profiles = try await ProfileManager.listAutoUpdateEnabled()
            if profiles.isEmpty {
                return
            }
            try scheduleUpdate(ProfileUpdateTask.calculateEarliestBeginDate(profiles))
        }

        private nonisolated static func getAndupdateProfiles(_ task: BGTask) async {
            let profiles: [Profile]
            do {
                profiles = try await ProfileManager.listAutoUpdateEnabled()
            } catch {
                return
            }
            if profiles.isEmpty {
                return
            }
            do {
                let success = try await ProfileUpdateTask.updateProfiles(profiles)
                try? scheduleUpdate(ProfileUpdateTask.calculateEarliestBeginDate(profiles))
                task.setTaskCompleted(success: success)
                NSLog("profile update task succeed")
            } catch {
                try? scheduleUpdate(nil)
                task.setTaskCompleted(success: false)
                NSLog("profile update task failed: \(error.localizedDescription)")
            }
            task.expirationHandler = {
                try? scheduleUpdate(nil)
                NSLog("profile update task expired")
            }
        }

        private static func scheduleUpdate(_ earliestBeginDate: Date?) throws {
            let request = BGAppRefreshTaskRequest(identifier: taskSchedulerPermittedIdentifier)
            request.earliestBeginDate = earliestBeginDate
            try BGTaskScheduler.shared.submit(request)
        }
    }
#endif
