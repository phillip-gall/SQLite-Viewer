import SwiftUI

struct RowsWorkspaceView: View {
    let catalog: [SchemaObject]
    @ObservedObject var model: RowsWorkspaceModel
    @ObservedObject var counts: TableCountStore
    @State private var filterEditor: FilterEditorSelection?

    private struct FilterEditorSelection: Identifiable {
        let id = UUID()
        let filter: RowFilter?
    }

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
                    Button("Reload", systemImage: "arrow.clockwise") {
                        counts.invalidate()
                        model.reload()
                    }
                        .accessibilityIdentifier("reload-rows")
                }
            }
            .padding(.horizontal)

            if let page = model.page {
                HStack {
                    Text("Filters").font(.headline)
                    Spacer()
                    Button("Add filter", systemImage: "plus") {
                        filterEditor = FilterEditorSelection(filter: nil)
                    }
                    .accessibilityIdentifier("add-filter")
                    if !model.filters.isEmpty {
                        Button("Clear all") { model.applyFilters([]) }
                            .accessibilityIdentifier("clear-filters")
                    }
                }
                .padding(.horizontal)
                if !model.filters.isEmpty {
                    Text("All conditions must match")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    ForEach(model.filters) { filter in
                        HStack {
                            Text(filterDescription(filter))
                                .lineLimit(2)
                                .accessibilityIdentifier("filter-\(filter.id.uuidString)")
                            Spacer(minLength: 8)
                            Button("Edit") { filterEditor = FilterEditorSelection(filter: filter) }
                            Button("Remove") {
                                model.applyFilters(model.filters.filter { $0.id != filter.id })
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                    }
                }
                if let message = model.removedFilterMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }
                if !model.filters.isEmpty {
                    matchingSummary(for: page.object)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                        .accessibilityIdentifier("rows-matching-count")
                }
            }

            if let selected = model.selected {
                if selected.kind == .view {
                    Text(model.filters.isEmpty ? "View" : "Filtered view")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                } else if model.filters.isEmpty {
                    Group {
                        switch counts.state(for: selected) {
                        case .value(let total): Text("\(total) rows")
                        case .failed(let message): Text("Count unavailable: \(message)")
                        case .counting, nil: Text("Counting…")
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    .accessibilityIdentifier("rows-total-count")
                }
            }

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
        .sheet(item: $filterEditor) { selection in
            if let page = model.page {
                RowFilterEditor(columns: page.columns, editing: selection.filter) { filter in
                    var updated = model.filters
                    if let index = updated.firstIndex(where: { $0.id == filter.id }) {
                        updated[index] = filter
                    } else {
                        updated.append(filter)
                    }
                    model.applyFilters(updated)
                }
            }
        }
        .onChange(of: model.page?.object.id) { _, _ in
            if let selected = model.selected, model.page != nil {
                counts.request(selected, priority: true)
            }
        }
    }

    @ViewBuilder
    private func matchingSummary(for object: SchemaObject) -> some View {
        if let error = model.matchingCountError {
            Text("Matching count unavailable: \(error)").foregroundStyle(.red)
        } else if let matching = model.matchingCount {
            if object.kind == .table {
                switch counts.state(for: object) {
                case .value(let total): Text("Matching \(matching) of \(total) rows")
                case .failed: Text("Matching \(matching) rows; total unavailable")
                case .counting, nil: Text("Matching \(matching) rows; counting total…")
                }
            } else {
                Text("Matching \(matching) rows")
            }
        } else {
            Text("Counting matches…")
        }
    }

    private func filterDescription(_ filter: RowFilter) -> String {
        guard let value = filter.value, filter.operation.needsValue else {
            return "\(filter.column) \(filter.operation.label)"
        }
        let display: String
        switch value {
        case .text(let text): display = "\"\(text)\""
        case .integer(let number): display = String(number)
        case .real(let number): display = String(number)
        case .null: display = "NULL"
        case .blob(let data): display = "\(data.count) bytes"
        }
        return "\(filter.column) \(filter.operation.label) \(display)"
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
