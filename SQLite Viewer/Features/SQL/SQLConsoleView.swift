import SwiftUI

struct SQLConsoleView: View {
    let database: LibraryDatabase
    @ObservedObject var model: SQLConsoleModel

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                SQLTextEditor(text: $model.draft)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(height: min(max(geometry.size.height * 0.36, 150), 300))
                    .overlay(alignment: .bottomTrailing) {
                        GlassControlBar {
                            if model.isRunning {
                                ProgressView().padding(.horizontal, 8)
                                SymbolButton(title: "Cancel", symbol: "stop.fill") { model.cancel() }
                                    .disabled(model.isCancelling)
                                    .accessibilityIdentifier("cancel-sql")
                            } else {
                                if let result = model.result {
                                    Text(result.failure == nil ? "Finished" : "Stopped")
                                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                                }
                                Button {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    model.run()
                                } label: {
                                    Label("Run", systemImage: "play.fill").padding(.horizontal, 12).frame(height: 44)
                                }
                                .accessibilityIdentifier("run-sql")
                            }
                        }
                        .padding(12)
                    }
                Divider()
                if let failure = model.result?.failure {
                    errorSummary("Statement \(failure.number): \(failure.message)")
                } else if let error = model.errorMessage { errorSummary(error) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if let result = model.result {
                            ForEach(result.blocks) { block in resultBlock(block) }
                            if let failure = result.failure { failureView(failure) }
                        } else if !model.isRunning && model.errorMessage == nil {
                            ContentUnavailableView("No results", systemImage: "chevron.left.forwardslash.chevron.right",
                                                   description: Text("Run SQL against this imported copy."))
                                .frame(minHeight: max(150, geometry.size.height * 0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(WorkspaceStyle.canvas)
    }

    private func errorSummary(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline).foregroundStyle(.red).padding(16)
            .accessibilityIdentifier("sql-error-summary")
    }

    private func resultBlock(_ block: SQLStatementBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statement \(block.number)")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .accessibilityIdentifier("sql-statement-\(block.number)")
            Text(block.sql)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
            Text(block.hasColumns ? "\(block.rowCount) rows · \(elapsed(block.elapsedSeconds))" :
                    "\(block.affectedRows) affected rows · \(elapsed(block.elapsedSeconds))")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            if block.isTruncated {
                Text("Showing the first 200 of \(block.rowCount) rows. Rerun with LIMIT for a narrower result.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
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

    }

    private func failureView(_ failure: SQLStatementFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(failure.isCancellation ? "Cancelled during statement \(failure.number)" :
                  "Statement \(failure.number) failed", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
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
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 72, right: 0)
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
