import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = LibraryViewModel()
    @State private var isImporterPresented = false
    @State private var pendingDelete: LibraryDatabase?
    @State private var pendingRename: LibraryDatabase?
    @State private var renameDraft = ""
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if model.isImporting {
                        ProgressView("Importing database…")
                            .accessibilityIdentifier("import-progress")
                    }
                    if model.databases.isEmpty {
                        ContentUnavailableView("No databases", systemImage: "externaldrive",
                                               description: Text("Import a SQLite file to create an editable copy."))
                    }
                    ForEach(model.databases) { database in
                        Button {
                            Task {
                                if await model.open(database.id) { path.append(database.id) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(database.displayName).font(.headline)
                                Text(database.importedAt, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: database.fileSize, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let problem = database.problem {
                                    Text(problem).font(.caption).foregroundStyle(.red)
                                }
                                Text("Open").font(.caption).foregroundStyle(.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .accessibilityLabel("Open \(database.displayName)")
                        .accessibilityIdentifier("open-\(database.id.uuidString)")
                        .accessibilityAction(named: "Rename") { beginRename(database) }
                        .accessibilityAction(named: "Delete") { pendingDelete = database }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { beginRename(database) }
                            Button(role: .destructive) { pendingDelete = database } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Rename", systemImage: "pencil") { beginRename(database) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = database
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                } footer: {
                    Text("Import .sqlite, .sqlite3, or .db files. Import makes an independent snapshot. The source and its WAL sidecars must be accessible for uncheckpointed transactions to appear.")
                }
            }
            .navigationTitle("Databases")
            .toolbar {
                #if DEBUG
                if model.showsUITestImport {
                    Button("Import test database") {
                        Task { await model.importUITestSample() }
                    }
                    .accessibilityIdentifier("import-test-database")
                }
                #endif
                Button("Import", systemImage: "square.and.arrow.down") {
                    isImporterPresented = true
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("import-button")
            }
            .navigationDestination(for: UUID.self) { id in
                if let database = model.opened, database.id == id, let library = model.library {
                    DatabaseWorkspace(database: database, library: library)
                }
            }
            .fileImporter(isPresented: $isImporterPresented,
                          allowedContentTypes: SQLiteDocumentTypes.contentTypes) { result in
                switch result {
                case .success(let url): Task { await model.importFile(url) }
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Delete imported copy?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                if let database = pendingDelete {
                    Button("Delete \(database.displayName)", role: .destructive) {
                        Task { await model.delete(database.id) }
                        pendingDelete = nil
                    }
                }
            } message: {
                Text("The original file will not be changed.")
            }
            .sheet(item: $pendingRename) { database in
                NavigationStack {
                    Form {
                        TextField("Database name", text: $renameDraft)
                            .accessibilityIdentifier("rename-name")
                        if let error = model.renameErrorMessage {
                            Text(error).foregroundStyle(.red)
                                .accessibilityIdentifier("rename-error")
                        }
                    }
                    .navigationTitle("Rename database")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { pendingRename = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    if await model.rename(database.id, to: renameDraft) {
                                        pendingRename = nil
                                    }
                                }
                            }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("save-rename")
                        }
                    }
                }
            }
            .alert("Database error", isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task { await model.load() }
        .onOpenURL { url in
            Task {
                if await model.importSharedFile(url) { path.removeAll() }
            }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { Task { await model.close() } }
        }
    }

    private func beginRename(_ database: LibraryDatabase) {
        model.renameErrorMessage = nil
        renameDraft = database.displayName
        pendingRename = database
    }
}

private struct DatabaseWorkspace: View {
    let database: LibraryDatabase
    @StateObject private var schemaModel: SchemaWorkspaceModel
    @StateObject private var rowsModel: RowsWorkspaceModel
    @StateObject private var storageModel: StorageWorkspaceModel
    @StateObject private var sqlModel: SQLConsoleModel
    @StateObject private var countStore: TableCountStore
    @State private var destination = "schema"

    init(database: LibraryDatabase, library: DatabaseLibrary) {
        self.database = database
        _schemaModel = StateObject(wrappedValue: SchemaWorkspaceModel(databaseID: database.id, library: library))
        _rowsModel = StateObject(wrappedValue: RowsWorkspaceModel(databaseID: database.id, library: library))
        _storageModel = StateObject(wrappedValue: StorageWorkspaceModel(databaseID: database.id, library: library))
        _sqlModel = StateObject(wrappedValue: SQLConsoleModel(databaseID: database.id, library: library))
        _countStore = StateObject(wrappedValue: TableCountStore(databaseID: database.id, library: library))
    }

    var body: some View {
        TabView(selection: $destination) {
            SchemaWorkspaceView(database: database, model: schemaModel, counts: countStore,
                                onRefresh: refreshSchema, onBrowseRows: browseRows)
                .tabItem { Label("Schema", systemImage: "square.stack.3d.up") }
                .tag("schema")
            RowsWorkspaceView(catalog: schemaModel.catalog, model: rowsModel, counts: countStore)
                .tabItem { Label("Rows", systemImage: "tablecells") }
                .tag("rows")
            StorageWorkspaceView(model: storageModel)
                .tabItem { Label("Storage", systemImage: "externaldrive") }
                .tag("storage")
            SQLConsoleView(database: database, model: sqlModel)
                .tabItem { Label("SQL", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag("sql")
        }
        .navigationTitle(database.displayName)
        .onChange(of: schemaModel.refreshVersion) { _, _ in
            rowsModel.invalidateAndReload(availableObjects: schemaModel.catalog)
        }
        .onChange(of: sqlModel.completedVersion) { _, _ in
            refreshAfterSQL()
        }
    }

    private func refreshSchema() {
        countStore.invalidate()
        rowsModel.invalidateVisiblePage()
        schemaModel.refreshSchema()
    }

    private func browseRows(_ object: SchemaObject) {
        rowsModel.select(object)
        destination = "rows"
    }

    private func refreshAfterSQL() {
        countStore.invalidate()
        rowsModel.invalidateVisiblePage()
        schemaModel.refreshSchema()
        storageModel.refresh()
    }
}
