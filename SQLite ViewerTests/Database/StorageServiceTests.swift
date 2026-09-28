import Foundation
import XCTest
@testable import SQLite_Viewer

final class StorageServiceTests: XCTestCase {
    func testStorageCategoriesReconcileAndCountEachTreeOnce() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("CREATE TABLE large (id INTEGER PRIMARY KEY, grp INTEGER, note TEXT, payload BLOB)")
        try await fixture.session.execute("CREATE INDEX large_group ON large(grp)")
        try await fixture.session.execute("CREATE INDEX large_note ON large(note)")
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 250)
            INSERT INTO large SELECT n, n % 5, printf('item %04d', n), zeroblob(3000) FROM seq
            """
        )
        try await fixture.session.execute("DELETE FROM large WHERE id > 50")
        try await fixture.session.execute("CREATE TABLE wr (key TEXT PRIMARY KEY, value TEXT) WITHOUT ROWID")
        try await fixture.session.execute("INSERT INTO wr VALUES ('a', 'saved')")
        try await fixture.session.execute("CREATE VIEW large_view AS SELECT id FROM large")

        let report = try await StorageService(session: fixture.session).load()
        XCTAssertGreaterThan(report.pageSize, 0)
        XCTAssertGreaterThan(report.freePages, 0)
        XCTAssertEqual(report.logicalBytes, report.pageSize * report.pageCount)
        XCTAssertEqual(
            report.data.bytes + report.indexes.bytes + report.otherFootprint.bytes +
            report.freeBytes + report.overheadBytes,
            report.logicalBytes
        )
        let large = try XCTUnwrap(report.objects.first { $0.name == "large" })
        XCTAssertEqual(large.indexes.map(\.name), ["large_group", "large_note"])
        XCTAssertGreaterThan(large.data?.footprint.bytes ?? 0, 0)
        XCTAssertEqual(large.total.bytes, (large.data?.footprint.bytes ?? 0) + large.indexFootprint.bytes)
        let withoutRowID = try XCTUnwrap(report.objects.first { $0.name == "wr" })
        XCTAssertEqual(withoutRowID.data?.name, "wr")
        XCTAssertTrue(withoutRowID.indexes.isEmpty)
        let view = try XCTUnwrap(report.objects.first { $0.name == "large_view" })
        XCTAssertEqual(view.kind, .view)
        XCTAssertEqual(view.total.bytes, 0)
        XCTAssertTrue(report.other.contains { $0.tree.name == "sqlite_schema" })

        let names = report.objects.flatMap { object in
            [object.data?.name].compactMap { $0 } + object.indexes.map(\.name)
        } + report.other.map { $0.tree.name }
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testRefreshReflectsIndexInsertAndDrop() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("CREATE TABLE changing (id INTEGER PRIMARY KEY, payload BLOB)")
        let service = StorageService(session: fixture.session)
        let before = try await service.load()
        let original = try XCTUnwrap(before.objects.first { $0.name == "changing" })
        XCTAssertTrue(original.indexes.isEmpty)

        try await fixture.session.execute("CREATE INDEX changing_payload ON changing(payload)")
        let indexed = try await service.load()
        XCTAssertEqual(indexed.objects.first { $0.name == "changing" }?.indexes.map(\.name), ["changing_payload"])

        try await fixture.session.execute("INSERT INTO changing VALUES (1, zeroblob(20000))")
        let inserted = try await service.load()
        XCTAssertGreaterThan(inserted.objects.first { $0.name == "changing" }?.total.bytes ?? 0,
                             indexed.objects.first { $0.name == "changing" }?.total.bytes ?? 0)

        try await fixture.session.execute("DROP TABLE changing")
        let dropped = try await service.load()
        XCTAssertFalse(dropped.objects.contains { $0.name == "changing" })
        XCTAssertFalse(dropped.other.contains { $0.tree.name == "changing_payload" })
    }

    func testWALIsSeparateFromLogicalPages() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        _ = try await fixture.session.execute("PRAGMA journal_mode=WAL")
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('in WAL')")
        let report = try await StorageService(session: fixture.session).load()
        XCTAssertGreaterThan(report.walBytes, 0)
        XCTAssertEqual(report.logicalBytes, report.pageCount * report.pageSize)
        XCTAssertEqual(report.logicalBytes,
                       report.data.bytes + report.indexes.bytes + report.otherFootprint.bytes +
                       report.freeBytes + report.overheadBytes)
    }

    func testEmptyDatabaseAndOverflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try DatabaseSession(url: directory.appendingPathComponent("empty.sqlite"), createIfNeeded: true)
        let report = try await StorageService(session: session).load()
        XCTAssertTrue(report.objects.isEmpty)
        XCTAssertEqual(report.logicalBytes,
                       report.data.bytes + report.indexes.bytes + report.otherFootprint.bytes +
                       report.freeBytes + report.overheadBytes)
        try await session.close()

        XCTAssertThrowsError(try StorageFootprint(bytes: Int64.max, pages: 0, payload: 0, unused: 0)
            .adding(StorageFootprint(bytes: 1, pages: 0, payload: 0, unused: 0)))
    }
}
