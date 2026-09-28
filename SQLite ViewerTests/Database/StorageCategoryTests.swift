import Foundation
import XCTest
@testable import SQLite_Viewer

final class StorageCategoryTests: XCTestCase {
    func testContributorAccountingSharesAndUnassignedCategories() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.execute("CREATE TABLE large (id INTEGER PRIMARY KEY, payload BLOB)")
        try await fixture.session.execute("CREATE INDEX large_payload ON large(payload)")
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200)
            INSERT INTO large SELECT n, zeroblob(3000) FROM seq
            """
        )
        try await fixture.session.execute("DELETE FROM large WHERE id > 20")
        _ = try await fixture.session.execute("PRAGMA journal_mode=WAL")
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('wal')")
        let report = try await StorageService(session: fixture.session).load()
        let all = try StorageCategoryBreakdown.all(from: report)
        XCTAssertEqual(all.count, 5)
        for category in StorageCategory.allCases {
            let breakdown = try XCTUnwrap(all[category])
            XCTAssertEqual(breakdown.contributors.reduce(0) { $0 + $1.bytes }, breakdown.bytes)
            if breakdown.bytes > 0 {
                XCTAssertEqual(breakdown.contributors.reduce(0.0) {
                    $0 + breakdown.share(of: $1)
                }, 1, accuracy: 0.000001)
            }
        }
        XCTAssertGreaterThan(report.walBytes, 0)
        XCTAssertGreaterThan(report.freeBytes, 0)
        XCTAssertTrue(all[.tableData]?.contributors.contains { $0.name == "large" } == true)
        XCTAssertTrue(all[.indexes]?.contributors.contains { $0.name == "large" } == true)
        XCTAssertTrue(all[.other]?.contributors.contains { $0.name == "sqlite_schema" } == true)
        XCTAssertEqual(all[.free]?.contributors.map(\.name), ["Unassigned"])
        if report.overheadBytes > 0 {
            XCTAssertEqual(all[.overhead]?.contributors.map(\.name), ["Unassigned"])
        }
        XCTAssertEqual(all[.free]?.shareOfLogical ?? 0,
                       Double(report.freeBytes) / Double(report.logicalBytes), accuracy: 0.000001)
    }

    func testZeroCategoriesAndMismatch() throws {
        let empty = StorageReport(pageSize: 4096, pageCount: 0, freePages: 0,
                                  logicalBytes: 0, freeBytes: 0, overheadBytes: 0, walBytes: 0,
                                  data: .zero, indexes: .zero, otherFootprint: .zero,
                                  objects: [], other: [])
        let all = try StorageCategoryBreakdown.all(from: empty)
        XCTAssertTrue(all.values.allSatisfy { $0.contributors.isEmpty && $0.shareOfLogical == 0 })
        let inconsistent = StorageReport(pageSize: 4096, pageCount: 1, freePages: 0,
                                         logicalBytes: 4096, freeBytes: 0, overheadBytes: 0,
                                         walBytes: 0,
                                         data: StorageFootprint(bytes: 4096, pages: 1, payload: 0, unused: 0),
                                         indexes: .zero, otherFootprint: .zero,
                                         objects: [], other: [])
        XCTAssertThrowsError(try StorageCategoryBreakdown.all(from: inconsistent))
    }
}

@MainActor
final class StorageCategoryModelTests: XCTestCase {
    func testRefreshKeepsCategorySelectionAndRebuildsContributors() async throws {
        let fixture = try await SQLiteFixture.make()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Task { await fixture.remove() }
            try? FileManager.default.removeItem(at: root)
        }
        try await fixture.session.close()
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        _ = try await library.open(entry.id)
        let session = try await library.session(for: entry.id)
        let model = StorageWorkspaceModel(databaseID: entry.id, library: library)
        model.refresh()
        try await waitUntil { model.report != nil }
        let before = model.breakdowns[.indexes]?.bytes ?? 0
        model.selectCategory(.indexes)
        try await session.execute("CREATE INDEX sample_number ON sample(number)")
        model.refresh()
        try await waitUntil { model.report != nil }
        XCTAssertEqual(model.selectedCategory, .indexes)
        XCTAssertGreaterThan(model.breakdowns[.indexes]?.bytes ?? 0, before)
        try await session.execute("DROP TABLE sample")
        model.refresh()
        try await waitUntil { model.report != nil }
        XCTAssertEqual(model.selectedCategory, .indexes)
        XCTAssertFalse(model.breakdowns[.indexes]?.contributors.contains { $0.name == "sample" } == true)
        try await library.closeActive()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for storage")
    }
}
