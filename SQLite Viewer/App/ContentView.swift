import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = LibraryViewModel()
    @State private var isImporterPresented = false
    @State private var pendingDelete: LibraryDatabase?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if model.databases.isEmpty {
                        ContentUnavailableView("No databases", systemImage: "externaldrive",
                                               description: Text("Import a SQLite file to create an editable copy."))
                    }
                    ForEach(model.databases) { database in
                        HStack {
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
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("open-\(database.id.uuidString)")
                            Button(role: .destructive) { pendingDelete = database } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(database.displayName)")
                        }
                    }
                } footer: {
                    Text("Import makes an independent snapshot. The source and its WAL sidecars must be accessible for uncheckpointed transactions to appear.")
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
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item]) { result in
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
            .alert("Database error", isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task { await model.load() }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { Task { await model.close() } }
        }
    }
}

private struct DatabaseWorkspace: View {
    let database: LibraryDatabase
    @StateObject private var schemaModel: SchemaWorkspaceModel
    @StateObject private var rowsModel: RowsWorkspaceModel
    @State private var destination = "schema"

    init(database: LibraryDatabase, library: DatabaseLibrary) {
        self.database = database
        _schemaModel = StateObject(wrappedValue: SchemaWorkspaceModel(databaseID: database.id, library: library))
        _rowsModel = StateObject(wrappedValue: RowsWorkspaceModel(databaseID: database.id, library: library))
    }

    var body: some View {
        TabView(selection: $destination) {
            SchemaWorkspaceView(database: database, model: schemaModel,
                                onRefresh: refreshSchema, onBrowseRows: browseRows)
                .tabItem { Label("Schema", systemImage: "square.stack.3d.up") }
                .tag("schema")
            RowsWorkspaceView(catalog: schemaModel.catalog, model: rowsModel)
                .tabItem { Label("Rows", systemImage: "tablecells") }
                .tag("rows")
            futureDestination("Storage", symbol: "externaldrive")
                .tabItem { Label("Storage", systemImage: "externaldrive") }
                .tag("storage")
            futureDestination("SQL", symbol: "chevron.left.forwardslash.chevron.right")
                .tabItem { Label("SQL", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag("sql")
        }
        .onChange(of: schemaModel.refreshVersion) { _, _ in
            rowsModel.invalidateAndReload(availableObjects: schemaModel.catalog)
        }
    }

    private func refreshSchema() {
        rowsModel.invalidateVisiblePage()
        schemaModel.refreshSchema()
    }

    private func browseRows(_ object: SchemaObject) {
        rowsModel.select(object)
        destination = "rows"
    }

    private func futureDestination(_ name: String, symbol: String) -> some View {
        ContentUnavailableView("\(name) coming soon", systemImage: symbol)
    }
}
