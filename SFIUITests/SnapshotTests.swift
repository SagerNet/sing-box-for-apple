import XCTest

@MainActor
final class SnapshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        if let page = screenshotPage() {
            app.launchEnvironment["SCREENSHOT_PAGE"] = page
        } else {
            app.launchEnvironment["SCREENSHOT_PAGE"] = ""
        }
        setupSnapshot(app)
        app.launch()
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

    func test01Dashboard() {
        snapshot("01_Dashboard")
    }

    func test02Logs() {
        sleep(1)
        snapshot("02_Logs")
    }

    func test03Settings() {
        sleep(1)
        snapshot("03_Settings")
    }
}
