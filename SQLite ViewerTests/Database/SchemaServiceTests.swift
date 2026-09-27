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
}
