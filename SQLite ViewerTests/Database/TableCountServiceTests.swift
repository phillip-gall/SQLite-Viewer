import XCTest
@testable import SQLite_Viewer

final class TableCountServiceTests: XCTestCase {
    func testExactCountsAndQuotedNamesAfterWrites() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let service = TableCountService(session: fixture.session)
        try await fixture.session.execute("CREATE TABLE \"odd\"\"name\" (value INTEGER)")
        let schema = SchemaService(session: fixture.session)
        var catalog = try await schema.loadCatalog()
        let sample = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let quoted = try XCTUnwrap(catalog.first { $0.name == "odd\"name" })
        var sampleCount = try await service.count(sample)
        XCTAssertEqual(sampleCount, 0)
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('one'), ('two')")
        try await fixture.session.execute("INSERT INTO \"odd\"\"name\" VALUES (1)")
        sampleCount = try await service.count(sample)
        let quotedCount = try await service.count(quoted)
        XCTAssertEqual(sampleCount, 2)
        XCTAssertEqual(quotedCount, 1)
        try await fixture.session.execute("DELETE FROM sample WHERE label = 'one'")
        sampleCount = try await service.count(sample)
        XCTAssertEqual(sampleCount, 1)
        try await fixture.session.execute("DROP TABLE \"odd\"\"name\"")
        do {
            _ = try await service.count(quoted)
            XCTFail("Expected dropped table count to fail")
        } catch { }
        catalog = try await schema.loadCatalog()
        XCTAssertFalse(catalog.contains { $0.name == quoted.name })
    }

    func testCountDecoderPreservesInt64AndRejectsBadResults() throws {
        let large = Int64(Int32.max) + 1
        let valid = SQLiteResult(columns: ["COUNT(*)"], rows: [[.integer(large)]],
                                 rowCount: 1, truncated: false, affectedRows: 0)
        XCTAssertEqual(try TableCountService.decode(valid, table: "big"), large)
        let invalid = SQLiteResult(columns: ["COUNT(*)"], rows: [[.text("unknown")]],
                                   rowCount: 1, truncated: false, affectedRows: 0)
        XCTAssertThrowsError(try TableCountService.decode(invalid, table: "bad"))
    }
}
