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

nonisolated struct SchemaColumn: Identifiable, Equatable, Sendable {
    enum Visibility: Int64, Sendable {
        case normal = 0
        case virtualTableHidden = 1
        case generatedVirtual = 2
        case generatedStored = 3
    }

    let cid: Int64
    let name: String
    let declaredType: String
    let notNull: Bool
    let defaultSQL: String?
    let primaryKeyPosition: Int64
    let visibility: Visibility

    var id: Int64 { cid }
}

nonisolated struct TableViewDetail: Equatable, Sendable {
    enum TableKind: String, Sendable {
        case ordinary = "table"
        case virtual = "virtual"
        case shadow = "shadow"
    }

    let object: SchemaObject
    let columns: [SchemaColumn]
    let tableKind: TableKind?
    let withoutRowID: Bool?
    let strict: Bool?
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

    func loadTableViewDetail(_ selected: SchemaObject) async throws -> TableViewDetail {
        guard selected.kind == .table || selected.kind == .view else {
            throw SchemaError.unsupportedObject(selected.name)
        }
        guard let object = try await loadCatalog().first(where: { $0.id == selected.id }) else {
            throw SchemaError.missingObject(selected.name)
        }
        let quoted = SQLIdentifier.quote(object.name)
        let result = try await session.execute("PRAGMA main.table_xinfo(\(quoted))", rowLimit: Int.max)
        guard !result.truncated else { throw SchemaError.invalidResult("Columns for \(object.name) were truncated.") }
        let decoder = try SchemaRowDecoder(result)
        let columns = try result.rows.map { row in
            let hidden = try decoder.requiredInteger("hidden", in: row)
            guard let visibility = SchemaColumn.Visibility(rawValue: hidden) else {
                throw SchemaError.invalidResult("Unknown hidden code \(hidden) for \(object.name).")
            }
            return SchemaColumn(
                cid: try decoder.requiredInteger("cid", in: row),
                name: try decoder.text("name", in: row),
                declaredType: try decoder.text("type", in: row),
                notNull: try decoder.requiredInteger("notnull", in: row) != 0,
                defaultSQL: try decoder.optionalText("dflt_value", in: row),
                primaryKeyPosition: try decoder.requiredInteger("pk", in: row),
                visibility: visibility
            )
        }
        if object.kind == .view {
            return TableViewDetail(object: object, columns: columns, tableKind: nil,
                                   withoutRowID: nil, strict: nil)
        }
        let tableList = try await session.execute("PRAGMA main.table_list(\(quoted))", rowLimit: Int.max)
        guard !tableList.truncated else { throw SchemaError.invalidResult("Table properties were truncated.") }
        let tableDecoder = try SchemaRowDecoder(tableList)
        for row in tableList.rows {
            guard try tableDecoder.text("schema", in: row) == "main",
                  try tableDecoder.text("name", in: row) == object.name else { continue }
            let type = try tableDecoder.text("type", in: row)
            guard let kind = TableViewDetail.TableKind(rawValue: type) else {
                throw SchemaError.invalidResult("Unknown table type \(type) for \(object.name).")
            }
            return TableViewDetail(
                object: object, columns: columns, tableKind: kind,
                withoutRowID: try tableDecoder.requiredInteger("wr", in: row) != 0,
                strict: try tableDecoder.requiredInteger("strict", in: row) != 0
            )
        }
        throw SchemaError.missingObject(object.name)
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
