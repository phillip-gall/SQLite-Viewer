import XCTest

final class SQLite_ViewerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImportAndReopenAfterRelaunch() throws {
        let app = XCUIApplication()
        let name = "UI Test \(UUID().uuidString)"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let database = app.staticTexts[name]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        XCTAssertTrue(app.staticTexts["Database open"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        XCTAssertTrue(app.staticTexts["Database open"].waitForExistence(timeout: 10))
    }
}
