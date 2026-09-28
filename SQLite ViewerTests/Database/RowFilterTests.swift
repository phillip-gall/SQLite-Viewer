import XCTest
@testable import SQLite_Viewer

final class RowFilterTests: XCTestCase {
    func testPredicatesMatchPagesAndCounts() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute(
            "CREATE TABLE people (customer_id INTEGER, income INTEGER, note TEXT, payload BLOB, \"odd\"\"name\" TEXT)"
        )
        try await fixture.session.execute(
            """
            INSERT INTO people VALUES
            (10, 500, 'low', NULL, 'first'),
            (10, 1500, '100%_match', x'01', 'second'),
            (20, 2000, NULL, NULL, 'third'),
            (10, 3000, 'other', NULL, 'fourth')
            """
        )
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let object = try XCTUnwrap(catalog.first { $0.name == "people" })
        let rows = RowsService(session: fixture.session)
        let counts = TableCountService(session: fixture.session)
        let filters = [
            RowFilter(column: "customer_id", operation: .equals, value: .integer(10)),
            RowFilter(column: "income", operation: .greater, value: .integer(1000))
        ]
        let page = try await rows.loadPage(for: object, filters: filters)
        let matching = try await counts.countMatching(object, filters: filters)
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(matching, 2)
        XCTAssertEqual(page.rows.map { $0[1] }, [.integer(1500), .integer(3000)])

        let literal = [RowFilter(column: "note", operation: .contains, value: .text("%_"))]
        let literalPage = try await rows.loadPage(for: object, filters: literal)
        XCTAssertEqual(literalPage.rows.count, 1)
        let literalCount = try await counts.countMatching(object, filters: literal)
        XCTAssertEqual(literalCount, 1)
        let nulls = try await rows.loadPage(for: object, filters: [
            RowFilter(column: "payload", operation: .isNull)
        ])
        XCTAssertEqual(nulls.rows.count, 3)
        let nonNulls = try await rows.loadPage(for: object, filters: [
            RowFilter(column: "payload", operation: .isNotNull)
        ])
        XCTAssertEqual(nonNulls.rows.count, 1)
        let quoted = try await rows.loadPage(for: object, filters: [
            RowFilter(column: "odd\"name", operation: .equals, value: .text("third"))
        ])
        XCTAssertEqual(quoted.rows.first?[0], .integer(20))
        let none = try await rows.loadPage(for: object, filters: [
            RowFilter(column: "income", operation: .less, value: .integer(0))
        ])
        XCTAssertTrue(none.rows.isEmpty)
        let zeroCount = try await counts.countMatching(object, filters: [
            RowFilter(column: "income", operation: .less, value: .integer(0))
        ])
        XCTAssertEqual(zeroCount, 0)
    }

    func testRejectsUntrustedColumnsAndUnsupportedValues() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let object = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let rows = RowsService(session: fixture.session)
        for filter in [
            RowFilter(column: "label; DROP TABLE sample", operation: .equals, value: .text("x")),
            RowFilter(column: "label", operation: .equals, value: .blob(Data([0xFF]))),
            RowFilter(column: "payload", operation: .equals, value: .text("x")),
            RowFilter(column: "decimal", operation: .greater, value: .real(.infinity)),
            RowFilter(column: "label", operation: .contains, value: .integer(1)),
            RowFilter(column: "label", operation: .equals)
        ] {
            do {
                _ = try await rows.loadPage(for: object, filters: [filter])
                XCTFail("Expected filter rejection")
            } catch is RowFilterError { }
        }
        let after = try await SchemaService(session: fixture.session).loadCatalog()
        XCTAssertNotNil(after.first { $0.name == "sample" })
    }

    func testFilteredPagingAndSort() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 205)
            INSERT INTO sample(id, number, label) SELECT n, n, 'same' FROM seq
            """
        )
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let object = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let filters = [RowFilter(column: "number", operation: .greaterOrEqual, value: .integer(50))]
        let service = RowsService(session: fixture.session)
        let second = try await service.loadPage(for: object, number: 2,
                                                sort: RowSort(column: "label", descending: false),
                                                filters: filters)
        XCTAssertEqual(second.rows.count, 56)
        XCTAssertEqual(second.rows.first?[0], .integer(150))
        XCTAssertFalse(second.hasNext)
        let count = try await TableCountService(session: fixture.session)
            .countMatching(object, filters: filters)
        XCTAssertEqual(count, 156)
    }
}
