import Foundation
import XCTest
@testable import SQLite_Viewer

final class SharedFileImportTests: XCTestCase {
    func testRepeatedDeliveryIsSuppressedButLaterShareAndFailureCanRetry() {
        let first = URL(fileURLWithPath: "/tmp/first.sqlite")
        let second = URL(fileURLWithPath: "/tmp/second.sqlite")
        let now = Date(timeIntervalSince1970: 1_000)
        var gate = SharedFileImportGate()

        XCTAssertTrue(gate.begin(first, at: now))
        XCTAssertFalse(gate.begin(first, at: now.addingTimeInterval(10)))
        XCTAssertTrue(gate.begin(second, at: now))
        gate.finish(second, succeeded: false, at: now)
        XCTAssertTrue(gate.begin(second, at: now.addingTimeInterval(0.1)))
        gate.finish(first, succeeded: true, at: now.addingTimeInterval(10))
        XCTAssertFalse(gate.begin(first, at: now.addingTimeInterval(11)))
        XCTAssertTrue(gate.begin(first, at: now.addingTimeInterval(13)))
    }

    @MainActor
    func testSharedFileUsesProtectedCopyAndRejectsBadURLs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let source = sourceDirectory.appendingPathComponent("shared.sqlite")
        let session = try DatabaseSession(url: source, createIfNeeded: true)
        try await session.execute("CREATE TABLE sample (value TEXT)")
        try await session.execute("INSERT INTO sample VALUES ('saved')")
        try await session.close()
        let original = try Data(contentsOf: source)

        let library = try DatabaseLibrary(rootURL: root)
        let model = LibraryViewModel(library: library)
        let firstImport = await model.importSharedFile(source)
        XCTAssertTrue(firstImport)
        let repeatedImport = await model.importSharedFile(source)
        XCTAssertFalse(repeatedImport)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let entries = try await library.databases()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.originalFilename, "shared.sqlite")

        try FileManager.default.removeItem(at: source)
        let reopened = await model.open(try XCTUnwrap(entries.first?.id))
        XCTAssertTrue(reopened)

        let badURL = URL(string: "https://example.com/not-a-file.sqlite")!
        let acceptedBadURL = await model.importSharedFile(badURL)
        XCTAssertFalse(acceptedBadURL)
        XCTAssertEqual(model.errorMessage, "Only local files can be imported.")
    }

    @MainActor
    func testUnavailableProviderFileCanBeRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let source = sourceDirectory.appendingPathComponent("late.db")
        let library = try DatabaseLibrary(rootURL: root)
        let model = LibraryViewModel(library: library)
        let missing = await model.importSharedFile(source)
        XCTAssertFalse(missing)
        XCTAssertNotNil(model.errorMessage)
        let entriesAfterFailure = try await library.databases()
        XCTAssertTrue(entriesAfterFailure.isEmpty)

        let session = try DatabaseSession(url: source, createIfNeeded: true)
        try await session.execute("CREATE TABLE sample (value TEXT)")
        try await session.close()
        let retried = await model.importSharedFile(source)
        XCTAssertTrue(retried)
        let entriesAfterRetry = try await library.databases()
        XCTAssertEqual(entriesAfterRetry.count, 1)
    }
}
