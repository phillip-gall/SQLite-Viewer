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
        let sample = app.buttons["schema-table:sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        XCTAssertTrue(app.staticTexts["column-value"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["index-sample_value"].exists)
        XCTAssertTrue(app.staticTexts["stored-sql"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
    }
}
