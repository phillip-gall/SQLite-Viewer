import Foundation

nonisolated struct RowColumn: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let declaredType: String
}

nonisolated struct RowSort: Equatable, Sendable {
    let column: String
    let descending: Bool
}

nonisolated struct RowPage: Sendable {
    let object: SchemaObject
    let columns: [RowColumn]
    let rows: [[SQLiteValue]]
    let number: Int
    let hasNext: Bool
    let hasStableOrder: Bool
}

nonisolated enum RowsError: LocalizedError, Sendable {
    case invalidPage
    case invalidSort(String)
    case unsupportedObject(String)
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .invalidPage: "The requested row page is out of range."
        case .invalidSort(let name): "The sort column \(name) no longer exists."
        case .unsupportedObject(let name): "Rows are not available for \(name)."
        case .invalidResult(let detail): "Could not read table rows. \(detail)"
        }
    }
}

/// Reads one page through the shared SQLite connection. A page retains at most 100 rows.
struct RowsService: Sendable {
    static let pageSize = 100
    let session: DatabaseSession

    func loadPage(for object: SchemaObject, number: Int = 1, sort: RowSort? = nil,
                  filters: [RowFilter] = []) async throws -> RowPage {
        guard object.kind == .table || object.kind == .view else {
            throw RowsError.unsupportedObject(object.name)
        }
        guard number > 0, number - 1 <= Int64.max / Int64(Self.pageSize) else { throw RowsError.invalidPage }
        let detail = try await SchemaService(session: session).loadTableViewDetail(object)
        let columns = detail.columns.enumerated().map {
            RowColumn(id: $0.offset, name: $0.element.name, declaredType: $0.element.declaredType)
        }
        guard !columns.isEmpty else { throw RowsError.invalidResult("The object has no columns.") }
        if let sort, !columns.contains(where: { $0.name == sort.column }) {
            throw RowsError.invalidSort(sort.column)
        }
        let predicate = try RowPredicate.compile(filters, columns: detail.columns)

        let stableKeys = try await stableKeys(for: detail)
        var order: [String] = []
        if let sort {
            order.append("\(SQLIdentifier.quote(sort.column)) \(sort.descending ? "DESC" : "ASC")")
        }
        for key in stableKeys where key != sort?.column {
            order.append("\(SQLIdentifier.quote(key)) ASC")
        }
        let projection = columns.map { SQLIdentifier.quote($0.name) }.joined(separator: ", ")
        let orderSQL = order.isEmpty ? "" : " ORDER BY " + order.joined(separator: ", ")
        let sql = "SELECT \(projection) FROM main.\(SQLIdentifier.quote(object.name))\(predicate.sql)\(orderSQL) LIMIT ? OFFSET ?"
        let offset = Int64(number - 1) * Int64(Self.pageSize)
        let result = try await session.execute(
            sql, bindings: predicate.bindings + [.integer(Int64(Self.pageSize + 1)), .integer(offset)],
            rowLimit: Self.pageSize + 1
        )
        guard !result.truncated, result.columns.count == columns.count else {
            throw RowsError.invalidResult("The page result changed while loading.")
        }
        return RowPage(object: detail.object, columns: columns,
                       rows: Array(result.rows.prefix(Self.pageSize)), number: number,
                       hasNext: result.rows.count > Self.pageSize, hasStableOrder: !stableKeys.isEmpty)
    }

    private func stableKeys(for detail: TableViewDetail) async throws -> [String] {
        guard detail.object.kind == .table, detail.tableKind == .ordinary else { return [] }
        let primaryKey = detail.columns.filter { $0.primaryKeyPosition > 0 }
            .sorted { $0.primaryKeyPosition < $1.primaryKeyPosition }
        if detail.withoutRowID == true { return primaryKey.map(\.name) }

        let names = Set(detail.columns.map { $0.name.lowercased() })
        if let alias = ["rowid", "_rowid_", "oid"].first(where: { !names.contains($0) }) {
            return [alias]
        }
        guard primaryKey.count == 1, primaryKey[0].declaredType.uppercased() == "INTEGER" else {
            return []
        }
        // INTEGER PRIMARY KEY DESC creates an index instead of aliasing rowid.
        let indexes = try await session.execute(
            "PRAGMA main.index_list(\(SQLIdentifier.quote(detail.object.name)))", rowLimit: Int.max
        )
        guard !indexes.truncated else { throw RowsError.invalidResult("Index metadata was truncated.") }
        let decoder = try SchemaRowDecoder(indexes)
        for row in indexes.rows {
            if try decoder.text("origin", in: row) == "pk" { return [] }
        }
        return [primaryKey[0].name]
    }
}
