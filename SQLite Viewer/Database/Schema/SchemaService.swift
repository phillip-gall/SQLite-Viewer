import Foundation

nonisolated enum SchemaError: LocalizedError, Sendable {
    case invalidResult(String)
    case missingObject(String)
    case unsupportedObject(String)

    var errorDescription: String? {
        switch self {
        case .invalidResult(let detail): "Could not read schema metadata. \(detail)"
        case .missingObject(let name): "The schema object \(name) no longer exists. Refresh the schema."
        case .unsupportedObject(let name): "Schema details are not available for \(name)."
        }
    }
}

nonisolated struct SchemaObject: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case table, view, index, trigger
    }

    let kind: Kind
    let name: String
    let tableName: String
    let rootPage: Int64?
    let sql: String?
    let isInternal: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}

/// Reads only the main schema through the connection owned by DatabaseSession.
struct SchemaService: Sendable {
    let session: DatabaseSession

    func loadCatalog() async throws -> [SchemaObject] {
        var objects: [SchemaObject] = []
        let pageSize = 100
        while true {
            let result = try await session.execute(
                """
                SELECT type, name, tbl_name, rootpage, sql FROM main.sqlite_schema
                WHERE type IN ('table', 'view', 'index', 'trigger')
                ORDER BY type COLLATE BINARY, name COLLATE BINARY
                LIMIT ? OFFSET ?
                """,
                bindings: [.integer(Int64(pageSize)), .integer(Int64(objects.count))],
                rowLimit: pageSize
            )
            guard !result.truncated else { throw SchemaError.invalidResult("Catalog page was truncated.") }
            let decoder = try SchemaRowDecoder(result)
            for row in result.rows {
                guard let kind = SchemaObject.Kind(rawValue: try decoder.text("type", in: row)),
                      let root = try decoder.integer("rootpage", in: row) else {
                    throw SchemaError.invalidResult("An object has an unknown type or root page.")
                }
                let name = try decoder.text("name", in: row)
                objects.append(SchemaObject(
                    kind: kind, name: name, tableName: try decoder.text("tbl_name", in: row),
                    rootPage: root > 0 ? root : nil, sql: try decoder.optionalText("sql", in: row),
                    isInternal: name.lowercased().hasPrefix("sqlite_")
                ))
            }
            if result.rows.count < pageSize { return objects }
        }
    }
}

/// Fails on missing columns and unexpected SQLite types instead of silently dropping metadata.
nonisolated struct SchemaRowDecoder {
    private let positions: [String: Int]

    init(_ result: SQLiteResult) throws {
        positions = Dictionary(uniqueKeysWithValues: result.columns.enumerated().map { ($0.element.lowercased(), $0.offset) })
    }

    func value(_ name: String, in row: [SQLiteValue]) throws -> SQLiteValue {
        guard let position = positions[name.lowercased()], row.indices.contains(position) else {
            throw SchemaError.invalidResult("Missing \(name) column.")
        }
        return row[position]
    }

    func text(_ name: String, in row: [SQLiteValue]) throws -> String {
        guard case .text(let text) = try value(name, in: row) else {
            throw SchemaError.invalidResult("Invalid \(name) value.")
        }
        return text
    }

    func optionalText(_ name: String, in row: [SQLiteValue]) throws -> String? {
        switch try value(name, in: row) {
        case .null: nil
        case .text(let text): text
        default: throw SchemaError.invalidResult("Invalid \(name) value.")
        }
    }

    func integer(_ name: String, in row: [SQLiteValue]) throws -> Int64? {
        switch try value(name, in: row) {
        case .null: nil
        case .integer(let number): number
        default: throw SchemaError.invalidResult("Invalid \(name) value.")
        }
    }

    func requiredInteger(_ name: String, in row: [SQLiteValue]) throws -> Int64 {
        guard let number = try integer(name, in: row) else {
            throw SchemaError.invalidResult("Missing \(name) value.")
        }
        return number
    }
}
