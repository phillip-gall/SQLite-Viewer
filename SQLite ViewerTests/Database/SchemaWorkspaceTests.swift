import XCTest
@testable import SQLite_Viewer

@MainActor
final class SchemaWorkspaceTests: XCTestCase {
    func testRefreshTracksCreateDropAndClosedSession() async throws {
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
        let model = SchemaWorkspaceModel(databaseID: entry.id, library: library)
        model.refreshSchema()
        try await waitUntil { !model.isLoading }
        XCTAssertTrue(model.catalog.contains { $0.name == "sample" })

        try await session.execute("CREATE TABLE added (value TEXT)")
        model.refreshSchema()
        try await waitUntil { !model.isLoading }
        let added = try XCTUnwrap(model.catalog.first { $0.name == "added" })
        model.select(id: added.id)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.tableDetail?.object.name, "added")

        try await session.execute("DROP TABLE added")
        model.refreshSchema()
        try await waitUntil { !model.isLoading }
        XCTAssertNil(model.selected)
        XCTAssertNil(model.tableDetail)
        XCTAssertFalse(model.catalog.contains { $0.name == "added" })

        try await library.closeActive()
        model.refreshSchema()
        try await waitUntil { !model.isLoading }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.catalog.isEmpty)
        model.invalidate()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for schema work")
    }
}
