import Foundation

/// The only owner of a SQLite connection and its prepared statements.
actor DatabaseSession {
    private var connection: OpaquePointer?

    init(url: URL, createIfNeeded: Bool = false) throws {
        guard url.isFileURL else {
            throw SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                              message: "A local database file is required.", sql: "")
        }

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | (createIfNeeded ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &opened, flags, nil)
        guard status == SQLITE_OK, let opened else {
            let error = Self.makeError(opened, sql: "", fallbackCode: status)
            if let opened { sqlite3_close(opened) }
            throw error
        }
        sqlite3_extended_result_codes(opened, 1)
        connection = opened
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func close() throws {
        guard let connection else { return }
        let status = sqlite3_close(connection)
        guard status == SQLITE_OK else {
            throw Self.makeError(connection, sql: "", fallbackCode: status)
        }
        self.connection = nil
    }

    /// Runs one prepared statement. Every row is stepped, but at most `rowLimit` rows are retained.
    @discardableResult
    func execute(_ sql: String, bindings: [SQLiteValue] = [], rowLimit: Int = 100) throws -> SQLiteResult {
        guard let connection else {
            throw SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                              message: "The database is closed.", sql: sql)
        }
        guard rowLimit >= 0 else {
            throw SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                              message: "Row limit must not be negative.", sql: sql)
        }

        var statement: OpaquePointer?
        var tail = ""
        let status = sql.withCString { source in
            var remainder: UnsafePointer<CChar>?
            let status = sqlite3_prepare_v2(connection, source, -1, &statement, &remainder)
            if let remainder { tail = String(cString: remainder) }
            return status
        }
        guard status == SQLITE_OK else {
            let error = Self.makeError(connection, sql: sql, fallbackCode: status)
            if let statement { sqlite3_finalize(statement) }
            throw error
        }
        guard let statement else {
            throw SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                              message: "SQL contains no statement.", sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SQLiteError(code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                              message: "Execute one SQL statement at a time.", sql: sql)
        }
        guard sqlite3_bind_parameter_count(statement) == bindings.count else {
            throw SQLiteError(code: SQLITE_RANGE, extendedCode: SQLITE_RANGE,
                              message: "The number of bound values does not match the statement.", sql: sql)
        }
        for (offset, value) in bindings.enumerated() {
            let bindStatus = Self.bind(value, to: statement, at: Int32(offset + 1))
            guard bindStatus == SQLITE_OK else {
                throw Self.makeError(connection, sql: sql, fallbackCode: bindStatus)
            }
        }

        let columnCount = Int(sqlite3_column_count(statement))
        let columns = (0..<columnCount).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
        let isReadOnly = sqlite3_stmt_readonly(statement) != 0
        let changesBefore = sqlite3_total_changes64(connection)
        var rows: [[SQLiteValue]] = []
        var rowCount = 0

        while true {
            let stepStatus = sqlite3_step(statement)
            if stepStatus == SQLITE_DONE { break }
            guard stepStatus == SQLITE_ROW else {
                throw Self.makeError(connection, sql: sql, fallbackCode: stepStatus)
            }
            rowCount += 1
            if rows.count < rowLimit {
                rows.append(try (0..<columnCount).map {
                    try Self.readValue(from: statement, at: Int32($0), connection: connection, sql: sql)
                })
            }
        }
        return SQLiteResult(columns: columns, rows: rows, rowCount: rowCount,
                            truncated: rowCount > rows.count,
                            affectedRows: isReadOnly ? 0 : sqlite3_total_changes64(connection) - changesBefore)
    }

    static func compileOptionUsed(_ option: String) -> Bool {
        sqlite3_compileoption_used(option) != 0
    }

    private static func bind(_ value: SQLiteValue, to statement: OpaquePointer, at index: Int32) -> Int32 {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        switch value {
        case .null:
            return sqlite3_bind_null(statement, index)
        case .integer(let number):
            return sqlite3_bind_int64(statement, index, number)
        case .real(let number):
            return sqlite3_bind_double(statement, index, number)
        case .text(let string):
            let bytes = string.utf8CString
            return bytes.withUnsafeBufferPointer {
                sqlite3_bind_text(statement, index, $0.baseAddress, Int32(bytes.count - 1), transient)
            }
        case .blob(let data):
            if data.isEmpty { return sqlite3_bind_zeroblob(statement, index, 0) }
            return data.withUnsafeBytes {
                sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient)
            }
        }
    }

    private static func readValue(from statement: OpaquePointer, at index: Int32,
                                  connection: OpaquePointer, sql: String) throws -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard let bytes = sqlite3_column_text(statement, index) else {
                throw makeError(connection, sql: sql, fallbackCode: SQLITE_NOMEM)
            }
            return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: length))
        default:
            return .null
        }
    }

    private static func makeError(_ connection: OpaquePointer?, sql: String, fallbackCode: Int32) -> SQLiteError {
        guard let connection else {
            return SQLiteError(code: fallbackCode & 0xff, extendedCode: fallbackCode,
                               message: String(cString: sqlite3_errstr(fallbackCode)), sql: sql)
        }
        let extendedCode = sqlite3_extended_errcode(connection)
        return SQLiteError(code: extendedCode & 0xff, extendedCode: extendedCode,
                           message: String(cString: sqlite3_errmsg(connection)), sql: sql)
    }
}
