import SwiftUI

struct DatabaseWorkspace: View {
    let database: LibraryDatabase
    let isExporting: Bool
    let onExport: () -> Void
    @StateObject private var model: DatabaseWorkspaceModel
    @State private var showsSidebar = true

    init(database: LibraryDatabase, library: DatabaseLibrary, isExporting: Bool, onExport: @escaping () -> Void) {
        self.database = database
        self.isExporting = isExporting
        self.onExport = onExport
        _model = StateObject(wrappedValue: DatabaseWorkspaceModel(databaseID: database.id, library: library))
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 800 {
                HStack(spacing: 0) {
                    if showsSidebar {
                        WorkspaceSchemaSidebar(model: model.schema, counts: model.counts,
                                               onSelect: model.select, onRefresh: model.refreshSchema)
                            .frame(width: 270)
                        Divider()
                    }
                    destination(model.destination, wide: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Toggle schema sidebar", systemImage: "sidebar.left") {
                            withAnimation { showsSidebar.toggle() }
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("toggle-schema-sidebar")
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("Workspace", selection: $model.destination) {
                            ForEach(DatabaseWorkspaceModel.Destination.allCases) { item in
                                Label(item.title, systemImage: item.symbol).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 380)
                        .accessibilityIdentifier("workspace-picker")
                    }
                }
            } else {
                TabView(selection: $model.destination) {
                    ForEach(DatabaseWorkspaceModel.Destination.allCases) { item in
                        destination(item, wide: false)
                            .tabItem { Label(item.title, systemImage: item.symbol) }
                            .tag(item)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .background(WorkspaceStyle.canvas)
        .navigationTitle(database.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Export database", systemImage: "square.and.arrow.up", action: onExport)
                .labelStyle(.iconOnly)
                .disabled(isExporting)
                .accessibilityIdentifier("export-database")
        }
        .task { model.refreshSchema() }
    }

    @ViewBuilder
    private func destination(_ destination: DatabaseWorkspaceModel.Destination, wide: Bool) -> some View {
        switch destination {
        case .schema:
            SchemaWorkspaceView(database: database, model: model.schema, counts: model.counts,
                                onRefresh: model.refreshSchema, onBrowseRows: model.browseRows,
                                detailOnly: wide)
        case .rows:
            WorkspaceRowsContent(schema: model.schema, rows: model.rows, counts: model.counts)
        case .sql:
            SQLConsoleView(database: database, model: model.sql)
        case .storage:
            StorageWorkspaceView(model: model.storage)
        }
    }
}

/// Observes the catalog independently from workspace navigation.
private struct WorkspaceRowsContent: View {
    @ObservedObject var schema: SchemaWorkspaceModel
    @ObservedObject var rows: RowsWorkspaceModel
    @ObservedObject var counts: TableCountStore

    var body: some View {
        RowsWorkspaceView(catalog: schema.catalog, model: rows, counts: counts)
    }
}

private struct WorkspaceSchemaSidebar: View {
    @ObservedObject var model: SchemaWorkspaceModel
    @ObservedObject var counts: TableCountStore
    let onSelect: (SchemaObject) -> Void
    let onRefresh: () -> Void
    @State private var search = ""

    var body: some View {
        List {
            ForEach(SchemaObject.Kind.allCases, id: \.self) { kind in
                let objects = model.catalog.filter {
                    $0.kind == kind && (search.isEmpty || $0.name.localizedStandardContains(search))
                }
                if !objects.isEmpty {
                    Section(kind.heading) {
                        ForEach(objects) { object in
                            Button { onSelect(object) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(kind)).foregroundStyle(.tint)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(object.name).lineLimit(1)
                                        if case .value(let total) = counts.state(for: object) {
                                            Text("\(total) rows").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(model.selectedID == object.id ? Color.accentColor.opacity(0.12) : Color.clear)
                            .accessibilityIdentifier("schema-\(object.id)")
                            .accessibilityAddTraits(model.selectedID == object.id ? .isSelected : [])
                            .task(id: model.refreshVersion) { counts.request(object) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, prompt: "Find an object")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(model.catalog.count) objects").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh schema", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("refresh-schema")
            }
            .padding(12)
        }
        .overlay {
            if model.isLoading && model.catalog.isEmpty { ProgressView() }
            else if let error = model.errorMessage, model.catalog.isEmpty {
                ContentUnavailableView("Schema unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.catalog.isEmpty {
                ContentUnavailableView("No schema objects", systemImage: "square.stack.3d.up")
            }
        }
        .accessibilityIdentifier("schema-sidebar")
    }

    private func symbol(_ kind: SchemaObject.Kind) -> String {
        switch kind {
        case .table: "tablecells"
        case .view: "eye"
        case .index: "list.bullet.indent"
        case .trigger: "bolt"
        }
    }
}
