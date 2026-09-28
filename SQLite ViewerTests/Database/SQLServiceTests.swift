import XCTest
@testable import SQLite_Viewer

final class SQLServiceTests: XCTestCase {
    func testMultipleStatementsTypedRowsAndFailureLocation() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let service = SQLService(session: fixture.session)
        let script = """
        CREATE TABLE notes (value TEXT, payload BLOB, missing TEXT);
        -- A semicolon in this comment ; must not split the script.
        INSERT INTO notes VALUES ('hello; world', x'00FF', NULL);
        SELECT value, payload, missing FROM notes;
        """
        let output = try await service.run(script, cancellation: SQLCancellationToken())
        XCTAssertNil(output.failure)
        XCTAssertEqual(output.blocks.count, 3)
        XCTAssertEqual(output.blocks[1].affectedRows, 1)
        XCTAssertEqual(output.blocks[2].columns, ["value", "payload", "missing"])
        XCTAssertEqual(output.blocks[2].rows, [[.text("hello; world"), .blob(Data([0, 255])), .null]])

        let failed = try await service.run(
            "INSERT INTO notes VALUES ('saved', NULL, NULL);\nSELEKT value FROM notes;\nDELETE FROM notes;",
            cancellation: SQLCancellationToken()
        )
        XCTAssertEqual(failed.blocks.count, 1)
        XCTAssertEqual(failed.failure?.number, 2)
        XCTAssertEqual(failed.failure?.code, SQLITE_ERROR)
        XCTAssertEqual(failed.failure?.line, 2)
        XCTAssertNotNil(failed.failure?.column)
        let after = try await service.run("SELECT count(*) FROM notes", cancellation: SQLCancellationToken())
        XCTAssertEqual(after.blocks.first?.rows, [[.integer(2)]])

        let empty = try await service.run("  -- comment only", cancellation: SQLCancellationToken())
        XCTAssertTrue(empty.blocks.isEmpty)
        XCTAssertNotNil(empty.failure)
        let blank = try await service.run("", cancellation: SQLCancellationToken())
        XCTAssertTrue(blank.blocks.isEmpty)
        XCTAssertNotNil(blank.failure)
        let parameters = try await service.run("SELECT ?", cancellation: SQLCancellationToken())
        XCTAssertEqual(parameters.failure?.code, SQLITE_RANGE)
    }

    func testExplicitTransactionsAndReturningLimit() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let service = SQLService(session: fixture.session)
        let rolledBack = try await service.run(
            "BEGIN; INSERT INTO sample(id) VALUES (1); ROLLBACK; SELECT count(*) FROM sample;",
            cancellation: SQLCancellationToken()
        )
        XCTAssertNil(rolledBack.failure)
        XCTAssertEqual(rolledBack.blocks.count, 4)
        XCTAssertEqual(rolledBack.blocks.last?.rows, [[.integer(0)]])
        let committed = try await service.run(
            "BEGIN; INSERT INTO sample(id) VALUES (1); COMMIT; SELECT count(*) FROM sample;",
            cancellation: SQLCancellationToken()
        )
        XCTAssertNil(committed.failure)
        XCTAssertEqual(committed.blocks.last?.rows, [[.integer(1)]])

        let large = try await service.run(
            """
            WITH RECURSIVE seq(n) AS (SELECT 2 UNION ALL SELECT n + 1 FROM seq WHERE n < 206)
            INSERT INTO sample(id) SELECT n FROM seq RETURNING id;
            SELECT count(*) FROM sample;
            """,
            cancellation: SQLCancellationToken()
        )
        XCTAssertNil(large.failure)
        XCTAssertEqual(large.blocks.count, 2)
        XCTAssertEqual(large.blocks[0].rowCount, 205)
        XCTAssertEqual(large.blocks[0].rows.count, 200)
        XCTAssertTrue(large.blocks[0].isTruncated)
        XCTAssertEqual(large.blocks[1].rows, [[.integer(206)]])
    }

    func testCancellationLeavesSessionUsable() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let service = SQLService(session: fixture.session)
        let token = SQLCancellationToken()
        let running = Task {
            try await service.run(
                "WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq) SELECT sum(n) FROM seq;",
                cancellation: token
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        token.cancel()
        let cancelled = try await running.value
        XCTAssertEqual(cancelled.failure?.code, SQLITE_INTERRUPT)
        let after = try await service.run("SELECT 42", cancellation: SQLCancellationToken())
        XCTAssertNil(after.failure)
        XCTAssertEqual(after.blocks.first?.rows, [[.integer(42)]])
    }

    func testBusyDatabaseReportsErrorAndRecovers() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }
        let second = try DatabaseSession(url: fixture.directory.appendingPathComponent("fixture.sqlite"))
        defer { Task { try? await second.close() } }
        try await fixture.session.execute("BEGIN EXCLUSIVE")
        let blocked = try await SQLService(session: second).run(
            "INSERT INTO sample(id) VALUES (1)", cancellation: SQLCancellationToken()
        )
        XCTAssertEqual(blocked.failure?.code, SQLITE_BUSY)
        XCTAssertFalse(blocked.failure?.message.isEmpty ?? true)
        try await fixture.session.execute("ROLLBACK")
        let retried = try await SQLService(session: second).run(
            "INSERT INTO sample(id) VALUES (1)", cancellation: SQLCancellationToken()
        )
        XCTAssertNil(retried.failure)
    }

    func testClosingLibraryCancelsRunningSQL() async throws {
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
        let running = Task {
            try await SQLService(session: session).run(
                "WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq) SELECT sum(n) FROM seq;",
                cancellation: SQLCancellationToken()
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        try await library.closeActive()
        let stopped = try await running.value
        XCTAssertEqual(stopped.failure?.code, SQLITE_INTERRUPT)
        _ = try await library.open(entry.id)
        let reopened = try await library.session(for: entry.id)
        let after = try await SQLService(session: reopened).run("SELECT 1", cancellation: SQLCancellationToken())
        XCTAssertEqual(after.blocks.first?.rows, [[.integer(1)]])
        try await library.closeActive()
    }

    func testImportedCopyWritesPersistWithoutChangingSource() async throws {
        let fixture = try await SQLiteFixture.make()
        let source = fixture.directory.appendingPathComponent("fixture.sqlite")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Task { await fixture.remove() }
            try? FileManager.default.removeItem(at: root)
        }
        try await fixture.session.close()
        let originalBytes = try Data(contentsOf: source)
        let library = try DatabaseLibrary(rootURL: root)
        let entry = try await library.importDatabase(from: source)
        _ = try await library.open(entry.id)
        let session = try await library.session(for: entry.id)
        let service = SQLService(session: session)
        let changed = try await service.run(
            """
            CREATE TABLE added (value TEXT);
            CREATE INDEX added_value ON added(value);
            INSERT INTO added VALUES ('kept'), ('discard');
            UPDATE added SET value = 'updated' WHERE value = 'kept';
            DELETE FROM added WHERE value = 'discard';
            """,
            cancellation: SQLCancellationToken()
        )
        XCTAssertNil(changed.failure)
        XCTAssertEqual(changed.blocks.count, 5)
        XCTAssertEqual(changed.blocks[3].affectedRows, 1)
        XCTAssertEqual(changed.blocks[4].affectedRows, 1)
        let catalog = try await SchemaService(session: session).loadCatalog()
        XCTAssertTrue(catalog.contains { $0.name == "added" })
        XCTAssertTrue(catalog.contains { $0.name == "added_value" })
        let dropped = try await service.run("DROP INDEX added_value", cancellation: SQLCancellationToken())
        XCTAssertNil(dropped.failure)
        let afterDrop = try await SchemaService(session: session).loadCatalog()
        XCTAssertFalse(afterDrop.contains { $0.name == "added_value" })
        try await library.closeActive()
        _ = try await library.open(entry.id)
        let reopened = try await library.session(for: entry.id)
        let rows = try await SQLService(session: reopened).run("SELECT value FROM added", cancellation: SQLCancellationToken())
        XCTAssertEqual(rows.blocks.first?.rows, [[.text("updated")]])
        let removed = try await SQLService(session: reopened).run("DROP TABLE added", cancellation: SQLCancellationToken())
        XCTAssertNil(removed.failure)
        let finalCatalog = try await SchemaService(session: reopened).loadCatalog()
        XCTAssertFalse(finalCatalog.contains { $0.name == "added" })
        try await library.closeActive()
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    }
}
