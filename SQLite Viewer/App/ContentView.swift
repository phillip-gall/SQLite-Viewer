import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
                        databaseRow(database)
                    }
                } footer: {
                    Text("Import a .sqlite, .sqlite3, or .db file to work on a separate copy. Include accessible WAL sidecars for recent transactions.")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(WorkspaceStyle.canvas)
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
                .labelStyle(.iconOnly)
                .disabled(model.isBusy)
                .accessibilityIdentifier("import-button")
            }
            .navigationDestination(for: UUID.self) { id in
                if let database = model.databases.first(where: { $0.id == id }), let library = model.library {
                    DatabaseDestination(database: database, library: library, model: model)
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
        .sheet(item: $model.exportedDatabase, onDismiss: model.discardExport) { snapshot in
            DatabaseShareSheet(fileURL: snapshot.fileURL)
        }
        .overlay(alignment: .bottom) {
            if model.isExporting {
                ProgressView("Preparing database…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .accessibilityIdentifier("export-progress")
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

    private func databaseRow(_ database: LibraryDatabase) -> some View {
        Button {
            path.append(database.id)
        } label: {
            databaseLabel(database)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(model.isBusy)
        .accessibilityLabel("Open \(database.displayName)")
        .accessibilityIdentifier("open-\(database.id.uuidString)")
        .accessibilityAction(named: "Rename") { beginRename(database) }
        .accessibilityAction(named: "Export") { export(database) }
        .accessibilityAction(named: "Delete") { pendingDelete = database }
        .contextMenu {
            Button("Export database", systemImage: "square.and.arrow.up") { export(database) }
                .disabled(model.isBusy)
            Button("Rename", systemImage: "pencil") { beginRename(database) }
            Button(role: .destructive) { pendingDelete = database } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Export", systemImage: "square.and.arrow.up") { export(database) }
                .disabled(model.isBusy)
            Button("Rename", systemImage: "pencil") { beginRename(database) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingDelete = database
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private func databaseLabel(_ database: LibraryDatabase) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(database.displayName).font(.headline).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: database.fileSize, countStyle: .file))
                    Text("·")
                    Text(database.importedAt, style: .date)
                }
                .font(.caption).foregroundStyle(.secondary)
                if let problem = database.problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func beginRename(_ database: LibraryDatabase) {
        model.renameErrorMessage = nil
        renameDraft = database.displayName
        pendingRename = database
    }

    private func export(_ database: LibraryDatabase) {
        Task { await model.export(database.id) }
    }
}

private struct DatabaseDestination: View {
    let database: LibraryDatabase
    let library: DatabaseLibrary
    @ObservedObject var model: LibraryViewModel
    @State private var attempt = 0

    var body: some View {
        Group {
            if let opened = model.opened, opened.id == database.id {
                DatabaseWorkspace(database: opened, library: library,
                                  isExporting: model.isExporting,
                                  onExport: { Task { await model.export(database.id) } })
            } else if let message = model.openingErrorMessage {
                ContentUnavailableView {
                    Label("Could not open database", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { attempt += 1 }
                }
                .accessibilityIdentifier("database-open-error")
            } else {
                ProgressView("Opening database…")
                    .accessibilityIdentifier("database-open-progress")
            }
        }
        .navigationTitle(database.displayName)
        .task(id: attempt) { _ = await model.open(database.id) }
    }
}

private struct DatabaseShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

