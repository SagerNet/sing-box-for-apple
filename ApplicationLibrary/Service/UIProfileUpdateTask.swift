import BackgroundTasks
import Foundation
import Library

#if os(iOS) || os(tvOS)
    public class UIProfileUpdateTask: BGAppRefreshTask {
        public static let taskSchedulerPermittedIdentifier = "\(FilePath.packageName).update_profiles"

        public static func setup() async throws {
            let success = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskSchedulerPermittedIdentifier, using: nil) { task in
                NSLog("profile update task started")
                do {
                    let success = try ProfileUpdateTask.updateProfiles()
                    try? scheduleUpdate(Date(timeIntervalSinceNow: ProfileUpdateTask.taskInterval))
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
            if !success {
                throw NSError(domain: "register failed", code: 0)
            }
            if await BGTaskScheduler.shared.pendingTaskRequests().isEmpty {
                var earliestBeginDate: Date? = nil
                if let updatedAt = try ProfileUpdateTask.oldestUpdated() {
                    if updatedAt > Date(timeIntervalSinceNow: -ProfileUpdateTask.taskInterval) {
                        earliestBeginDate = updatedAt.addingTimeInterval(ProfileUpdateTask.taskInterval)
                    }
                }
                try scheduleUpdate(earliestBeginDate)
            }
        }

        private static func scheduleUpdate(_ earliestBeginDate: Date?) throws {
            let request = BGAppRefreshTaskRequest(identifier: taskSchedulerPermittedIdentifier)
            request.earliestBeginDate = earliestBeginDate
            try BGTaskScheduler.shared.submit(request)
        }
    }
#endif
