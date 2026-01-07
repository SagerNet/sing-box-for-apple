import XCTest

@MainActor
final class SnapshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.terminate()
        configureLanguage()
        if let value = ProcessInfo.processInfo.environment["SCREENSHOT_WINDOW_PIXEL_HEIGHT"] {
            app.launchEnvironment["SCREENSHOT_WINDOW_PIXEL_HEIGHT"] = value
        }
        if let value = ProcessInfo.processInfo.environment["SCREENSHOT_WINDOW_HEIGHT"] {
            app.launchEnvironment["SCREENSHOT_WINDOW_HEIGHT"] = value
        }
        if let page = screenshotPage() {
            app.launchEnvironment["SCREENSHOT_PAGE"] = page
        } else {
            app.launchEnvironment["SCREENSHOT_PAGE"] = ""
        }
        setupSnapshot(app)
        app.launch()
    }

    private func configureLanguage() {
        let environment = ProcessInfo.processInfo.environment
        var language = environment["SCREENSHOT_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var locale = environment["SCREENSHOT_LOCALE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if language == nil || language?.isEmpty == true {
            let cached = loadScreenshotLanguage()
            language = cached.language
            if locale == nil || locale?.isEmpty == true {
                locale = cached.locale
            }
        }
        guard let language, !language.isEmpty else {
            return
        }
        app.launchArguments += ["-AppleLanguages", "(\(language))"]
        app.launchEnvironment["SCREENSHOT_LANGUAGE"] = language
        if let locale, !locale.isEmpty {
            app.launchArguments += ["-AppleLocale", locale]
            app.launchEnvironment["SCREENSHOT_LOCALE"] = locale
        }
    }

    private func screenshotPage() -> String? {
        let testName = name
        if testName.contains("test01Dashboard") {
            return "dashboard"
        }
        if testName.contains("test02Logs") {
            return "logs"
        }
        if testName.contains("test03Settings") {
            return "settings"
        }
        return nil
    }

    func test01Dashboard() throws {
        sleep(1)
        snapshot("01_Dashboard")
    }

    func test02Logs() throws {
        sleep(1)
        snapshot("02_Logs")
    }

    func test03Settings() throws {
        sleep(1)
        snapshot("03_Settings")
    }
}
