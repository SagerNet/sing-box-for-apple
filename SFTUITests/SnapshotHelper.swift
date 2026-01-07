import Foundation
import XCTest

private var screenshotsDir: URL!

private func resolveScreenshotsDir() -> URL {
    let env = ProcessInfo.processInfo.environment
    if let override = env["SCREENSHOTS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    if let override = env["SNAPSHOT_SCREENSHOTS_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    if let simulatorHostHome = env["SIMULATOR_HOST_HOME"] {
        return URL(fileURLWithPath: simulatorHostHome)
            .appendingPathComponent("Library/Caches/tools.fastlane/screenshots")
    }
    return URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/tools.fastlane/screenshots")
}

@MainActor
func setupSnapshot(_ app: XCUIApplication, waitForAnimations _: Bool = true) {
    app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]
    screenshotsDir = resolveScreenshotsDir()
    try! FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
}

@MainActor
func snapshot(_ name: String, waitForLoadingIndicator: Bool = true) {
    snapshot(name, timeWaitingForIdle: waitForLoadingIndicator ? 1 : 0)
}

@MainActor
func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval) {
    if timeout > 0 {
        sleep(UInt32(timeout))
    }
    let simulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "AppleTV"
    let screenshot = XCUIScreen.main.screenshot()
    let path = screenshotsDir.appendingPathComponent("\(simulator)-\(name).png")
    try! screenshot.pngRepresentation.write(to: path)
}

func loadScreenshotLanguage() -> (language: String?, locale: String?) {
    let dir = resolveScreenshotsDir()
    let language = readScreenshotText(dir.appendingPathComponent("language.txt"))
    let locale = readScreenshotText(dir.appendingPathComponent("locale.txt"))
    return (language, locale)
}

private func readScreenshotText(_ url: URL) -> String? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
