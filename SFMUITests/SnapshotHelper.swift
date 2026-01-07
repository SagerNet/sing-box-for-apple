import AppKit
import CoreGraphics
import Darwin
import Foundation
import XCTest

private var screenshotsDir: URL!
@MainActor
private var currentApp: XCUIApplication?

private func resolveScreenshotsDir() -> URL {
    let env = ProcessInfo.processInfo.environment
    if let override = env["SCREENSHOTS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    if let override = env["SNAPSHOT_SCREENSHOTS_PATH"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        return cachesDir.appendingPathComponent("tools.fastlane/screenshots", isDirectory: true)
    }
    return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("tools.fastlane/screenshots", isDirectory: true)
}

@MainActor
func setupSnapshot(_ app: XCUIApplication, waitForAnimations _: Bool = true) {
    app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]
    currentApp = app
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
    guard let app = currentApp else { return }
    let path = screenshotsDir.appendingPathComponent("Mac-\(name).png")
    var resolvedWindowID: CGWindowID?
    let deadline = Date().addingTimeInterval(10)
    while resolvedWindowID == nil, Date() < deadline {
        resolvedWindowID = windowID(for: app)
        if resolvedWindowID == nil {
            usleep(200_000)
        }
    }
    if let resolvedWindowID {
        if let image = cgWindowListCreateImage(windowID: resolvedWindowID), let data = pngData(from: image) {
            try! data.write(to: path)
            return
        }
        if captureWindowScreenshot(windowID: resolvedWindowID, to: path) {
            return
        }
    }
    let screenshot = XCUIScreen.main.screenshot()
    try! screenshot.pngRepresentation.write(to: path)
}

@MainActor
private func captureWindowScreenshot(windowID: CGWindowID, to path: URL) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-t", "png", "-o", "-l", "\(windowID)", path.path]
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

@MainActor
private func windowID(for _: XCUIApplication) -> CGWindowID? {
    guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: "io.nekohasekai.sfavt").first else {
        return nil
    }
    let pid = Int(runningApp.processIdentifier)
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    var candidate: (id: CGWindowID, area: CGFloat)?
    for info in infoList {
        guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int, ownerPid == pid else {
            continue
        }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        guard layer == 0 else { continue }
        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else {
            continue
        }
        let area = bounds.width * bounds.height
        guard area > 0 else { continue }
        guard let number = info[kCGWindowNumber as String] as? Int else { continue }
        if candidate == nil || area > (candidate?.area ?? 0) {
            candidate = (CGWindowID(number), area)
        }
    }
    return candidate?.id
}

private func cgWindowListCreateImage(windowID: CGWindowID) -> CGImage? {
    typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> CGImage?
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard let symbol = dlsym(rtldDefault, "CGWindowListCreateImage") else { return nil }
    let function = unsafeBitCast(symbol, to: CGWindowListCreateImageFunc.self)
    let bounds = CGRect.null
    let listOption = CGWindowListOption.optionIncludingWindow
    let imageOption: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
    return function(bounds, listOption, windowID, imageOption)
}

private func pngData(from image: CGImage) -> Data? {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
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
