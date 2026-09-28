import Foundation

nonisolated enum TableCountError: LocalizedError, Sendable {
    case unsupportedObject(String)
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedObject(let name): "Row counts are not available for \(name)."
        case .invalidResult(let name): "Could not read the row count for \(name)."
        }
    }
}

struct TableCountService: Sendable {
    let session: DatabaseSession

    func count(_ object: SchemaObject) async throws -> Int64 {
        guard object.kind == .table else { throw TableCountError.unsupportedObject(object.name) }
        let result = try await session.execute(
            "SELECT COUNT(*) FROM main.\(SQLIdentifier.quote(object.name))", rowLimit: 1
        )
        return try Self.decode(result, table: object.name)
    }

    static func decode(_ result: SQLiteResult, table name: String) throws -> Int64 {
        guard result.rowCount == 1, result.rows.count == 1,
              result.rows[0].count == 1,
              case .integer(let count) = result.rows[0][0], count >= 0 else {
            throw TableCountError.invalidResult(name)
        }
        return count
    }
}
