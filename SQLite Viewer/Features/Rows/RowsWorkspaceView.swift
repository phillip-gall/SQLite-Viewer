import SwiftUI

struct RowsWorkspaceView: View {
    let catalog: [SchemaObject]
    @ObservedObject var model: RowsWorkspaceModel
    @ObservedObject var counts: TableCountStore
    @State private var filterEditor: FilterEditorSelection?
    @State private var showsFilters = false

    private struct FilterEditorSelection: Identifiable {
        let id = UUID()
        let filter: RowFilter?
    }

    var body: some View {
        ZStack(alignment: .top) {
            WorkspaceStyle.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                if let page = model.page {
                    SQLiteValueGrid(columns: page.columns, rows: page.rows, sort: model.sort,
                                    onSort: { model.setSort($0) },
                                    firstRowNumber: (page.number - 1) * RowsService.pageSize + 1)
                        .id("\(page.object.id):\(page.number):\(model.sort?.column ?? ""):\(model.sort?.descending ?? false)")
                } else if let error = model.errorMessage {
                    ContentUnavailableView {
                        Label("Rows unavailable", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Retry") { model.reload() }
                        if model.sort != nil { Button("Clear sort") { model.clearSort() } }
                    }
                    .accessibilityIdentifier("rows-error")
                } else if model.isLoading {
                    ProgressView("Loading rows").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Choose a table", systemImage: "tablecells",
                                           description: Text("Select a table or view to browse its rows."))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // One control axis; scroll content remains reachable beneath the glass.
                GlassControlBar {
                    Menu {
                        ForEach(catalog.filter { $0.kind == .table || $0.kind == .view }) { object in
                            Button(object.name) { model.select(object) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tablecells")
                            Text(model.selected?.name ?? "Choose a table").lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("rows-object-picker")
                    .disabled(catalog.isEmpty)
                    Spacer(minLength: 0)
                    SymbolButton(title: "Filters", symbol: model.filters.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                        showsFilters = true
                    }
                    .disabled(model.page == nil)
                    .accessibilityValue("\(model.filters.count) active filters")
                    .accessibilityIdentifier("show-filters")
                    SymbolButton(title: "Reload", symbol: "arrow.clockwise") {
                        counts.invalidate()
                        model.reload()
                    }
                    .disabled(model.selected == nil || model.isLoading)
                    .accessibilityIdentifier("reload-rows")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selected = model.selected {
                    GlassControlBar {
                        VStack(alignment: .leading, spacing: 2) {
                            countSummary(selected)
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier(model.filters.isEmpty ? "rows-total-count" : "rows-matching-count")
                            Text("Page \(model.pageNumber)").font(.caption.weight(.medium))
                        }
                        .lineLimit(1).padding(.leading, 12)
                        Spacer(minLength: 0)
                        if model.sort != nil {
                            SymbolButton(title: "Clear sort", symbol: "arrow.up.arrow.down") { model.clearSort() }
                        }
                        SymbolButton(title: "Previous", symbol: "chevron.left") { model.showPage(model.pageNumber - 1) }
                            .disabled(model.pageNumber == 1 || model.isLoading)
                            .accessibilityIdentifier("rows-previous-page")
                        SymbolButton(title: "Next", symbol: "chevron.right") { model.showPage(model.pageNumber + 1) }
                            .disabled(model.page?.hasNext != true || model.isLoading)
                            .accessibilityIdentifier("rows-next-page")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showsFilters) { filtersPanel }
        .onChange(of: model.page?.object.id) { _, _ in
            if let selected = model.selected, model.page != nil { counts.request(selected, priority: true) }
        }
    }

    private var filtersPanel: some View {
        NavigationStack {
            List {
                if model.filters.isEmpty {
                    ContentUnavailableView("No filters", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Add a condition to narrow the rows."))
                } else {
                    Section("All conditions must match") {
                        ForEach(model.filters) { filter in
                            Button(filter.displayDescription) {
                                filterEditor = FilterEditorSelection(filter: filter)
                            }
                            .accessibilityIdentifier("filter-\(filter.id.uuidString)")
                            .swipeActions {
                                Button("Remove", role: .destructive) { model.removeFilter(filter.id) }
                            }
                        }
                    }
                    Button("Clear all", role: .destructive) { model.applyFilters([]) }
                        .accessibilityIdentifier("clear-filters")
                }
                if let message = model.removedFilterMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if model.page?.hasStableOrder == false {
                    Text("This object has no stable row key. Rows may move between pages.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { showsFilters = false } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add filter", systemImage: "plus") {
                        filterEditor = FilterEditorSelection(filter: nil)
                    }
                    .labelStyle(.iconOnly).accessibilityIdentifier("add-filter")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $filterEditor) { selection in
            if let page = model.page {
                RowFilterEditor(columns: page.columns, editing: selection.filter, onSave: model.saveFilter)
            }
        }
    }

    @ViewBuilder
    private func countSummary(_ object: SchemaObject) -> some View {
        if !model.filters.isEmpty {
            if let error = model.matchingCountError {
                Text("Matching count unavailable: \(error)").foregroundStyle(.red)
            } else if let matching = model.matchingCount {
                if case .value(let total) = counts.state(for: object), object.kind == .table {
                    Text("Matching \(matching) of \(total) rows")
                } else { Text("Matching \(matching) rows") }
            } else { Text("Counting matches…") }
        } else if object.kind == .view { Text("View") }
        else {
            switch counts.state(for: object) {
            case .value(let total): Text("\(total) rows")
            case .failed(let message): Text("Count unavailable: \(message)")
            case .counting, nil: Text("Counting…")
            }
        }
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
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))
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
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.08))
                            }
                        }
                    }
                }
            }
            .frame(width: numberWidth + CGFloat(columns.count) * cellWidth + 24,
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
