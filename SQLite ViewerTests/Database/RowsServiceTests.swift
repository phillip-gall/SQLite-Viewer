import XCTest
@testable import SQLite_Viewer

final class RowsServiceTests: XCTestCase {
    func testPagingTypedValuesAndDuplicateSortKeys() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 205)
            INSERT INTO sample(id, number, decimal, label, payload, optional)
            SELECT n, CASE WHEN n = 205 THEN 9223372036854775807 ELSE n END,
                   1.25, CASE WHEN n = 205 THEN '日本語' ELSE 'same' END,
                   CASE WHEN n = 205 THEN x'00FF10' ELSE NULL END,
                   NULL FROM seq
            """
        )
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let object = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let service = RowsService(session: fixture.session)
        let first = try await service.loadPage(for: object)
        XCTAssertEqual(first.rows.count, 100)
        XCTAssertTrue(first.hasNext)
        XCTAssertTrue(first.hasStableOrder)
        XCTAssertEqual(first.rows.first?[0], .integer(1))
        let second = try await service.loadPage(for: object, number: 2)
        XCTAssertEqual(second.rows.first?[0], .integer(101))
        XCTAssertTrue(second.hasNext)
        let last = try await service.loadPage(for: object, number: 3)
        XCTAssertEqual(last.rows.count, 5)
        XCTAssertFalse(last.hasNext)
        XCTAssertEqual(last.rows.last?[1], .integer(Int64.max))
        XCTAssertEqual(last.rows.last?[3], .text("日本語"))
        XCTAssertEqual(last.rows.last?[4], .blob(Data([0, 255, 16])))
        XCTAssertEqual(last.rows.last?[5], .null)

        let sorted = try await service.loadPage(for: object, number: 2,
                                                sort: RowSort(column: "label", descending: false))
        XCTAssertEqual(sorted.rows.first?[0], .integer(101))
        XCTAssertEqual(sorted.rows.last?[0], .integer(200))
    }

    func testWithoutRowIDQuotedNamesEmptyAndUnstableView() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("INSERT INTO keys VALUES ('b', '2'), ('a', '2'), ('a', '1')")
        try await fixture.session.execute("CREATE TABLE \"odd\"\"name\" (\"rowid\" TEXT, value TEXT)")
        try await fixture.session.execute("INSERT INTO \"odd\"\"name\" VALUES ('shadow', 'ok')")
        try await fixture.session.execute("INSERT INTO \"odd\"\"name\" VALUES ('second', 'later')")
        try await fixture.session.execute("CREATE TABLE plain (value TEXT)")
        try await fixture.session.execute("INSERT INTO plain VALUES ('b'), ('a')")
        try await fixture.session.execute("CREATE TABLE no_alias (rowid TEXT, _rowid_ TEXT, oid TEXT, value TEXT)")
        try await fixture.session.execute("CREATE TABLE integer_alias (rowid TEXT, _rowid_ TEXT, oid TEXT, value INTEGER PRIMARY KEY)")
        try await fixture.session.execute("INSERT INTO integer_alias(value) VALUES (2), (1)")
        try await fixture.session.execute("CREATE TABLE desc_key (rowid TEXT, _rowid_ TEXT, oid TEXT, value INTEGER PRIMARY KEY DESC)")
        try await fixture.session.execute("INSERT INTO desc_key(value) VALUES (NULL), (NULL)")
        try await fixture.session.execute("CREATE VIEW key_view AS SELECT left_key FROM keys")
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let service = RowsService(session: fixture.session)
        let keys = try XCTUnwrap(catalog.first { $0.name == "keys" })
        let keyPage = try await service.loadPage(for: keys)
        XCTAssertTrue(keyPage.hasStableOrder)
        XCTAssertEqual(keyPage.rows.map { $0[0] }, [.text("a"), .text("a"), .text("b")])
        XCTAssertEqual(keyPage.rows.map { $0[1] }, [.text("1"), .text("2"), .text("2")])

        let quoted = try XCTUnwrap(catalog.first { $0.name == "odd\"name" })
        let quotedPage = try await service.loadPage(for: quoted)
        XCTAssertEqual(quotedPage.rows.first, [.text("shadow"), .text("ok")])
        XCTAssertTrue(quotedPage.hasStableOrder)
        XCTAssertEqual(quotedPage.rows.last, [.text("second"), .text("later")])

        let plain = try XCTUnwrap(catalog.first { $0.name == "plain" })
        let plainPage = try await service.loadPage(for: plain)
        XCTAssertTrue(plainPage.hasStableOrder)
        XCTAssertEqual(plainPage.rows.map { $0[0] }, [.text("b"), .text("a")])
        let noAlias = try XCTUnwrap(catalog.first { $0.name == "no_alias" })
        let noAliasPage = try await service.loadPage(for: noAlias)
        XCTAssertFalse(noAliasPage.hasStableOrder)
        let integerAlias = try XCTUnwrap(catalog.first { $0.name == "integer_alias" })
        let integerAliasPage = try await service.loadPage(for: integerAlias)
        XCTAssertTrue(integerAliasPage.hasStableOrder)
        XCTAssertEqual(integerAliasPage.rows.map { $0[3] }, [.integer(1), .integer(2)])
        let descKey = try XCTUnwrap(catalog.first { $0.name == "desc_key" })
        let descKeyPage = try await service.loadPage(for: descKey)
        XCTAssertFalse(descKeyPage.hasStableOrder)

        let view = try XCTUnwrap(catalog.first { $0.name == "key_view" })
        let viewPage = try await service.loadPage(for: view)
        XCTAssertFalse(viewPage.hasStableOrder)
        do {
            _ = try await service.loadPage(for: keys, number: 0)
            XCTFail("Expected an invalid page error")
        } catch RowsError.invalidPage {}
        do {
            _ = try await service.loadPage(for: keys, sort: RowSort(column: "missing", descending: false))
            XCTFail("Expected an invalid sort error")
        } catch RowsError.invalidSort {}

        let empty = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let emptyPage = try await service.loadPage(for: empty)
        XCTAssertTrue(emptyPage.rows.isEmpty)
        XCTAssertFalse(emptyPage.hasNext)
    }

    func testLargeTableKeepsOnlyOnePage() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 50000)
            INSERT INTO sample(id, number) SELECT n, n FROM seq
            """
        )
        let catalog = try await SchemaService(session: fixture.session).loadCatalog()
        let object = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let page = try await RowsService(session: fixture.session).loadPage(for: object, number: 400)
        XCTAssertEqual(page.rows.count, 100)
        XCTAssertEqual(page.rows.first?[0], .integer(39901))
        XCTAssertTrue(page.hasNext)
    }
}
