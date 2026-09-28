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

    @MainActor
    func testSQLConsoleRefreshesSchemaAndKeepsDraft() throws {
        let app = XCUIApplication()
        let name = "SQL Test \(UUID().uuidString)"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let database = app.staticTexts[name]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        app.tabBars.buttons["SQL"].tap()
        let editor = app.textViews["sql-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let script = "CREATE TABLE console_added (value TEXT); INSERT INTO console_added VALUES ('persisted'); SELECT value FROM console_added;"
        editor.tap()
        editor.typeText(script)
        app.buttons["run-sql"].tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if app.staticTexts["sql-statement-3"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["sql-statement-3"].exists)
        XCTAssertTrue(app.staticTexts["Row 1, value, text persisted"].exists)
        app.tabBars.buttons["Schema"].tap()
        XCTAssertTrue(app.buttons["schema-table:console_added"].waitForExistence(timeout: 10))
        app.tabBars.buttons["SQL"].tap()
        XCTAssertTrue((editor.value as? String)?.contains(script) == true)
    }

    @MainActor
    func testSQLConsoleShowsErrorAfterSuccessfulStatement() throws {
        let app = XCUIApplication()
        let name = "SQL Error Test \(UUID().uuidString)"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let database = app.staticTexts[name]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        app.tabBars.buttons["SQL"].tap()
        let editor = app.textViews["sql-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("SELECT 1; SELEKT 2;")
        app.buttons["run-sql"].tap()
        XCTAssertTrue(app.staticTexts["sql-error-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["sql-statement-1"].exists)
        XCTAssertTrue(app.staticTexts["Stopped"].exists)
    }
}
