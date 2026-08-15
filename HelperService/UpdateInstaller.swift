import Foundation
import Libbox
import Library
import os

private let logger = Logger(category: "UpdateInstaller")

enum UpdateInstaller {
    private static let workDirectoryPath = (WorkingDirectoryManager.helperTempDirectoryPath as NSString).appendingPathComponent("Update")

    static func install(pkgPath: String) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: workDirectoryPath)
        do {
            try fileManager.createDirectory(atPath: workDirectoryPath, withIntermediateDirectories: true)
        } catch {
            throw serviceError("create update directory: \(error.localizedDescription)")
        }
        defer { try? fileManager.removeItem(atPath: workDirectoryPath) }

        let localPKGPath = (workDirectoryPath as NSString).appendingPathComponent("update.pkg")
        do {
            try fileManager.copyItem(atPath: pkgPath, toPath: localPKGPath)
        } catch {
            throw serviceError("copy update package: \(error.localizedDescription)")
        }

        try verifySignature(pkgPath: localPKGPath)
        try verifyVersion(pkgPath: localPKGPath)

        logger.info("installing update package")
        let installResult = runProcess("/usr/sbin/installer", ["-pkg", localPKGPath, "-target", "/"])
        guard installResult.exitStatus == 0 else {
            throw serviceError("installer exited with \(installResult.exitStatus): \(tail(installResult.output))")
        }
        logger.info("update package installed")
    }

    private static func verifySignature(pkgPath: String) throws {
        let result = runProcess("/usr/sbin/pkgutil", ["--check-signature", pkgPath])
        guard result.exitStatus == 0 else {
            throw serviceError("update package is not signed: \(tail(result.output))")
        }
        let expectedTeam = "(\(AppConfiguration.teamID))"
        let signedByTeam = result.output.components(separatedBy: "\n").contains { line in
            line.contains("Developer ID Installer") && line.contains(expectedTeam)
        }
        guard signedByTeam else {
            throw serviceError("update package signer mismatch")
        }
    }

    private static func verifyVersion(pkgPath: String) throws {
        let listResult = runProcess("/usr/bin/xar", ["-tf", pkgPath])
        guard listResult.exitStatus == 0 else {
            throw serviceError("list update package: \(tail(listResult.output))")
        }
        let entries = listResult.output.components(separatedBy: "\n")
        guard let packageInfoEntry = entries.first(where: { $0 == "PackageInfo" || $0.hasSuffix("/PackageInfo") }) else {
            throw serviceError("update package has no PackageInfo")
        }
        let extractResult = runProcess("/usr/bin/xar", ["-xf", pkgPath, packageInfoEntry, "-C", workDirectoryPath])
        guard extractResult.exitStatus == 0 else {
            throw serviceError("extract PackageInfo: \(tail(extractResult.output))")
        }
        let packageInfoPath = (workDirectoryPath as NSString).appendingPathComponent(packageInfoEntry)
        let document: XMLDocument
        do {
            document = try XMLDocument(contentsOf: URL(fileURLWithPath: packageInfoPath), options: [])
        } catch {
            throw serviceError("parse PackageInfo: \(error.localizedDescription)")
        }
        let versionNodes = (try? document.nodes(forXPath: "//bundle/@CFBundleShortVersionString")) ?? []
        guard let packageVersion = versionNodes.compactMap(\.stringValue).first(where: { !$0.isEmpty }) else {
            throw serviceError("update package has no version")
        }
        let installedVersion = Bundle.main.version
        guard LibboxCompareSemver(packageVersion, installedVersion) else {
            throw serviceError("update package \(packageVersion) is not newer than installed \(installedVersion)")
        }
    }

    private static func runProcess(_ executablePath: String, _ arguments: [String]) -> (exitStatus: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: outputData, encoding: .utf8) ?? "")
    }

    private static func tail(_ output: String) -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOutput.count > 1024 else { return trimmedOutput }
        return String(trimmedOutput.suffix(1024))
    }

    private static func serviceError(_ message: String) -> NSError {
        NSError(domain: "RootHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
