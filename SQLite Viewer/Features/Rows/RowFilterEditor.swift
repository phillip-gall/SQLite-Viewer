import SwiftUI

struct RowFilterEditor: View {
    let columns: [RowColumn]
    let editing: RowFilter?
    let onSave: (RowFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: RowFilterEditorModel

    init(columns: [RowColumn], editing: RowFilter?, onSave: @escaping (RowFilter) -> Void) {
        self.columns = columns
        self.editing = editing
        self.onSave = onSave
        _model = StateObject(wrappedValue: RowFilterEditorModel(columns: columns, editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Column", selection: $model.column) {
                    ForEach(columns, id: \.name) { Text($0.name).tag($0.name) }
                }
                .accessibilityIdentifier("filter-column")
                Picker("Condition", selection: $model.operation) {
                    ForEach(RowFilter.Operator.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .accessibilityIdentifier("filter-operation")
                if model.operation.needsValue {
                    Picker("Value type", selection: $model.valueKind) {
                        ForEach(RowFilterEditorModel.ValueKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("filter-value-type")
                    TextField("Value", text: $model.enteredValue)
                        .accessibilityIdentifier("filter-value")
                }
                if model.selectedIsBlob {
                    Text("BLOB columns support NULL checks only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.operation == .contains {
                    Text("Contains treats % and _ literally. Letter case follows SQLite LIKE rules.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage = model.errorMessage {
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
                    Button("Apply") {
                        if let filter = model.makeFilter() { onSave(filter); dismiss() }
                    }
                        .accessibilityIdentifier("apply-filter")
                }
            }
        }
    }

}
