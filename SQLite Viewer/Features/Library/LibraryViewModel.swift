import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var databases: [LibraryDatabase] = []
    @Published private(set) var opened: LibraryDatabase?
    @Published private(set) var isBusy = false
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    @Published var renameErrorMessage: String?

    private(set) var library: DatabaseLibrary?
    private var sharedImportGate = SharedFileImportGate()
    private var activeImportCount = 0

    init(library: DatabaseLibrary? = nil) {
        self.library = library
    }

    func load() async {
        do {
            if library == nil { library = try DatabaseLibrary() }
            let entries = try await library?.databases() ?? []
            if !isImporting { databases = entries }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importFile(_ url: URL) async -> Bool {
        activeImportCount += 1
        isImporting = true
        isBusy = true
        defer {
            activeImportCount -= 1
            isImporting = activeImportCount > 0
            isBusy = activeImportCount > 0
        }
        if library == nil { await load() }
        guard let library else { return false }
        do {
            _ = try await library.importDatabase(from: url)
            databases = try await library.databases()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importSharedFile(_ url: URL) async -> Bool {
        guard url.isFileURL else {
            errorMessage = "Only local files can be imported."
            return false
        }
        guard sharedImportGate.begin(url) else { return false }
        let imported = await importFile(url)
        sharedImportGate.finish(url, succeeded: imported)
        return imported
    }

    func open(_ id: UUID) async -> Bool {
        guard let library else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            opened = try await library.open(id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func close() async {
        do {
            try await library?.closeActive()
            opened = nil
            databases = try await library?.databases() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ id: UUID, to name: String) async -> Bool {
        guard let library else { return false }
        renameErrorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let renamed = try await library.rename(id, to: name)
            if let index = databases.firstIndex(where: { $0.id == id }) {
                databases[index] = renamed
            }
            if opened?.id == id { opened = renamed }
            return true
        } catch {
            renameErrorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ id: UUID) async {
        guard let library else { return }
        do {
            try await library.delete(id)
            if opened?.id == id { opened = nil }
            databases = try await library.databases()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    var showsUITestImport: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-import")
    }

    func importUITestSample() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let arguments = ProcessInfo.processInfo.arguments
            let offset = arguments.firstIndex(of: "-ui-test-import").map { $0 + 1 }
            let name = offset.flatMap { $0 < arguments.count ? arguments[$0] : nil } ?? "UI Test Sample"
            let url = directory.appendingPathComponent("\(name).sqlite")
            let session = try DatabaseSession(url: url, createIfNeeded: true)
            try await session.execute("CREATE TABLE sample (value TEXT)")
            try await session.execute("CREATE INDEX sample_value ON sample(value)")
            try await session.execute("INSERT INTO sample VALUES ('saved')")
            try await session.execute("CREATE TABLE earnings (customer_id INTEGER, income INTEGER)")
            try await session.execute("INSERT INTO earnings VALUES (10, 500), (10, 1500), (20, 2000)")
            try await session.execute("CREATE TABLE wide_rows (value TEXT, second TEXT, third TEXT, fourth TEXT, fifth TEXT, distant TEXT)")
            try await session.execute(
                """
                WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 205)
                INSERT INTO wide_rows(value, distant) SELECT printf('row %03d', n), 'far' FROM seq
                """
            )
            try await session.close()
            await importFile(url)
            try FileManager.default.removeItem(at: directory)
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: directory)
        }
    }
    #endif
}
