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
        #if os(macOS)
            if app.outlines.staticTexts["Dashboard"].exists {
                app.outlines.staticTexts["Dashboard"].click()
            }
        #endif
        sleep(1)
        snapshot("01_Dashboard")
    }

    func test02Logs() throws {
        #if os(iOS)
            if app.tabBars.buttons["Logs"].exists {
                app.tabBars.buttons["Logs"].firstMatch.tap()
            } else if app.buttons["Logs"].exists {
                app.buttons["Logs"].firstMatch.tap()
            }
        #elseif os(macOS)
            if app.outlines.staticTexts["Logs"].exists {
                app.outlines.staticTexts["Logs"].click()
            }
        #elseif os(tvOS)
            let remote = XCUIRemote.shared
            for _ in 0 ..< 3 {
                remote.press(.down)
                usleep(300_000)
            }
            if app.cells["Logs"].exists {
                app.cells["Logs"].tap()
            } else {
                remote.press(.select)
            }
        #endif
        sleep(1)
        snapshot("02_Logs")
    }

    func test03Settings() throws {
        #if os(iOS)
            if app.tabBars.buttons["Settings"].exists {
                app.tabBars.buttons["Settings"].firstMatch.tap()
            } else if app.buttons["Settings"].exists {
                app.buttons["Settings"].firstMatch.tap()
            }
        #elseif os(macOS)
            if app.outlines.staticTexts["Settings"].exists {
                app.outlines.staticTexts["Settings"].click()
            }
        #elseif os(tvOS)
            let remote = XCUIRemote.shared
            remote.press(.down)
            usleep(300_000)
            if app.cells["Settings"].exists {
                app.cells["Settings"].tap()
            } else {
                remote.press(.select)
            }
        #endif
        sleep(1)
        snapshot("03_Settings")
    }
}
