import SwiftUI

struct RowFilterEditor: View {
    let columns: [RowColumn]
    let editing: RowFilter?
    let onSave: (RowFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var column: String
    @State private var operation: RowFilter.Operator
    @State private var valueKind: ValueKind
    @State private var enteredValue: String
    @State private var errorMessage: String?

    private enum ValueKind: String, CaseIterable {
        case text = "Text"
        case integer = "Integer"
        case real = "Real"
    }

    init(columns: [RowColumn], editing: RowFilter?, onSave: @escaping (RowFilter) -> Void) {
        self.columns = columns
        self.editing = editing
        self.onSave = onSave
        _column = State(initialValue: editing?.column ?? columns.first?.name ?? "")
        _operation = State(initialValue: editing?.operation ?? .equals)
        switch editing?.value {
        case .integer(let number):
            _valueKind = State(initialValue: .integer)
            _enteredValue = State(initialValue: String(number))
        case .real(let number):
            _valueKind = State(initialValue: .real)
            _enteredValue = State(initialValue: String(number))
        case .text(let text):
            _valueKind = State(initialValue: .text)
            _enteredValue = State(initialValue: text)
        default:
            let type = columns.first { $0.name == (editing?.column ?? columns.first?.name) }?.declaredType.uppercased() ?? ""
            _valueKind = State(initialValue: type.contains("INT") ? .integer :
                (type.contains("REAL") || type.contains("DOUBLE") || type.contains("FLOAT") ? .real : .text))
            _enteredValue = State(initialValue: "")
        }
    }

    private var selectedIsBlob: Bool {
        columns.first { $0.name == column }?.declaredType.uppercased().contains("BLOB") == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Column", selection: $column) {
                    ForEach(columns, id: \.name) { Text($0.name).tag($0.name) }
                }
                .accessibilityIdentifier("filter-column")
                Picker("Condition", selection: $operation) {
                    ForEach(RowFilter.Operator.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .accessibilityIdentifier("filter-operation")
                if operation.needsValue {
                    Picker("Value type", selection: $valueKind) {
                        ForEach(ValueKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("filter-value-type")
                    TextField("Value", text: $enteredValue)
                        .accessibilityIdentifier("filter-value")
                }
                if selectedIsBlob {
                    Text("BLOB columns support NULL checks only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if operation == .contains {
                    Text("Contains treats % and _ literally. Letter case follows SQLite LIKE rules.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                        .accessibilityIdentifier("filter-error")
                }
            }
            .navigationTitle(editing == nil ? "Add filter" : "Edit filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .accessibilityIdentifier("apply-filter")
                }
            }
        }
    }

    private func apply() {
        guard !column.isEmpty else { errorMessage = "Choose a column."; return }
        if selectedIsBlob && operation.needsValue {
            errorMessage = "BLOB columns support NULL checks only."
            return
        }
        let value: SQLiteValue?
        if !operation.needsValue {
            value = nil
        } else {
            guard !enteredValue.isEmpty else { errorMessage = "Enter a value."; return }
            switch valueKind {
            case .text: value = .text(enteredValue)
            case .integer:
                guard let number = Int64(enteredValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    errorMessage = "Enter a valid 64-bit integer."
                    return
                }
                value = .integer(number)
            case .real:
                guard let number = Double(enteredValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                      number.isFinite else {
                    errorMessage = "Enter a valid finite number."
                    return
                }
                value = .real(number)
            }
            if operation == .contains, valueKind != .text {
                errorMessage = "Contains needs a text value."
                return
            }
        }
        onSave(RowFilter(id: editing?.id ?? UUID(), column: column,
                         operation: operation, value: value))
        dismiss()
    }
}
