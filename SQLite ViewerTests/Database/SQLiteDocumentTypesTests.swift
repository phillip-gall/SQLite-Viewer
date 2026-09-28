import UniformTypeIdentifiers
import XCTest
@testable import SQLite_Viewer

final class SQLiteDocumentTypesTests: XCTestCase {
    func testSystemSQLiteTypeAcceptsSupportedExtensionsOnly() {
        let sqlite = SQLiteDocumentTypes.contentTypes[0]
        XCTAssertEqual(sqlite.identifier, SQLiteDocumentTypes.identifier)
        XCTAssertTrue(sqlite.conforms(to: .data))
        for ext in SQLiteDocumentTypes.supportedExtensions {
            let resolved = UTType(filenameExtension: ext)
            XCTAssertNotNil(resolved, "Missing type for .\(ext)")
            XCTAssertTrue(resolved?.conforms(to: sqlite) == true, ".\(ext) is not SQLite")
        }
        for ext in ["txt", "pdf"] {
            XCTAssertFalse(UTType(filenameExtension: ext)?.conforms(to: sqlite) == true)
        }
        XCTAssertFalse(UTType.folder.conforms(to: sqlite))
    }

    func testSQLiteLookingSuffixStillNeedsContentValidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let source = sourceDirectory.appendingPathComponent("not-a-database.db")
        try Data("not SQLite".utf8).write(to: source)
        let library = try DatabaseLibrary(rootURL: root)
        do {
            _ = try await library.importDatabase(from: source)
            XCTFail("Expected invalid database")
        } catch let error as LibraryError {
            guard case .invalidSource = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let entries = try await library.databases()
        XCTAssertTrue(entries.isEmpty)
    }
}
