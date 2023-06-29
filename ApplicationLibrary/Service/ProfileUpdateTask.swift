import Foundation
import Library

public enum ProfileUpdateTask {
    private static var timer: Timer?

    public static func setup() throws {
        var earliestBeginDate: Date?
        if let updatedAt = try oldestUpdated() {
            if updatedAt > Date(timeIntervalSinceNow: -taskInterval) {
                earliestBeginDate = updatedAt.addingTimeInterval(taskInterval)
            }
        }
        timer = Timer(fire: earliestBeginDate ?? Date.now, interval: taskInterval, repeats: true, block: { _ in
            do {
                _ = try updateProfiles()
                NSLog("profile update task succeed")
            } catch {
                NSLog("profile update task failed: \(error.localizedDescription)")
            }
        })
    }

    static let taskInterval: TimeInterval = 15 * 60

    static func oldestUpdated() throws -> Date? {
        let profiles = try ProfileManager.listAutoUpdateEnabled()
        return profiles.map { profile in
            profile.lastUpdated!
        }
        .min()
    }

    static func updateProfiles() throws -> Bool {
        let profiles = try ProfileManager.listAutoUpdateEnabled()
        var success = true
        for profile in profiles {
            if profile.lastUpdated! > Date(timeIntervalSinceNow: -taskInterval) {
                continue
            }
            do {
                try profile.updateRemoteProfile()
            } catch {
                NSLog("Update profile \(profile.name) failed: \(error.localizedDescription)")
                success = false
            }
        }
        return success
    }
}
