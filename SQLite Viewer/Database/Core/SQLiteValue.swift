import Foundation

nonisolated enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

nonisolated enum SQLIdentifier {
    static func quote(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

nonisolated struct SQLiteResult: Sendable {
    let columns: [String]
    let rows: [[SQLiteValue]]
    let rowCount: Int
    let truncated: Bool
    let affectedRows: Int64
}

nonisolated struct SQLiteError: Error, LocalizedError, Sendable {
    let code: Int32
    let extendedCode: Int32
    let message: String
    let sql: String

    var errorDescription: String? { message }
}
