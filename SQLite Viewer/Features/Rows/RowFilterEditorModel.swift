import Combine
import Foundation

@MainActor
final class RowFilterEditorModel: ObservableObject {
    let columns: [RowColumn]
    let editing: RowFilter?
    @Published var column: String
    @Published var operation: RowFilter.Operator
    @Published var valueKind: ValueKind
    @Published var enteredValue: String
    @Published var errorMessage: String?

    enum ValueKind: String, CaseIterable {
        case text = "Text"
        case integer = "Integer"
        case real = "Real"
    }

    init(columns: [RowColumn], editing: RowFilter?) {
        self.columns = columns
        self.editing = editing
        column = editing?.column ?? columns.first?.name ?? ""
        operation = editing?.operation ?? .equals
        switch editing?.value {
        case .integer(let number):
            valueKind = .integer
            enteredValue = String(number)
        case .real(let number):
            valueKind = .real
            enteredValue = String(number)
        case .text(let text):
            valueKind = .text
            enteredValue = text
        default:
            let type = columns.first { $0.name == (editing?.column ?? columns.first?.name) }?.declaredType.uppercased() ?? ""
            valueKind = type.contains("INT") ? .integer :
                (type.contains("REAL") || type.contains("DOUBLE") || type.contains("FLOAT") ? .real : .text)
            enteredValue = ""
        }
    }

    var selectedIsBlob: Bool {
        columns.first { $0.name == column }?.declaredType.uppercased().contains("BLOB") == true
    }

    func makeFilter() -> RowFilter? {
        guard !column.isEmpty else { errorMessage = "Choose a column."; return nil }
        if selectedIsBlob && operation.needsValue {
            errorMessage = "BLOB columns support NULL checks only."
            return nil
        }
        let value: SQLiteValue?
        if !operation.needsValue {
            value = nil
        } else {
            guard !enteredValue.isEmpty else { errorMessage = "Enter a value."; return nil }
            switch valueKind {
            case .text: value = .text(enteredValue)
            case .integer:
                guard let number = Int64(enteredValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    errorMessage = "Enter a valid 64-bit integer."
                    return nil
                }
                value = .integer(number)
            case .real:
                guard let number = Double(enteredValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                      number.isFinite else {
                    errorMessage = "Enter a valid finite number."
                    return nil
                }
                value = .real(number)
            }
            if operation == .contains, valueKind != .text {
                errorMessage = "Contains needs a text value."
                return nil
            }
        }
        errorMessage = nil
        return RowFilter(id: editing?.id ?? UUID(), column: column, operation: operation, value: value)
    }
}
