import Foundation

nonisolated struct SQLStatementBlock: Identifiable, Sendable {
    let number: Int
    let sql: String
    let columns: [String]
    let rows: [[SQLiteValue]]
    let rowCount: Int64
    let affectedRows: Int64
    let elapsedSeconds: Double

    var id: Int { number }
    var hasColumns: Bool { !columns.isEmpty }
    var isTruncated: Bool { rowCount > rows.count }
}

nonisolated struct SQLStatementFailure: Sendable {
    let number: Int
    let code: Int32
    let extendedCode: Int32
    let message: String
    let line: Int?
    let column: Int?

    var isCancellation: Bool { code == SQLITE_INTERRUPT }
}

nonisolated struct SQLScriptResult: Sendable {
    let blocks: [SQLStatementBlock]
    let failure: SQLStatementFailure?
}

/// The UI can set this while DatabaseSession is busy stepping on its actor.
nonisolated final class SQLCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// This context remains owned by DatabaseSession for the connection's lifetime.
nonisolated final class SQLProgressContext: @unchecked Sendable {
    private let lock = NSLock()
    private var active: SQLCancellationToken?
    private var closing = false

    func setActive(_ token: SQLCancellationToken?) {
        lock.lock()
        active = token
        let shouldCancel = closing && token != nil
        lock.unlock()
        if shouldCancel { token?.cancel() }
    }

    var shouldInterrupt: Bool {
        lock.lock()
        let token = active
        lock.unlock()
        return token?.isCancelled ?? false
    }

    func cancelActive() {
        lock.lock()
        closing = true
        let token = active
        lock.unlock()
        token?.cancel()
    }

    func clearClosing() {
        lock.lock()
        closing = false
        lock.unlock()
    }
}

struct SQLService: Sendable {
    let session: DatabaseSession

    func run(_ script: String, cancellation: SQLCancellationToken) async throws -> SQLScriptResult {
        try await session.executeScript(script, cancellation: cancellation)
    }
}
