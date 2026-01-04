#if os(macOS)
    import Foundation
    import Security

    public struct XPCConnectionInfo {
        public let pid: pid_t
        public let bundleID: String?
        public let teamID: String?
    }

    public enum XPCConnectionValidator {
        private static func getSecCode(for connection: NSXPCConnection) -> SecCode? {
            let pid = connection.processIdentifier
            var code: SecCode?
            let attributes = [kSecGuestAttributePid: pid] as CFDictionary
            guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else {
                return nil
            }
            return code
        }

        private static func getSigningInfo(_ code: SecCode) -> [String: Any]? {
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
                  let staticCode
            else {
                return nil
            }

            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess else {
                return nil
            }
            return info as? [String: Any]
        }

        public static func getConnectionInfo(_ connection: NSXPCConnection) -> XPCConnectionInfo {
            let pid = connection.processIdentifier

            guard let secCode = getSecCode(for: connection),
                  let signingInfo = getSigningInfo(secCode)
            else {
                return XPCConnectionInfo(pid: pid, bundleID: nil, teamID: nil)
            }

            let bundleID = signingInfo[kSecCodeInfoIdentifier as String] as? String
            let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String

            return XPCConnectionInfo(pid: pid, bundleID: bundleID, teamID: teamID)
        }

        public static func validateConnection(
            _ connection: NSXPCConnection,
            teamID: String,
            allowedBundleIDs: [String]
        ) -> Bool {
            guard let secCode = getSecCode(for: connection) else {
                return false
            }

            let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
            var secRequirement: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
                  let req = secRequirement,
                  SecCodeCheckValidity(secCode, [], req) == errSecSuccess
            else {
                return false
            }

            guard let signingInfo = getSigningInfo(secCode),
                  let bundleID = signingInfo[kSecCodeInfoIdentifier as String] as? String,
                  allowedBundleIDs.contains(bundleID)
            else {
                return false
            }

            return true
        }
    }
#endif
