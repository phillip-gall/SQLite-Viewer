import SwiftUI

struct SchemaWorkspaceView: View {
    let database: LibraryDatabase
    @ObservedObject var model: SchemaWorkspaceModel
    @ObservedObject var counts: TableCountStore
    let onRefresh: () -> Void
    let onBrowseRows: (SchemaObject) -> Void

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 700 {
                HStack(spacing: 0) {
                    catalogList(wide: true)
                        .frame(width: 320)
                    Divider()
                    detailPane(wide: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                catalogList(wide: false)
            }
        }
        .accessibilityIdentifier("database-workspace")
        .task { onRefresh() }
    }

    private func catalogList(wide: Bool) -> some View {
        List {
                Section {
                    Button("Refresh schema", systemImage: "arrow.clockwise") { onRefresh() }
                        .accessibilityIdentifier("refresh-schema")
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { onRefresh() }
                    }
                }
                if model.catalog.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("No schema objects", systemImage: "square.stack.3d.up")
                }
                ForEach(SchemaObject.Kind.allCases, id: \.self) { kind in
                    let objects = model.catalog.filter { $0.kind == kind }
                    if !objects.isEmpty {
                        Section(kind.heading) {
                            ForEach(objects) { object in
                                if wide {
                                    Button { model.select(id: object.id) } label: {
                                        objectLabel(object)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(objectAccessibilityLabel(object))
                                    .accessibilityIdentifier("schema-\(object.id)")
                                } else {
                                    NavigationLink {
                                        detailPane(wide: false).onAppear { model.select(id: object.id) }
                                    } label: {
                                        objectLabel(object)
                                    }
                                    .accessibilityLabel(objectAccessibilityLabel(object))
                                    .accessibilityIdentifier("schema-\(object.id)")
                                }
                            }
                        }
                    }
                }
        }
        .navigationTitle(database.displayName)
        .overlay {
            if model.isLoading && model.catalog.isEmpty { ProgressView("Loading schema") }
        }
    }

    private func objectLabel(_ object: SchemaObject) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(object.name)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if object.isInternal || model.shadowNames.contains(object.name) {
                Text(model.shadowNames.contains(object.name) ? "Shadow table" : "SQLite internal")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if object.kind == .table { countLabel(object) }
            if object.kind == .view {
                Text("View").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: model.refreshVersion) { counts.request(object) }
    }

    private func detailPane(wide: Bool) -> some View {
        Group {
                if let error = model.errorMessage {
                    errorView(error)
                } else if let object = model.selected {
                    detail(for: object, wide: wide)
                } else {
                    ContentUnavailableView("Select a schema object", systemImage: "square.stack.3d.up")
                }
        }
        .navigationTitle(model.selected?.name ?? "Schema")
    }

    @ViewBuilder
    private func detail(for object: SchemaObject, wide: Bool) -> some View {
        if model.isLoading {
            ProgressView("Loading \(object.name)")
        } else {
            List {
                Section("Object") {
                    LabeledContent("Name", value: object.name)
                    LabeledContent("Type", value: object.kind.rawValue.capitalized)
                    if object.kind == .table {
                        LabeledContent("Rows") { countLabel(object) }
                            .task(id: model.refreshVersion) { counts.request(object, priority: true) }
                    }
                    if object.kind == .index || object.kind == .trigger {
                        LabeledContent("On", value: object.tableName)
                    }
                    if object.isInternal { Text("SQLite internal object") }
                    if model.shadowNames.contains(object.name) { Text("Shadow table") }
                }
                if object.kind == .table {
                    Section {
                        BrowseRowsButton(object: object, dismissDetail: !wide,
                                         action: onBrowseRows)
                    }
                }
                if let table = model.tableDetail {
                    if let kind = table.tableKind {
                        Section("Table properties") {
                            LabeledContent("Kind", value: kind.label)
                            LabeledContent("WITHOUT ROWID", value: table.withoutRowID == true ? "Yes" : "No")
                            LabeledContent("STRICT", value: table.strict == true ? "Yes" : "No")
                        }
                    }
                    Section("Columns") {
                        ForEach(table.columns) { column in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(column.name).font(.headline)
                                    .accessibilityIdentifier("column-\(column.name)")
                                Text(column.declaredType.isEmpty ? "No declared type" : column.declaredType)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("\(column.visibility.label) · \(column.notNull ? "NOT NULL" : "Nullable")\(column.primaryKeyPosition > 0 ? " · Primary key \(column.primaryKeyPosition)" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let expression = column.defaultSQL {
                                    Text("Default: \(expression)").font(.caption).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if !model.indexes.isEmpty {
                        Section("Indexes") {
                            ForEach(model.indexes) { index in
                                indexSummary(index)
                            }
                        }
                    }
                    let triggers = model.catalog.filter { $0.kind == .trigger && $0.tableName == object.name }
                    if !triggers.isEmpty {
                        Section("Triggers") {
                            ForEach(triggers) { trigger in
                                VStack(alignment: .leading) {
                                    Text(trigger.name).font(.headline)
                                    sqlText(trigger.sql)
                                }
                            }
                        }
                    }
                }
                if let index = model.selectedIndex {
                    Section("Index properties") {
                        LabeledContent("Table", value: index.tableName)
                        LabeledContent("Origin", value: index.origin.label)
                        LabeledContent("Unique", value: index.isUnique ? "Yes" : "No")
                        LabeledContent("Partial", value: index.isPartial ? "Yes" : "No")
                    }
                    Section("Keys") {
                        ForEach(index.keys) { entry in indexEntry(entry) }
                    }
                    if index.entries.contains(where: { !$0.isKey }) {
                        Section("Auxiliary entries") {
                            ForEach(index.entries.filter { !$0.isKey }) { entry in indexEntry(entry) }
                        }
                    }
                }
                Section("Stored SQL") { sqlText(object.sql) }
            }
        }
    }

    @ViewBuilder
    private func countLabel(_ object: SchemaObject) -> some View {
        switch counts.state(for: object) {
        case .value(let count):
            Text("\(count) rows").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text("Count unavailable: \(message)").font(.caption).foregroundStyle(.red)
        case .counting, nil:
            Text("Counting…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func countAccessibility(_ object: SchemaObject) -> String {
        guard object.kind == .table else { return "" }
        switch counts.state(for: object) {
        case .value(let count): return ", \(count) rows"
        case .failed: return ", row count unavailable"
        case .counting, nil: return ", counting rows"
        }
    }

    private func objectAccessibilityLabel(_ object: SchemaObject) -> String {
        "\(object.kind.rawValue) \(object.name)\(object.isInternal ? ", SQLite internal" : "")\(countAccessibility(object))"
    }

    private func indexSummary(_ index: SchemaIndex) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(index.name).font(.headline)
                .accessibilityIdentifier("index-\(index.name)")
            Text("\(index.origin.label) · \(index.isUnique ? "Unique" : "Not unique")\(index.isPartial ? " · Partial" : "")")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(index.keys) { entry in indexEntry(entry) }
        }
    }

    private func indexEntry(_ entry: SchemaIndexEntry) -> some View {
        HStack {
            Text("\(entry.sequence + 1). \(entry.source.label)")
            Spacer()
            Text("\(entry.descending ? "DESC" : "ASC") · \(entry.collation)")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func sqlText(_ sql: String?) -> some View {
        if let sql {
            Text(sql)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("stored-sql")
        } else {
            Text("No stored CREATE SQL").foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Schema unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { onRefresh() }
        }
        .accessibilityIdentifier("schema-error")
    }
}

private struct BrowseRowsButton: View {
    let object: SchemaObject
    let dismissDetail: Bool
    let action: (SchemaObject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Browse rows", systemImage: "tablecells") {
            if dismissDetail { dismiss() }
            action(object)
        }
        .accessibilityIdentifier("browse-rows")
    }
}

private extension SchemaObject.Kind {
    var heading: String {
        switch self {
        case .table: "Tables"
        case .view: "Views"
        case .index: "Indexes"
        case .trigger: "Triggers"
        }
    }
}

private extension TableViewDetail.TableKind {
    var label: String {
        switch self {
        case .ordinary: "Ordinary table"
        case .virtual: "Virtual table"
        case .shadow: "Shadow table"
        }
    }
}

private extension SchemaIndex.Origin {
    var label: String {
        switch self {
        case .created: "CREATE INDEX"
        case .uniqueConstraint: "UNIQUE constraint"
        case .primaryKey: "PRIMARY KEY"
        }
    }
}

private extension SchemaColumn.Visibility {
    var label: String {
        switch self {
        case .normal: "Normal"
        case .virtualTableHidden: "Hidden"
        case .generatedVirtual: "VIRTUAL generated"
        case .generatedStored: "STORED generated"
        }
    }
}

private extension SchemaIndexEntry.Source {
    var label: String {
        switch self {
        case .column(let name): name
        case .expression: "Expression"
        case .rowID: "Rowid"
        }
    }
}
