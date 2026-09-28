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
    func testLibraryRowBackgroundOpensAndRenamePersists() throws {
        let app = XCUIApplication()
        let name = "Rename Test \(UUID().uuidString.prefix(6))"
        let renamed = "Renamed database"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let row = app.buttons["Open \(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.collectionViews["database-workspace"].waitForExistence(timeout: 10))
        app.buttons["Databases"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Rename"].tap()
        let editor = app.textFields["rename-name"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count) + renamed)
        app.buttons["save-rename"].tap()
        let newRow = app.buttons["Open \(renamed)"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 10))
        newRow.tap()
        XCTAssertTrue(app.collectionViews["database-workspace"].waitForExistence(timeout: 10))
        app.tabBars.buttons["SQL"].tap()
        XCTAssertTrue(app.staticTexts["Imported copy: \(renamed)"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSchemaAndRowsShowExactTableCount() throws {
        let app = XCUIApplication()
        let name = "Count Test \(UUID().uuidString.prefix(6))"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let row = app.buttons["Open \(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let table = app.buttons["schema-table:sample"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        let count = NSPredicate(format: "label CONTAINS %@", "1 rows")
        expectation(for: count, evaluatedWith: table)
        waitForExpectations(timeout: 10)
        table.tap()
        app.buttons["browse-rows"].tap()
        let rowsCount = app.staticTexts["rows-total-count"]
        XCTAssertTrue(rowsCount.waitForExistence(timeout: 10))
        XCTAssertEqual(rowsCount.label, "1 rows")
    }

    @MainActor
    func testRowsCombineCustomerAndIncomeFilters() throws {
        let app = XCUIApplication()
        let name = "Filter Test \(UUID().uuidString.prefix(6))"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let row = app.buttons["Open \(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.tabBars.buttons["Rows"].tap()
        app.buttons["rows-object-picker"].tap()
        app.buttons["earnings"].tap()
        XCTAssertTrue(app.buttons["add-filter"].waitForExistence(timeout: 10))

        app.buttons["add-filter"].tap()
        let value = app.textFields["filter-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("10")
        app.buttons["apply-filter"].tap()
        XCTAssertTrue(app.buttons["add-filter"].waitForExistence(timeout: 10))

        app.buttons["add-filter"].tap()
        app.buttons["filter-column"].tap()
        app.buttons["income"].tap()
        app.buttons["filter-operation"].tap()
        app.buttons[">"].tap()
        let secondValue = app.textFields["filter-value"]
        secondValue.tap()
        secondValue.typeText("1000")
        app.buttons["apply-filter"].tap()
        let matching = app.staticTexts["rows-matching-count"]
        XCTAssertTrue(matching.waitForExistence(timeout: 10))
        let expected = NSPredicate(format: "label CONTAINS %@", "Matching 1 of 3 rows")
        expectation(for: expected, evaluatedWith: matching)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["Page 1"].exists)
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

    @MainActor
    func testStorageChartTableDetailsAndSQLRefresh() throws {
        let app = XCUIApplication()
        let name = "Storage Test \(UUID().uuidString)"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        app.buttons["import-test-database"].tap()
        let database = app.staticTexts[name]
        XCTAssertTrue(database.waitForExistence(timeout: 10))
        database.tap()
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Storage")
        ).firstMatch.tap()
        let chart = app.descendants(matching: .any)["storage-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Table data"].exists)
        XCTAssertTrue(app.staticTexts["Free pages"].exists)
        let sample = app.buttons["storage-table:sample"]
        for _ in 0..<4 {
            if sample.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sample.isHittable)
        sample.tap()
        XCTAssertTrue(app.descendants(matching: .any)["storage-detail"].waitForExistence(timeout: 10))

        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "SQL")
        ).firstMatch.tap()
        let editor = app.textViews["sql-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("CREATE INDEX sample_value_extra ON sample(value);")
        app.buttons["run-sql"].tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: 10))
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Storage")
        ).firstMatch.tap()
        let newIndex = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "sample_value_extra,")
        ).firstMatch
        XCTAssertTrue(newIndex.waitForExistence(timeout: 10))
    }
}
