//
//  SQLite_ViewerTests.swift
//  SQLite ViewerTests
//
//  Created by Phillip Gall on 27.09.26.
//

import XCTest
@testable import SQLite_Viewer

final class SQLite_ViewerTests: XCTestCase {
    func testAllValueTypesRoundTrip() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }

        let values: [SQLiteValue] = [
            .integer(Int64.max), .real(1.25), .text("a\u{0}b"),
            .blob(Data([0, 1, 254, 255])), .null
        ]
        try await fixture.session.execute(
            "INSERT INTO sample(number, decimal, label, payload, optional) VALUES (?, ?, ?, ?, ?)",
            bindings: values
        )
        let result = try await fixture.session.execute(
            "SELECT number, decimal, label, payload, optional FROM sample"
        )
        XCTAssertEqual(result.columns, ["number", "decimal", "label", "payload", "optional"])
        XCTAssertEqual(result.rows, [values])
        XCTAssertEqual(result.rowCount, 1)
        XCTAssertFalse(result.truncated)
    }

    func testIdentifierQuotingAndBoundValues() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }

        let name = "a\"b"
        XCTAssertEqual(SQLIdentifier.quote(name), "\"a\"\"b\"")
        try await fixture.session.execute("CREATE TABLE \(SQLIdentifier.quote(name)) (value TEXT)")
        try await fixture.session.execute("INSERT INTO \(SQLIdentifier.quote(name)) VALUES (?)",
                                          bindings: [.text("O'Reilly")])
        let result = try await fixture.session.execute("SELECT value FROM \(SQLIdentifier.quote(name))")
        XCTAssertEqual(result.rows, [[.text("O'Reilly")]])
    }

    func testErrorsCarrySQLiteCodesAndSQL() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }

        let sql = "SELECT * FROM missing_table"
        do {
            _ = try await fixture.session.execute(sql)
            XCTFail("Expected SQLite to reject the query")
        } catch let error as SQLiteError {
            XCTAssertEqual(error.code, 1)
            XCTAssertEqual(error.extendedCode, 1)
            XCTAssertEqual(error.sql, sql)
            XCTAssertTrue(error.message.contains("missing_table"))
        }
    }

    func testDbstatAndCompileOptions() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }

        XCTAssertTrue(DatabaseSession.compileOptionUsed("ENABLE_DBSTAT_VTAB"))
        XCTAssertTrue(DatabaseSession.compileOptionUsed("OMIT_LOAD_EXTENSION"))
        let result = try await fixture.session.execute("SELECT * FROM dbstat LIMIT 1")
        XCTAssertEqual(result.rows.count, 1)
    }

    func testResultRetentionLimit() async throws {
        let fixture = try await SQLiteFixture.make()
        defer { Task { await fixture.remove() } }

        for number in 0..<5 {
            try await fixture.session.execute("INSERT INTO sample(number) VALUES (?)",
                                              bindings: [.integer(Int64(number))])
        }
        let result = try await fixture.session.execute("SELECT number FROM sample ORDER BY number", rowLimit: 2)
        XCTAssertEqual(result.rows, [[.integer(0)], [.integer(1)]])
        XCTAssertEqual(result.rowCount, 5)
        XCTAssertTrue(result.truncated)
    }
}
