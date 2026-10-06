import XCTest

/// Captures real simulator renders and exercises the rebuilt control layer.
final class RenderedViewsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testWorkspaceRendersAndControls() throws {
        let app = XCUIApplication()
        let name = "Design review \(UUID().uuidString.prefix(4))"
        app.launchArguments = ["-ui-test-import", name]
        app.launch()
        capture(app, "01-library")
        app.buttons["import-test-database"].tap()
        let open = app.buttons["Open \(name)"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let sample = app.buttons["schema-table:sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        capture(app, "02-schema")
        sample.tap()
        XCTAssertTrue(app.staticTexts["column-value"].waitForExistence(timeout: 10))
        capture(app, "03-schema-detail")
        app.buttons["browse-rows"].tap()
        XCTAssertTrue(app.buttons["sort-id"].waitForExistence(timeout: 10))
        capture(app, "04-rows")
        app.buttons["show-filters"].tap()
        XCTAssertTrue(app.buttons["add-filter"].waitForExistence(timeout: 5))
        app.buttons["add-filter"].tap()
        let value = app.textFields["filter-value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("1")
        capture(app, "05-filter-editor")
        app.buttons["apply-filter"].tap()
        XCTAssertTrue(app.buttons["clear-filters"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["rows-matching-count"].waitForExistence(timeout: 5))
        capture(app, "06-filtered-rows")
        select("SQL", in: app)
        let editor = app.textViews["sql-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("SELECT * FROM sample;")
        app.buttons["run-sql"].tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: 10))
        capture(app, "07-sql")
        select("Storage", in: app)
        XCTAssertTrue(app.staticTexts["storage-total"].waitForExistence(timeout: 10))
        capture(app, "08-storage")
        app.buttons["storage-category:indexes"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["storage-category-chart"].waitForExistence(timeout: 5))
        capture(app, "09-storage-detail")
        app.buttons["storage-overview"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["storage-chart"].exists)
        if app.buttons["toggle-schema-sidebar"].exists {
            app.buttons["toggle-schema-sidebar"].tap()
            XCTAssertFalse(app.descendants(matching: .any)["schema-sidebar"].exists)
            capture(app, "10-expanded-content")
            app.buttons["toggle-schema-sidebar"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["schema-sidebar"].exists)
        }
    }

    @MainActor
    private func select(_ title: String, in app: XCUIApplication) {
        if app.tabBars.buttons[title].exists { app.tabBars.buttons[title].tap() }
        else { app.segmentedControls.buttons[title].tap() }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
