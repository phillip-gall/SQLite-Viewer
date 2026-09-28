import SwiftUI

struct SQLConsoleView: View {
    let database: LibraryDatabase
    @ObservedObject var model: SQLConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imported copy: \(database.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            SQLTextEditor(text: $model.draft)
                .frame(height: 170)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Run", systemImage: "play.fill") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    model.run()
                }
                .disabled(model.isRunning)
                .accessibilityIdentifier("run-sql")
                if model.isRunning {
                    Button("Cancel", systemImage: "stop.fill") { model.cancel() }
                        .disabled(model.isCancelling)
                        .accessibilityIdentifier("cancel-sql")
                    ProgressView(model.isCancelling ? "Cancelling" : "Running")
                } else if let result = model.result {
                    Text(result.failure == nil ? "Finished" : "Stopped")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            if let failure = model.result?.failure {
                Label("Statement \(failure.number): \(failure.message)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .accessibilityIdentifier("sql-error-summary")
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .accessibilityIdentifier("sql-error-summary")
            }

            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let result = model.result {
                        ForEach(result.blocks) { block in
                            resultBlock(block)
                        }
                        if let failure = result.failure { failureView(failure) }
                    } else if !model.isRunning && model.errorMessage == nil {
                        ContentUnavailableView("No results", systemImage: "chevron.left.forwardslash.chevron.right",
                                               description: Text("Run SQL against this imported copy."))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .navigationTitle("SQL")
    }

    private func resultBlock(_ block: SQLStatementBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statement \(block.number)")
                .font(.headline)
                .accessibilityIdentifier("sql-statement-\(block.number)")
            Text(block.sql)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(block.hasColumns ? "\(block.rowCount) rows · \(elapsed(block.elapsedSeconds))" :
                    "\(block.affectedRows) affected rows · \(elapsed(block.elapsedSeconds))")
                .font(.subheadline)
            if block.isTruncated {
                Text("Showing the first 200 of \(block.rowCount) rows. Rerun with LIMIT for a narrower result.")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("sql-truncated-\(block.number)")
            }
            if block.hasColumns {
                let descriptors = block.columns.enumerated().map {
                    RowColumn(id: $0.offset, name: $0.element, declaredType: "")
                }
                SQLiteValueGrid(columns: descriptors, rows: block.rows)
                    .frame(height: min(max(CGFloat(block.rows.count) * 44 + 55, 160), 360))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private func failureView(_ failure: SQLStatementFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(failure.isCancellation ? "Cancelled during statement \(failure.number)" :
                  "Statement \(failure.number) failed", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityIdentifier("sql-error")
            Text("SQLite code \(failure.code)\(failure.extendedCode == failure.code ? "" : " (extended \(failure.extendedCode))")")
                .font(.caption)
            Text(failure.message).textSelection(.enabled)
            if let line = failure.line, let column = failure.column {
                Text("Line \(line), column \(column)")
                    .font(.caption)
            }
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func elapsed(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1_000)
    }
}

/// UITextView keeps SQL punctuation exactly as entered by disabling smart substitutions.
private struct SQLTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "sql-editor"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SQLTextEditor

        init(_ parent: SQLTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
