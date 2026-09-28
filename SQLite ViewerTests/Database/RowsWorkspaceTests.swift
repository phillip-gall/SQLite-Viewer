import XCTest
@testable import SQLite_Viewer

@MainActor
final class RowsWorkspaceTests: XCTestCase {
    func testSelectionRestoresPageAndRefreshClearsDroppedTable() async throws {
        let fixture = try await SQLiteFixture.make()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Task { await fixture.remove() }
            try? FileManager.default.removeItem(at: root)
        }
        try await fixture.session.execute(
            """
            WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 205)
            INSERT INTO sample(id) SELECT n FROM seq
            """
        )
        try await fixture.session.close()
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        _ = try await library.open(entry.id)
        let session = try await library.session(for: entry.id)
        let catalog = try await SchemaService(session: session).loadCatalog()
        let sample = try XCTUnwrap(catalog.first { $0.name == "sample" })
        let keys = try XCTUnwrap(catalog.first { $0.name == "keys" })
        let model = RowsWorkspaceModel(databaseID: entry.id, library: library)

        model.select(sample)
        try await waitUntil { model.page != nil || model.errorMessage != nil }
        XCTAssertNil(model.errorMessage)
        model.showPage(2)
        try await waitUntil { model.page?.number == 2 || model.errorMessage != nil }
        XCTAssertEqual(model.page?.rows.first?[0], .integer(101))
        model.select(keys)
        try await waitUntil { model.page?.object.id == keys.id || model.errorMessage != nil }
        model.select(sample)
        try await waitUntil { model.page?.object.id == sample.id || model.errorMessage != nil }
        XCTAssertEqual(model.page?.number, 2)

        try await session.execute("DROP TABLE sample")
        model.invalidateVisiblePage()
        let updated = try await SchemaService(session: session).loadCatalog()
        model.invalidateAndReload(availableObjects: updated)
        XCTAssertNil(model.selected)
        XCTAssertNil(model.page)
        try await library.closeActive()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for rows")
    }
}
