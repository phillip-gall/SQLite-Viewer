import Foundation
import XCTest
@testable import SQLite_Viewer

final class DatabaseLibraryTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testImportUnusualExtensionAndReopenAfterSourceRemoval() async throws {
        let fixture = try await SQLiteFixture.make()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('saved')")
        try await fixture.session.close()
        let source = fixture.directory.appendingPathComponent("archive.unusual")
        try FileManager.default.moveItem(at: fixture.directory.appendingPathComponent("fixture.sqlite"), to: source)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: source)
        XCTAssertEqual(entry.originalFilename, "archive.unusual")
        XCTAssertEqual(entry.displayName, "archive")
        let copiedURL = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("database.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        let manifest = try String(contentsOf: root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(source.path))
        XCTAssertFalse(manifest.contains("fixture.sqlite"))
        try FileManager.default.removeItem(at: source)

        let reopenedLibrary = try DatabaseLibrary(rootURL: root)
        let reopened = try await reopenedLibrary.open(entry.id)
        XCTAssertEqual(reopened.id, entry.id)
        let copiedSession = try DatabaseSession(url: copiedURL)
        let result = try await copiedSession.execute("SELECT label FROM sample")
        XCTAssertEqual(result.rows, [[.text("saved")]])
        try await copiedSession.close()
        try await reopenedLibrary.closeActive()
    }

    func testCorruptFileAndInterruptedImportLeaveNoEntry() async throws {
        let root = temporaryRoot()
        let sourceDirectory = temporaryRoot()
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let source = sourceDirectory.appendingPathComponent("broken.db")
        try Data("not sqlite".utf8).write(to: source)
        let library = try DatabaseLibrary(rootURL: root)
        do {
            _ = try await library.importDatabase(from: source)
            XCTFail("Expected invalid header")
        } catch let error as LibraryError {
            guard case .invalidSource = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let afterInvalid = try await library.databases()
        XCTAssertTrue(afterInvalid.isEmpty)

        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        try await fixture.session.close()
        let validURL = fixture.directory.appendingPathComponent("fixture.sqlite")
        let handle = try FileHandle(forWritingTo: validURL)
        try handle.seek(toOffset: 100)
        try handle.write(contentsOf: Data(repeating: 0, count: 100))
        try handle.close()
        do {
            _ = try await library.importDatabase(from: validURL)
            XCTFail("Expected the damaged B-tree to fail backup or quick_check")
        } catch { }
        let afterCorruption = try await library.databases()
        XCTAssertTrue(afterCorruption.isEmpty)
        let staging = root.appendingPathComponent(".staging")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    func testDuplicateImportsAndDeletionOnlyRemoveSelectedCopy() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await fixture.session.close()
        let source = fixture.directory.appendingPathComponent("fixture.sqlite")
        let library = try DatabaseLibrary(rootURL: root)
        let first = try await library.importDatabase(from: source)
        let second = try await library.importDatabase(from: source)
        XCTAssertNotEqual(first.id, second.id)
        let imports = try await library.databases()
        XCTAssertEqual(imports.count, 2)
        _ = try await library.open(first.id)
        try await library.delete(first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.id.uuidString).path))
        let remaining = try await library.open(second.id)
        XCTAssertEqual(remaining.id, second.id)
        try await library.closeActive()
    }

    func testImportIncludesCommittedWALTransactions() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await fixture.session.execute("PRAGMA journal_mode=WAL")
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('from WAL')")

        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        let copiedURL = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("database.sqlite")
        let copied = try DatabaseSession(url: copiedURL)
        let rows = try await copied.execute("SELECT label FROM sample")
        XCTAssertEqual(rows.rows, [[.text("from WAL")]])
        try await copied.close()
    }

    func testImportWALDatabaseFromReadOnlyDirectoryWithoutSidecars() async throws {
        let fixture = try await SQLiteFixture.make()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = fixture.directory.appendingPathComponent("fixture.sqlite")
        _ = try await fixture.session.execute("PRAGMA journal_mode=WAL")
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('checkpointed')")
        try await fixture.session.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try await fixture.session.close()
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
            try? FileManager.default.removeItem(at: fixture.directory)
        }

        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: source)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("source.sqlite").path
        ))
        let copiedURL = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("database.sqlite")
        let copied = try DatabaseSession(url: copiedURL)
        let rows = try await copied.execute("SELECT label FROM sample")
        XCTAssertEqual(rows.rows, [[.text("checkpointed")]])
        try await copied.close()
    }

    func testReadOnlyDirectoryFallbackIncludesAccessibleWAL() async throws {
        let fixture = try await SQLiteFixture.make()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = fixture.directory.appendingPathComponent("fixture.sqlite")
        _ = try await fixture.session.execute("PRAGMA journal_mode=WAL")
        try await fixture.session.execute("INSERT INTO sample(label) VALUES ('still in WAL')")
        let sharedMemory = URL(fileURLWithPath: source.path + "-shm")
        try FileManager.default.removeItem(at: sharedMemory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
            Task { await fixture.remove() }
        }

        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: source)
        let copiedURL = root.appendingPathComponent(entry.id.uuidString).appendingPathComponent("database.sqlite")
        let copied = try DatabaseSession(url: copiedURL)
        let rows = try await copied.execute("SELECT label FROM sample")
        XCTAssertEqual(rows.rows, [[.text("still in WAL")]])
        try await copied.close()
    }

    func testProtectionBackupExclusionAndReconciliation() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await fixture.session.close()
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: fixture.directory.appendingPathComponent("fixture.sqlite"))
        let directory = root.appendingPathComponent(entry.id.uuidString)
        let database = directory.appendingPathComponent("database.sqlite")
        for url in [root, directory, database] {
            let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
            #if targetEnvironment(simulator)
            // CoreSimulator may not report protection classes for its host-backed files.
            if protection == nil { continue }
            #endif
            XCTAssertEqual(protection, .complete, "Missing complete protection: \(url.lastPathComponent)")
        }
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        let orphan = root.appendingPathComponent(".staging").appendingPathComponent("orphan")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        _ = try DatabaseLibrary(rootURL: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        try FileManager.default.removeItem(at: database)
        let listed = try await library.databases()
        XCTAssertNotNil(listed.first?.problem)
        try await library.delete(entry.id)
        let afterDeletion = try await library.databases()
        XCTAssertTrue(afterDeletion.isEmpty)
    }
}
