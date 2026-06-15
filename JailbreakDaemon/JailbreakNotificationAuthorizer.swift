#if JAILBREAK
    import Darwin
    import Foundation
    import Library
    import notify
    import os

    private let notificationAuthorizationLogger = Logger(category: "NotificationAuthorization")

    enum JailbreakNotificationAuthorizer {
        private static let systemStorePath = "/var/mobile/Library/BulletinBoard/VersionedSectionInfo.plist"

        /// Binary BBSectionInfo keyed archive template; indices 2, 3, and 5 are patched per bundle.
        private static let sectionInfoTemplateBase64 = [
            "YnBsaXN0MDDUAQIDBAUGTU5YJHZlcnNpb25YJG9iamVjdHNZJGFyY2hpdmVyVCR0b3ASAAGGoKgHCDAxQUgfSVUkbnVsbN8QFQkKCwwNDg8QERITFBUWFxgZGhscHR4fHiEiIx4jJicfHygjIh8jIyMjI18QFHN1cHByZXNzRnJvbVNldHRpbmdzXxASc3VwcHJlc3NlZFNldHRpbmdzWmhpZGVXZWVBcHBZc2VjdGlvbklEW2Rpc3BsYXlOYW1lVGljb25fEBlkaXNwbGF5c0NyaXRpY2FsQnVsbGV0aW5zW3N1YnNlY3Rpb25zXxATc2VjdGlvbkluZm9TZXR0aW5nc1YkY2xhc3NfEA9zZWN0aW9uQ2F0ZWdvcnlfEBJzdWJzZWN0aW9uUHJpb3JpdHlXdmVyc2lvbl8QGm1hbmFnZWRTZWN0aW9uSW5mb1NldHRpbmdzV2FwcE5hbWVbc2VjdGlvblR5cGVfEBBmYWN0b3J5U2VjdGlvbklEXxAPZGF0YVByb3ZpZGVySURzXHN1YnNlY3Rpb25JRFdmaWx0ZXJzXxAYcGF0aFRvV2VlQXBwUGx1Z2luQnVuZGxlCBAACIACgAWAAAiAAIADgAeABoAAgAWAAIAAgACAAIAAXxAmY29tLkxlb05hdGFuLkxOUG9wdXBDb250cm9sbGVyRXhhbXBsZS3ZMjM0NTY3Ejg5Ojs7Ox8fPjtAXHB1c2hTZXR0aW5nc18QGXNob3dzSW5Ob3RpZmljYXRpb25DZW50ZXJfEBNhbGxvd3NOb3RpZmljYXRpb25zXxAWc2hvd3NPbkV4dGVybmFsRGV2aWNlc18QFWNvbnRlbnRQcmV2aWV3U2V0dGluZ15jYXJQbGF5U2V0dGluZ18QEXNob3dzSW5Mb2NrU2NyZWVuWWFsZXJ0VHlwZRA/CQkJgAQJEAHSQkNERVokY2xhc3NuYW1lWCRjbGFzc2VzXxAVQkJTZWN0aW9uSW5mb1NldHRpbmdzokZHXxAVQkJTZWN0aW9uSW5mb1NldHRpbmdzWE5TT2JqZWN0V0xOUG9wdXDSQkNKS11CQlNlY3Rpb25JbmZvokxHXUJCU2VjdGlvbkluZm9fEA9OU0tleWVkQXJjaGl2ZXLRT1BUcm9vdIABAAgAEQAaACMALQAyADcAQABGAHMAigCfAKoAtADAAMUA4QDtAQMBCgEcATEBOQFWAV4BagF9AY8BnAGkAb8BwAHCAcMBxQHHAckBygHMAc4B0AHSAdQB1gHYAdoB3AHeAeACCQIcAikCRQJbAnQCjAKbAq8CuQK7ArwCvQK+AsACwQLDAsgC0wLcAvQC9wMPAxgDIAMlAzMDNgNEA1YDWQNeAAAAAAAAAgEAAAAAAAAAUQAAAAAAAAAAAAAAAAAAA2A=",
        ].joined()

        static func authorize(bundleIdentifier: String, displayName: String) throws {
            guard !bundleIdentifier.isEmpty, !bundleIdentifier.contains("/") else {
                throw makeError("invalid bundle identifier: \(bundleIdentifier)")
            }

            let displayName = displayName.isEmpty ? bundleIdentifier : displayName
            let systemTemplateSectionInfo = (try? loadStore(at: URL(fileURLWithPath: systemStorePath)))?["sectionInfo"] as? [String: Any] ?? [:]

            var wroteStore = false
            for storePath in storePaths {
                do {
                    if try write(
                        bundleIdentifier: bundleIdentifier,
                        displayName: displayName,
                        systemTemplateSectionInfo: systemTemplateSectionInfo,
                        to: storePath
                    ) {
                        wroteStore = true
                        notificationAuthorizationLogger.info("authorized notifications for \(bundleIdentifier, privacy: .public) in \(storePath, privacy: .public)")
                    }
                } catch {
                    notificationAuthorizationLogger.error("authorize notifications \(storePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    if storePath == systemStorePath {
                        throw error
                    }
                }
            }

            if wroteStore {
                postSettingsChangedNotifications()
            }
        }

        private static var storePaths: [String] {
            var paths = [systemStorePath]
            let rootlessPrefix = JailbreakConfiguration.rootlessPrefix
            if rootlessPrefix != "/", FileManager.default.fileExists(atPath: rootlessPrefix) {
                let rootlessStorePath = rootlessPrefix + systemStorePath
                if rootlessStorePath != systemStorePath {
                    paths.append(rootlessStorePath)
                }
            }
            return paths
        }

        private static func makeSectionInfoData(
            bundleIdentifier: String,
            displayName: String,
            sectionInfo: [String: Any],
            systemTemplateSectionInfo: [String: Any]
        ) throws -> Data {
            let templateData: Data
            if let storeTemplateData = Self.templateData(from: sectionInfo, excluding: bundleIdentifier) {
                templateData = storeTemplateData
            } else if let systemTemplateData = Self.templateData(from: systemTemplateSectionInfo, excluding: bundleIdentifier) {
                templateData = systemTemplateData
            } else {
                templateData = try fallbackTemplateData()
            }
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard var archive = try PropertyListSerialization.propertyList(
                from: templateData,
                options: [],
                format: &format
            ) as? [String: Any],
                var objects = archive["$objects"] as? [Any],
                objects.count > 5,
                var section = objects[1] as? [String: Any],
                var settings = objects[3] as? [String: Any]
            else {
                throw makeError("invalid notification section info archive")
            }

            objects[2] = bundleIdentifier
            objects[5] = displayName
            section["hideWeeApp"] = false
            section["isAppClip"] = false
            section["isModificationAllowed"] = false
            section["isRestricted"] = false
            section["suppressFromSettings"] = false
            section["suppressedSettings"] = 0
            settings["allowsNotifications"] = true
            settings["authorizationStatus"] = 2
            settings["alertType"] = 1
            settings["badgeSetting"] = 2
            settings["criticalAlertSetting"] = 0
            settings["lockScreenSetting"] = 2
            settings["notificationCenterSetting"] = 2
            settings["pushSettings"] = 63
            settings["scheduledDeliverySetting"] = settings["scheduledDeliverySetting"] ?? 1
            settings["showsInLockScreen"] = true
            settings["showsInNotificationCenter"] = true
            settings["showsOnExternalDevices"] = true
            settings["showsCustomSettingsLink"] = false
            if settings["soundSetting"] != nil {
                settings["soundSetting"] = 2
            }
            settings["timeSensitiveSetting"] = settings["timeSensitiveSetting"] ?? 0
            settings["userConfiguredDirectMessagesSetting"] = false
            settings["userConfiguredTimeSensitiveSetting"] = false
            objects[1] = section
            objects[3] = settings
            archive["$objects"] = objects

            return try PropertyListSerialization.data(
                fromPropertyList: archive,
                format: .binary,
                options: 0
            )
        }

        private static func templateData(from sectionInfo: [String: Any], excluding bundleIdentifier: String) -> Data? {
            let preferredBundleIdentifiers = [
                "org.coolstar.SileoStore",
                "xyz.willy.Zebra",
                "com.apple.AppStore",
                "com.apple.MobileSMS",
                "com.apple.mobilemail",
            ]
            for key in preferredBundleIdentifiers where key != bundleIdentifier {
                if let data = sectionInfo[key] as? Data, isUsableTemplate(data) {
                    return data
                }
            }
            for key in sectionInfo.keys.sorted() where key != bundleIdentifier && key != "\(bundleIdentifier).extension" {
                if let data = sectionInfo[key] as? Data, isUsableTemplate(data) {
                    return data
                }
            }
            return nil
        }

        private static func isUsableTemplate(_ data: Data) -> Bool {
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let archive = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any],
                let objects = archive["$objects"] as? [Any],
                objects.count > 5,
                objects[1] is [String: Any],
                objects[3] is [String: Any]
            else {
                return false
            }
            return true
        }

        private static func fallbackTemplateData() throws -> Data {
            guard let templateData = Data(base64Encoded: sectionInfoTemplateBase64) else {
                throw makeError("invalid notification section info template")
            }
            return templateData
        }

        private static func write(
            bundleIdentifier: String,
            displayName: String,
            systemTemplateSectionInfo: [String: Any],
            to storePath: String
        ) throws -> Bool {
            let fileManager = FileManager.default
            let storeURL = URL(fileURLWithPath: storePath)
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let existingAttributes = try? fileManager.attributesOfItem(atPath: storePath)
            let wasImmutable = existingAttributes?[.immutable] as? Bool ?? false
            if wasImmutable {
                try? fileManager.setAttributes([.immutable: false], ofItemAtPath: storePath)
            }
            defer {
                if wasImmutable {
                    try? fileManager.setAttributes([.immutable: true], ofItemAtPath: storePath)
                }
            }

            var store = try loadStore(at: storeURL)
            var sectionInfo = store["sectionInfo"] as? [String: Any] ?? [:]
            let sectionInfoData = try makeSectionInfoData(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                sectionInfo: sectionInfo,
                systemTemplateSectionInfo: systemTemplateSectionInfo
            )
            sectionInfo.removeValue(forKey: "\(bundleIdentifier).extension")
            if let existing = sectionInfo[bundleIdentifier] as? Data, existing == sectionInfoData {
                return false
            }
            sectionInfo[bundleIdentifier] = sectionInfoData
            store["sectionInfo"] = sectionInfo
            store["sectionInfoVersionNumber"] = 2

            let storeData = try PropertyListSerialization.data(
                fromPropertyList: store,
                format: .binary,
                options: 0
            )
            try writePreservingExistingFile(storeData, to: storeURL)

            if let existingAttributes {
                try? restore(attributes: existingAttributes, to: storePath)
            } else {
                try? fileManager.setAttributes([
                    .ownerAccountID: 501,
                    .groupOwnerAccountID: 501,
                    .posixPermissions: 0o644,
                ], ofItemAtPath: storePath)
            }
            return true
        }

        private static func loadStore(at url: URL) throws -> [String: Any] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ["sectionInfo": [String: Any]()]
            }
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard var store = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any]
            else {
                throw makeError("invalid BulletinBoard store at \(url.path)")
            }
            if store["sectionInfo"] == nil {
                store["sectionInfo"] = [String: Any]()
            }
            if store["sectionInfoVersionNumber"] == nil {
                store["sectionInfoVersionNumber"] = 2
            }
            return store
        }

        private static func writePreservingExistingFile(_ data: Data, to url: URL) throws {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer {
                    try? handle.close()
                }
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: data)
                try? handle.synchronize()
            } else {
                try data.write(to: url, options: [])
            }
        }

        private static func restore(attributes: [FileAttributeKey: Any], to path: String) throws {
            var restoredAttributes = [FileAttributeKey: Any]()
            for key in [FileAttributeKey.ownerAccountID, .groupOwnerAccountID, .posixPermissions] {
                if let value = attributes[key] {
                    restoredAttributes[key] = value
                }
            }
            if !restoredAttributes.isEmpty {
                try FileManager.default.setAttributes(restoredAttributes, ofItemAtPath: path)
            }
        }

        private static func postSettingsChangedNotifications() {
            for name in [
                "com.apple.bulletinboard.settingschanged",
                "com.apple.bulletinboard.settingsChanged",
                "com.apple.usernotifications.settingschanged",
                "com.apple.usernotifications.settingsChanged",
            ] {
                notify_post(name)
            }
        }

        private static func makeError(_ message: String) -> NSError {
            NSError(domain: "JailbreakNotificationAuthorizer", code: -1, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }
#endif
