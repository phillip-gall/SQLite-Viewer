import Foundation
@testable import SQLite_Viewer

struct SQLiteFixture {
    let directory: URL
    let session: DatabaseSession

    static func make() async throws -> SQLiteFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try DatabaseSession(url: directory.appendingPathComponent("fixture.sqlite"), createIfNeeded: true)
        try await session.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, number INTEGER, decimal REAL, label TEXT, payload BLOB, optional TEXT)")
        try await session.execute("CREATE INDEX sample_label ON sample(label)")
        try await session.execute("CREATE TABLE keys (left_key TEXT, right_key TEXT, PRIMARY KEY(left_key, right_key)) WITHOUT ROWID")
        return SQLiteFixture(directory: directory, session: session)
    }

    func remove() async {
        try? await session.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
