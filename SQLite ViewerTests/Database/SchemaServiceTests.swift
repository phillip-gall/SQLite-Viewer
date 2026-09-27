import XCTest
@testable import SQLite_Viewer

final class SchemaServiceTests: XCTestCase {
    func testCatalogIncludesEveryTypeAndSQLiteIndexes() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("CREATE TABLE \"quoted\"\"table\" (value TEXT UNIQUE)")
        try await fixture.session.execute("CREATE VIEW sample_view AS SELECT label FROM sample")
        try await fixture.session.execute("CREATE TRIGGER sample_trigger AFTER INSERT ON sample BEGIN UPDATE sample SET label = 'updated' WHERE id = new.id; END")

        let objects = try await SchemaService(session: fixture.session).loadCatalog()
        XCTAssertEqual(objects, objects.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) })
        XCTAssertEqual(objects.first(where: { $0.name == "sample_view" })?.kind, .view)
        XCTAssertEqual(objects.first(where: { $0.name == "sample_trigger" })?.tableName, "sample")
        XCTAssertEqual(objects.first(where: { $0.name == "sample_label" })?.kind, .index)
        XCTAssertNotNil(objects.first(where: { $0.name == "sample_label" })?.sql)
        XCTAssertEqual(objects.first(where: { $0.name == "quoted\"table" })?.kind, .table)
        let autoindex = try XCTUnwrap(objects.first { $0.name.hasPrefix("sqlite_autoindex_quoted") })
        XCTAssertTrue(autoindex.isInternal)
        XCTAssertEqual(autoindex.tableName, "quoted\"table")
        XCTAssertNil(autoindex.sql)
        XCTAssertNotNil(autoindex.rootPage)
        XCTAssertFalse(objects.contains { $0.name == "sqlite_schema" })
    }

    func testEmptyAndPagedCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try DatabaseSession(url: directory.appendingPathComponent("empty.sqlite"), createIfNeeded: true)
        defer {
            Task {
                try? await session.close()
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let service = SchemaService(session: session)
        let empty = try await service.loadCatalog()
        XCTAssertEqual(empty.count, 0)
        for number in 0..<121 {
            try await session.execute("CREATE TABLE \"item_\(number)\" (id INTEGER)")
        }
        let objects = try await service.loadCatalog()
        XCTAssertEqual(objects.count, 121)
        XCTAssertEqual(Set(objects.map(\.id)).count, 121)
    }

    func testTableAndViewDetails() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("CREATE TABLE \"odd\"\"name\" (a TEXT, b INTEGER, sum INTEGER GENERATED ALWAYS AS (b + 1) VIRTUAL, doubled INTEGER GENERATED ALWAYS AS (b * 2) STORED, PRIMARY KEY (a, b)) WITHOUT ROWID, STRICT")
        try await fixture.session.execute("CREATE VIEW quoted_view AS SELECT a, sum FROM \"odd\"\"name\"")
        let service = SchemaService(session: fixture.session)
        let catalog = try await service.loadCatalog()
        let table = try XCTUnwrap(catalog.first { $0.name == "odd\"name" })
        let detail = try await service.loadTableViewDetail(table)
        XCTAssertEqual(detail.tableKind, .ordinary)
        XCTAssertEqual(detail.withoutRowID, true)
        XCTAssertEqual(detail.strict, true)
        XCTAssertEqual(detail.columns.map(\.name), ["a", "b", "sum", "doubled"])
        XCTAssertEqual(detail.columns.map(\.primaryKeyPosition), [1, 2, 0, 0])
        XCTAssertEqual(detail.columns.map(\.visibility), [.normal, .normal, .generatedVirtual, .generatedStored])
        XCTAssertEqual(detail.columns[0].declaredType, "TEXT")
        XCTAssertNil(detail.columns[0].defaultSQL)
        let pragma = try await fixture.session.execute("PRAGMA main.table_xinfo(\"odd\"\"name\")")
        XCTAssertEqual(pragma.rows.count, detail.columns.count)
        let view = try XCTUnwrap(catalog.first { $0.name == "quoted_view" })
        let viewDetail = try await service.loadTableViewDetail(view)
        XCTAssertNil(viewDetail.tableKind)
        XCTAssertNil(viewDetail.withoutRowID)
        XCTAssertEqual(viewDetail.columns.map(\.name), ["a", "sum"])
        do {
            _ = try await service.loadTableViewDetail(try XCTUnwrap(catalog.first { $0.kind == .index }))
            XCTFail("Expected unsupported object")
        } catch SchemaError.unsupportedObject { }
        try await fixture.session.execute("DROP VIEW quoted_view")
        do {
            _ = try await service.loadTableViewDetail(view)
            XCTFail("Expected missing object")
        } catch SchemaError.missingObject { }
    }

    func testVirtualTableHiddenColumnsWhenSupported() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        guard DatabaseSession.compileOptionUsed("ENABLE_FTS5") else { return }
        try await fixture.session.execute("CREATE VIRTUAL TABLE search USING fts5(body)")
        let service = SchemaService(session: fixture.session)
        let catalog = try await service.loadCatalog()
        let table = try XCTUnwrap(catalog.first { $0.name == "search" })
        let detail = try await service.loadTableViewDetail(table)
        XCTAssertEqual(detail.tableKind, .virtual)
        XCTAssertTrue(detail.columns.contains { $0.visibility == .virtualTableHidden })
        XCTAssertTrue(catalog.contains { $0.name == "search_data" })
        let shadow = try XCTUnwrap(catalog.first { $0.name == "search_data" })
        let shadowDetail = try await service.loadTableViewDetail(shadow)
        XCTAssertEqual(shadowDetail.tableKind, .shadow)
    }
}
