import Foundation
import XCTest
@testable import SQLite_Viewer

final class DatabaseExportTests: XCTestCase {
    func testLargeDatabaseOpeningTimings() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await fixture.session.execute("INSERT INTO sample(payload) VALUES (zeroblob(128 * 1024 * 1024))")
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        let start = ProcessInfo.processInfo.systemUptime
        _ = try await library.open(entry.id)
        let openingTime = ProcessInfo.processInfo.systemUptime - start
        let session = try await library.session(for: entry.id)
        let checkStart = ProcessInfo.processInfo.systemUptime
        let check = try await session.execute("PRAGMA quick_check", rowLimit: 1)
        let checkTime = ProcessInfo.processInfo.systemUptime - checkStart
        XCTAssertEqual(check.rows, [[.text("ok")]])
        let size = try await session.execute("SELECT length(payload) FROM sample")
        XCTAssertEqual(size.rows, [[.integer(128 * 1024 * 1024)]])
        print("OPEN_BENCHMARK file_bytes=\(entry.fileSize) open_ms=\(openingTime * 1000) full_check_ms=\(checkTime * 1000)")
        try await library.closeActive()
    }

    func testExportIncludesCommittedWALAndLeavesActiveConnectionUsable() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        _ = try await library.rename(entry.id, to: "Shared database")
        _ = try await library.open(entry.id)
        let session = try await library.session(for: entry.id)
        try await session.execute("PRAGMA journal_mode=WAL")
        try await session.execute("PRAGMA wal_autocheckpoint=0")
        try await session.execute("INSERT INTO sample(label) VALUES ('committed in WAL')")

        let snapshot = try await library.exportDatabase(entry.id)
        XCTAssertEqual(snapshot.fileURL.lastPathComponent, "Shared database.sqlite")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: snapshot.fileURL.deletingLastPathComponent().path),
                       ["Shared database.sqlite"])
        let exported = try DatabaseSession(url: snapshot.fileURL)
        let rows = try await exported.execute("SELECT label FROM sample")
        XCTAssertEqual(rows.rows, [[.text("committed in WAL")]])
        let integrity = try await exported.execute("PRAGMA quick_check")
        XCTAssertEqual(integrity.rows, [[.text("ok")]])
        try await exported.close()

        try await session.execute("INSERT INTO sample(label) VALUES ('later change')")
        let reopenedSnapshot = try DatabaseSession(url: snapshot.fileURL)
        let snapshotCount = try await reopenedSnapshot.execute("SELECT count(*) FROM sample")
        XCTAssertEqual(snapshotCount.rows, [[.integer(1)]])
        try await reopenedSnapshot.close()
        try await library.discardExport(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.fileURL.deletingLastPathComponent().path))
        let liveCount = try await session.execute("SELECT count(*) FROM sample")
        XCTAssertEqual(liveCount.rows, [[.integer(2)]])
        try await library.closeActive()
    }

    func testClosedDatabaseExportUsesSafeFilenameAndCanBeImported() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        _ = try await library.rename(entry.id, to: "../folder\\name:db")
        let snapshot = try await library.exportDatabase(entry.id)
        XCTAssertEqual(snapshot.fileURL.deletingLastPathComponent().lastPathComponent, snapshot.id.uuidString)
        XCTAssertEqual(snapshot.fileURL.lastPathComponent, "..-folder-name-db.sqlite")
        let imported = try await library.importDatabase(from: snapshot.fileURL)
        XCTAssertNotEqual(imported.id, entry.id)
        try await library.discardExport(snapshot)

        _ = try await library.rename(entry.id, to: String(repeating: "🗃", count: 100))
        let unicodeSnapshot = try await library.exportDatabase(entry.id)
        XCTAssertLessThanOrEqual(unicodeSnapshot.fileURL.lastPathComponent.utf8.count, 255)
        try await library.discardExport(unicodeSnapshot)
    }

    func testFailedExportRemovesPartialSnapshot() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        let database = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("database.sqlite")
        try Data("broken database".utf8).write(to: database)
        do {
            _ = try await library.exportDatabase(entry.id)
            XCTFail("Expected corrupt database export to fail")
        } catch { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".exports").path).isEmpty)
    }

    @MainActor
    func testCancelledOpenDoesNotPublishConnectionAndCanBeRetried() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        let opening = Task { @MainActor in try await library.open(entry.id) }
        opening.cancel()
        do {
            _ = try await opening.value
            XCTFail("Expected cancelled open")
        } catch is CancellationError { }
        do {
            _ = try await library.session(for: entry.id)
            XCTFail("Cancelled open must not leave an active connection")
        } catch LibraryError.missingEntry { }
        _ = try await library.open(entry.id)
        try await library.closeActive()
    }
}
