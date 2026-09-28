import SwiftUI

struct RowsWorkspaceView: View {
    let catalog: [SchemaObject]
    @ObservedObject var model: RowsWorkspaceModel

    private var browsable: [SchemaObject] {
        catalog.filter { $0.kind == .table || $0.kind == .view }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Menu {
                    ForEach(browsable) { object in
                        Button("\(object.name)\(object.kind == .view ? " (view)" : "")") {
                            model.select(object)
                        }
                    }
                } label: {
                    Label(model.selected?.name ?? "Choose a table", systemImage: "tablecells")
                        .lineLimit(1)
                }
                .accessibilityIdentifier("rows-object-picker")
                .disabled(browsable.isEmpty)
                Spacer()
                if model.selected != nil {
                    Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                        .accessibilityIdentifier("reload-rows")
                }
            }
            .padding(.horizontal)

            if let page = model.page {
                if !page.hasStableOrder {
                    Text("This object has no stable row key. Rows may move between pages.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                HStack {
                    Text("Page \(page.number)")
                    Spacer()
                    if model.sort != nil {
                        Button("Clear sort") { model.clearSort() }
                    }
                    Button("Previous") { model.showPage(page.number - 1) }
                        .disabled(page.number == 1)
                        .accessibilityIdentifier("rows-previous-page")
                    Button("Next") { model.showPage(page.number + 1) }
                        .disabled(!page.hasNext)
                        .accessibilityIdentifier("rows-next-page")
                }
                .padding(.horizontal)
                SQLiteValueGrid(columns: page.columns, rows: page.rows, sort: model.sort,
                                onSort: { model.setSort($0) },
                                firstRowNumber: (page.number - 1) * RowsService.pageSize + 1)
                    .id("\(page.object.id):\(page.number):\(model.sort?.column ?? ""): \(model.sort?.descending ?? false)")
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Rows unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { model.reload() }
                    if model.sort != nil { Button("Clear sort") { model.clearSort() } }
                }
                .accessibilityIdentifier("rows-error")
            } else if model.isLoading {
                Spacer()
                ProgressView("Loading rows")
                Spacer()
            } else {
                ContentUnavailableView("Choose a table", systemImage: "tablecells",
                                       description: Text("Select a table or view to browse its rows."))
            }
        }
        .navigationTitle("Rows")
    }
}

/// Shared by table browsing and the SQL result screen.
struct SQLiteValueGrid: View {
    let columns: [RowColumn]
    let rows: [[SQLiteValue]]
    var sort: RowSort? = nil
    var onSort: ((String) -> Void)? = nil
    var firstRowNumber = 1

    @State private var detail: CellDetail?
    private let cellWidth: CGFloat = 180
    private let numberWidth: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: numberWidth, alignment: .leading)
                    ForEach(columns) { column in
                        Group {
                            if let onSort {
                                Button {
                                    onSort(column.name)
                                } label: {
                                    headerText(column)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("sort-\(column.name)")
                            } else {
                                headerText(column)
                            }
                        }
                        .frame(width: cellWidth, alignment: .leading)
                    }
                }
                .font(.headline)
                .padding(8)
                .background(.regularMaterial)
                Divider()
                if rows.isEmpty {
                    ContentUnavailableView("No rows", systemImage: "tablecells")
                        .frame(minWidth: 280, minHeight: 200)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.indices, id: \.self) { rowIndex in
                                HStack(spacing: 0) {
                                    Text("\(firstRowNumber + rowIndex)")
                                        .foregroundStyle(.secondary)
                                        .frame(width: numberWidth, alignment: .leading)
                                    ForEach(columns.indices, id: \.self) { columnIndex in
                                        cell(rows[rowIndex][columnIndex],
                                             column: columns[columnIndex].name,
                                             row: firstRowNumber + rowIndex)
                                            .frame(width: cellWidth, alignment: .leading)
                                    }
                                }
                                .padding(8)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.08))
                            }
                        }
                    }
                }
            }
            .frame(width: numberWidth + CGFloat(columns.count) * cellWidth + 16,
                   alignment: .leading)
        }
        .sheet(item: $detail) { selected in
            NavigationStack {
                ScrollView {
                    Text(selected.value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(selected.title)
                .toolbar { Button("Done") { detail = nil } }
            }
        }
    }

    private func headerText(_ column: RowColumn) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(column.name + (sort?.column == column.name ? (sort?.descending == true ? " ↓" : " ↑") : ""))
                .lineLimit(2)
            if !column.declaredType.isEmpty {
                Text(column.declaredType).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Column \(column.name)\(column.declaredType.isEmpty ? "" : ", \(column.declaredType)")")
    }

    @ViewBuilder
    private func cell(_ value: SQLiteValue, column: String, row: Int) -> some View {
        switch value {
        case .null:
            Text("NULL").italic().foregroundStyle(.secondary)
                .accessibilityLabel("Row \(row), \(column), NULL")
        case .integer(let number):
            Text(String(number)).textSelection(.enabled)
                .accessibilityLabel("Row \(row), \(column), integer \(number)")
        case .real(let number):
            Text(String(number)).textSelection(.enabled)
                .accessibilityLabel("Row \(row), \(column), real \(number)")
        case .text(let string):
            if string.count > 80 {
                Button(String(string.prefix(80)) + "…") {
                    detail = CellDetail(title: column, value: string)
                }
                .accessibilityLabel("Row \(row), \(column), text, show full value")
            } else {
                Text(string).textSelection(.enabled)
                    .accessibilityLabel("Row \(row), \(column), text \(string)")
            }
        case .blob(let data):
            Button {
                detail = CellDetail(title: "\(column) BLOB", value: data.map { String(format: "%02X", $0) }.joined(separator: " "))
            } label: {
                Text("\(data.count) bytes · \(data.prefix(8).map { String(format: "%02X", $0) }.joined())")
            }
            .accessibilityLabel("Row \(row), \(column), BLOB, \(data.count) bytes, show full value")
        }
    }
}

private struct CellDetail: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}
