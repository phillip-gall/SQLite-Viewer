import Foundation

nonisolated struct RowFilter: Identifiable, Equatable, Sendable {
    enum Operator: String, CaseIterable, Sendable {
        case equals, notEquals, greater, greaterOrEqual, less, lessOrEqual
        case contains, isNull, isNotNull

        var sql: String {
            switch self {
            case .equals: "="
            case .notEquals: "!="
            case .greater: ">"
            case .greaterOrEqual: ">="
            case .less: "<"
            case .lessOrEqual: "<="
            case .contains: "LIKE"
            case .isNull: "IS NULL"
            case .isNotNull: "IS NOT NULL"
            }
        }

        var label: String {
            switch self {
            case .equals: "="
            case .notEquals: "≠"
            case .greater: ">"
            case .greaterOrEqual: "≥"
            case .less: "<"
            case .lessOrEqual: "≤"
            case .contains: "contains"
            case .isNull: "is NULL"
            case .isNotNull: "is not NULL"
            }
        }

        var needsValue: Bool { self != .isNull && self != .isNotNull }
    }

    let id: UUID
    let column: String
    let operation: Operator
    let value: SQLiteValue?

    init(id: UUID = UUID(), column: String, operation: Operator, value: SQLiteValue? = nil) {
        self.id = id
        self.column = column
        self.operation = operation
        self.value = value
    }
}

nonisolated enum RowFilterError: LocalizedError, Sendable {
    case missingColumn(String)
    case missingValue
    case unsupportedValue
    case invalidNumber

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name): "The filter column \(name) no longer exists."
        case .missingValue: "Enter a filter value."
        case .unsupportedValue: "This filter needs a text, integer, or real value. BLOB values are not supported."
        case .invalidNumber: "Enter a finite number."
        }
    }
}

nonisolated struct RowPredicate: Sendable {
    let sql: String
    let bindings: [SQLiteValue]

    static func compile(_ filters: [RowFilter], columns: [SchemaColumn]) throws -> RowPredicate {
        let names = Set(columns.map(\.name))
        var parts: [String] = []
        var bindings: [SQLiteValue] = []
        for filter in filters {
            guard names.contains(filter.column) else { throw RowFilterError.missingColumn(filter.column) }
            let column = SQLIdentifier.quote(filter.column)
            if !filter.operation.needsValue {
                parts.append("\(column) \(filter.operation.sql)")
                continue
            }
            guard let value = filter.value else { throw RowFilterError.missingValue }
            if columns.first(where: { $0.name == filter.column })?.declaredType.uppercased().contains("BLOB") == true {
                throw RowFilterError.unsupportedValue
            }
            if case .real(let number) = value, !number.isFinite {
                throw RowFilterError.invalidNumber
            }
            if filter.operation == .contains {
                guard case .text(let text) = value else { throw RowFilterError.unsupportedValue }
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                parts.append("\(column) LIKE ? ESCAPE '\\'")
                bindings.append(.text("%\(escaped)%"))
            } else if case .null = value {
                throw RowFilterError.unsupportedValue
            } else if case .blob = value {
                throw RowFilterError.unsupportedValue
            } else {
                parts.append("\(column) \(filter.operation.sql) ?")
                bindings.append(value)
            }
        }
        return RowPredicate(sql: parts.isEmpty ? "" : " WHERE " + parts.joined(separator: " AND "),
                            bindings: bindings)
    }
}
