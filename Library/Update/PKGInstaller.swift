#if os(macOS)

    import Foundation
    import Security

    public enum PKGInstaller {
        private static let installerExitStatusMarker = "__PKG_INSTALLER_EXIT_STATUS__="

        private typealias ExecuteWithPrivilegesFunc = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        public static func authorize() throws -> AuthorizationRef {
            var authRef: AuthorizationRef?
            var status = AuthorizationCreate(nil, nil, [], &authRef)
            guard status == errAuthorizationSuccess, let authRef else {
                throw PKGInstallerError.authorizationFailed
            }

            let rightName = kAuthorizationRightExecute
            var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                status = AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
            }
            guard status == errAuthorizationSuccess else {
                if status == errAuthorizationCanceled {
                    AuthorizationFree(authRef, [])
                    throw PKGInstallerError.authorizationCancelled
                }
                AuthorizationFree(authRef, [])
                throw PKGInstallerError.authorizationFailed
            }

            return authRef
        }

        public static func install(pkgPath: String, authorization authRef: AuthorizationRef) throws {
            defer { AuthorizationFree(authRef, []) }

            guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
                throw PKGInstallerError.authorizationFailed
            }
            let executeWithPrivileges = unsafeBitCast(sym, to: ExecuteWithPrivilegesFunc.self)

            let escapedPkgPath = shellQuote(pkgPath)
            let command = "/usr/sbin/installer -pkg \(escapedPkgPath) -target / 2>&1; status=$?; printf '\\n\(installerExitStatusMarker)%d\\n' \"$status\"; exit \"$status\""
            let tool = "/bin/sh"
            var cArgs: [UnsafeMutablePointer<CChar>?] = [
                strdup("-c"), strdup(command), nil,
            ]
            defer { for i in 0 ..< cArgs.count - 1 {
                free(cArgs[i])
            } }

            var pipe: UnsafeMutablePointer<FILE>?
            let status = executeWithPrivileges(authRef, tool, [], &cArgs, &pipe)
            guard status == errAuthorizationSuccess else {
                throw PKGInstallerError.authorizationFailed
            }

            let output = pipe.map(readOutput(from:)) ?? ""
            let (exitStatus, installerOutput) = parseInstallerOutput(output)
            guard let exitStatus else {
                throw PKGInstallerError.installationFailed(installerOutput.isEmpty ? "Installer exited without reporting a status" : installerOutput)
            }
            guard exitStatus == 0 else {
                if installerOutput.isEmpty {
                    throw PKGInstallerError.installationFailed("Installer failed with exit status \(exitStatus)")
                }
                throw PKGInstallerError.installationFailed(installerOutput)
            }
        }

        public static func scheduleInstalledApplicationRelaunch() throws {
            guard let appPath = findInstalledAppPath() else {
                throw PKGInstallerError.relaunchFailed("Installed app not found in /Applications")
            }

            let escapedApp = appPath.replacingOccurrences(of: "'", with: "'\\''")
            let processID = ProcessInfo.processInfo.processIdentifier
            let command = "while kill -0 \(processID) 2>/dev/null; do sleep 1; done; open '\(escapedApp)' >/dev/null 2>&1"

            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", command]
            if let nullHandle = FileHandle(forWritingAtPath: "/dev/null") {
                process.standardOutput = nullHandle
                process.standardError = nullHandle
            }

            do {
                try process.run()
            } catch {
                throw PKGInstallerError.relaunchFailed(error.localizedDescription)
            }
        }

        private static func findInstalledAppPath() -> String? {
            if let bundleID = Bundle.main.bundleIdentifier,
               let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Applications")
            {
                for item in contents where item.hasSuffix(".app") {
                    let path = "/Applications/\(item)"
                    if let bundle = Bundle(path: path), bundle.bundleIdentifier == bundleID {
                        return path
                    }
                }
            }
            let fallback = "/Applications/\(Bundle.main.bundleURL.lastPathComponent)"
            if FileManager.default.fileExists(atPath: fallback) {
                return fallback
            }
            return nil
        }

        private static func shellQuote(_ value: String) -> String {
            "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }

        private static func readOutput(from pipe: UnsafeMutablePointer<FILE>) -> String {
            defer { fclose(pipe) }

            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            while true {
                let count = fread(buffer, 1, bufferSize, pipe)
                if count > 0 {
                    data.append(buffer, count: count)
                }
                if count < bufferSize {
                    if feof(pipe) != 0 || ferror(pipe) != 0 {
                        break
                    }
                }
            }

            return String(decoding: data, as: UTF8.self)
        }

        private static func parseInstallerOutput(_ output: String) -> (Int32?, String) {
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let markerRange = output.range(of: installerExitStatusMarker, options: .backwards) else {
                return (nil, trimmedOutput)
            }

            let statusText = output[markerRange.upperBound...].prefix { $0.isNumber || $0 == "-" }
            let installerOutput = String(output[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (Int32(String(statusText)), installerOutput)
        }
    }

    public enum PKGInstallerError: LocalizedError {
        case authorizationFailed
        case authorizationCancelled
        case installationFailed(String)
        case relaunchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .authorizationFailed:
                return "Authorization failed"
            case .authorizationCancelled:
                return "Authorization cancelled"
            case let .installationFailed(message):
                return message
            case let .relaunchFailed(message):
                return message
            }
        }
    }

#endif
