import XCTest

@MainActor
final class SnapshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        setupSnapshot(app)
        app.launch()
    }

    func test01Dashboard() throws {
        snapshot("01_Dashboard")
    }

    func test02Logs() throws {
        if app.tabBars.buttons["Logs"].exists {
            app.tabBars.buttons["Logs"].firstMatch.tap()
        } else if app.buttons["Logs"].exists {
            app.buttons["Logs"].firstMatch.tap()
        }
        sleep(1)
        snapshot("02_Logs")
    }

    func test03Settings() throws {
        // iPad on iOS 18+ uses floating tab bar which creates nested elements
        // Use firstMatch to handle multiple matching elements
        if app.tabBars.buttons["Settings"].exists {
            app.tabBars.buttons["Settings"].firstMatch.tap()
        } else if app.buttons["Settings"].exists {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists {
                tabBar.buttons.element(boundBy: tabBar.buttons.count - 1).tap()
            }
        }
        sleep(1)
        snapshot("03_Settings")
    }
}
