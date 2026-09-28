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
        for _ in 0..<3 {
            if app.staticTexts["stored-sql"].exists { break }
            app.swipeUp()
        }
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

    @MainActor
    func testBrowseLaterPageAndOffscreenColumn() throws {
        let app = XCUIApplication()
        let name = "Grid Test \(UUID().uuidString)"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let database = app.staticTexts[name]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        let wideRows = app.buttons["schema-table:wide_rows"]
        XCTAssertTrue(wideRows.waitForExistence(timeout: 10))
        wideRows.tap()
        let browse = app.buttons["browse-rows"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap()
        let next = app.buttons["rows-next-page"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Row 101, value, text row 101"].waitForExistence(timeout: 10))
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.exists)
        grid.swipeLeft()
        grid.swipeLeft()
        XCTAssertTrue(app.buttons["sort-distant"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
