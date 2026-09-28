import Darwin
import Foundation

nonisolated struct LibraryDatabase: Identifiable, Sendable, Equatable {
    let id: UUID
    let displayName: String
    let originalFilename: String
    let importedAt: Date
    let fileSize: Int64
    let problem: String?
}

nonisolated enum LibraryError: LocalizedError, Sendable {
    case invalidSource(String)
    case sourceOpen(String)
    case backup(String)
    case corrupt(String)
    case missingDatabase
    case missingEntry
    case damagedManifest
    case invalidName(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource(let detail): "This is not a valid SQLite database. \(detail)"
        case .sourceOpen(let detail): "Could not open the source database. \(detail)"
        case .backup(let detail): "Could not create the database snapshot. \(detail)"
        case .corrupt(let detail): "The database failed its integrity check. \(detail)"
        case .missingDatabase: "The imported database file is missing. Delete this entry and import it again."
        case .missingEntry: "This database is no longer in the library."
        case .damagedManifest: "The library manifest is missing or damaged. Delete this entry and import it again."
        case .invalidName(let detail): detail
        case .storage(let detail): "Could not update the protected database library. \(detail)"
        }
    }
}

actor DatabaseLibrary {
    private struct Manifest: Codable {
        let displayName: String
        let originalFilename: String
        let importedAt: Date
    }

    private let root: URL
    private let stagingRoot: URL
    private let files = FileManager.default
    private var activeID: UUID?
    private var activeSession: DatabaseSession?

    init(rootURL: URL? = nil) throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        root = rootURL ?? support.appendingPathComponent("Databases", isDirectory: true)
        stagingRoot = root.appendingPathComponent(".staging", isDirectory: true)
        do {
            try Self.protectDirectory(root)
            try Self.protectDirectory(stagingRoot)
            try FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)
                .forEach { try FileManager.default.removeItem(at: $0) }
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
    }

    func databases() throws -> [LibraryDatabase] {
        let directories: [URL]
        do {
            directories = try files.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
        return directories.compactMap { directory -> LibraryDatabase? in
            guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
            let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard directoryValues?.isDirectory == true, directoryValues?.isSymbolicLink != true else {
                return LibraryDatabase(id: id, displayName: "Damaged library entry",
                                       originalFilename: "", importedAt: .distantPast,
                                       fileSize: 0, problem: "The library entry is not a directory. Delete it and import again.")
            }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            let manifestValues = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard manifestValues?.isRegularFile == true, manifestValues?.isSymbolicLink != true,
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                return LibraryDatabase(id: id, displayName: "Damaged library entry",
                                       originalFilename: "", importedAt: .distantPast,
                                       fileSize: 0, problem: "The library manifest is missing or damaged. Delete this entry and import it again.")
            }
            let databaseURL = directory.appendingPathComponent("database.sqlite")
            let databaseValues = try? databaseURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let validFile = databaseValues?.isRegularFile == true && databaseValues?.isSymbolicLink != true
            let attributes = try? files.attributesOfItem(atPath: databaseURL.path)
            let size = validFile ? (attributes?[.size] as? NSNumber)?.int64Value ?? 0 : 0
            return LibraryDatabase(id: id, displayName: manifest.displayName,
                                   originalFilename: manifest.originalFilename,
                                   importedAt: manifest.importedAt, fileSize: size,
                                   problem: validFile ? nil : LibraryError.missingDatabase.localizedDescription)
        }.sorted { $0.importedAt > $1.importedAt }
    }

    @discardableResult
    func importDatabase(from source: URL) throws -> LibraryDatabase {
        guard source.isFileURL else { throw LibraryError.invalidSource("Choose a local file.") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let staging = stagingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = staging.appendingPathComponent("database.sqlite")
        let published = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try Self.protectDirectory(staging)
            defer { try? files.removeItem(at: staging) }
            try Self.checkSQLiteHeader(at: source)
            try Self.copySnapshot(from: source, to: destination, in: staging)
            try Self.protectContents(of: staging)

            let manifest = Manifest(displayName: source.deletingPathExtension().lastPathComponent,
                                    originalFilename: source.lastPathComponent, importedAt: Date())
            let manifestURL = staging.appendingPathComponent("manifest.json")
            try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
            try Self.protectFile(manifestURL)
            try files.moveItem(at: staging, to: published)
            return LibraryDatabase(id: id, displayName: manifest.displayName,
                                   originalFilename: manifest.originalFilename,
                                   importedAt: manifest.importedAt,
                                   fileSize: ((try? files.attributesOfItem(atPath: published.appendingPathComponent("database.sqlite").path)[.size]) as? NSNumber)?.int64Value ?? 0,
                                   problem: nil)
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
    }

    func open(_ id: UUID) async throws -> LibraryDatabase {
        guard let database = try databases().first(where: { $0.id == id }) else { throw LibraryError.missingEntry }
        if let problem = database.problem { throw LibraryError.corrupt(problem) }
        if activeID == id { return database }
        try await closeActive()
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("database.sqlite")
        do {
            try Self.checkSQLiteHeader(at: url)
            let session = try DatabaseSession(url: url)
            let check = try await session.execute("PRAGMA quick_check", rowLimit: 1)
            guard check.rows == [[.text("ok")]], check.rowCount == 1 else {
                try? await session.close()
                throw LibraryError.corrupt("PRAGMA quick_check did not return ok.")
            }
            try Self.protectContents(of: url.deletingLastPathComponent())
            activeSession = session
            activeID = id
            return database
        } catch let error as LibraryError {
            throw error
        } catch let error as SQLiteError {
            throw LibraryError.corrupt(error.message)
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
    }

    func closeActive() async throws {
        let closedID = activeID
        activeSession?.cancelActiveSQL()
        try await activeSession?.close()
        activeSession = nil
        activeID = nil
        if let closedID {
            try Self.protectContents(of: root.appendingPathComponent(closedID.uuidString, isDirectory: true))
        }
    }

    func session(for id: UUID) throws -> DatabaseSession {
        guard activeID == id, let activeSession else { throw LibraryError.missingEntry }
        return activeSession
    }

    @discardableResult
    func rename(_ id: UUID, to proposedName: String) throws -> LibraryDatabase {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.invalidName("Enter a database name.") }
        guard name.count <= 100 else { throw LibraryError.invalidName("Use 100 characters or fewer.") }
        guard let entry = try databases().first(where: { $0.id == id }) else {
            throw LibraryError.missingEntry
        }
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let values = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            throw LibraryError.damagedManifest
        }

        let replacement = Manifest(displayName: name, originalFilename: manifest.originalFilename,
                                   importedAt: manifest.importedAt)
        let temporaryURL = directory.appendingPathComponent(".manifest-\(UUID().uuidString)")
        defer { try? files.removeItem(at: temporaryURL) }
        do {
            try JSONEncoder().encode(replacement).write(to: temporaryURL, options: .atomic)
            try Self.protectFile(temporaryURL)
            guard Darwin.rename(temporaryURL.path, manifestURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
        return LibraryDatabase(id: entry.id, displayName: name,
                               originalFilename: manifest.originalFilename, importedAt: manifest.importedAt,
                               fileSize: entry.fileSize, problem: entry.problem)
    }

    func delete(_ id: UUID) async throws {
        guard try databases().contains(where: { $0.id == id }) else { throw LibraryError.missingEntry }
        if activeID == id { try await closeActive() }
        do {
            try files.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
        } catch {
            throw LibraryError.storage(error.localizedDescription)
        }
    }

    private static func checkSQLiteHeader(at url: URL) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 16) ?? Data()
            guard header == Data("SQLite format 3\0".utf8) else {
                throw LibraryError.invalidSource("The SQLite file header is missing.")
            }
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.sourceOpen(error.localizedDescription)
        }
    }

    private struct SnapshotTransferError: Error {
        let code: Int32
        let message: String

        var needsWritableSourceDirectory: Bool {
            let primaryCode = code & 0xFF
            return primaryCode == SQLITE_CANTOPEN || primaryCode == SQLITE_READONLY
        }
    }

    private static func copySnapshot(from source: URL, to destination: URL, in staging: URL) throws {
        do {
            try backup(from: source, to: destination)
        } catch let error as SnapshotTransferError where error.needsWritableSourceDirectory {
            // A picked file may be readable while SQLite cannot create its WAL index beside it.
            try removeSnapshotFiles(at: destination)
            let localSource = staging.appendingPathComponent("source.sqlite")
            defer {
                try? FileManager.default.removeItem(at: localSource)
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: localSource.path + "-wal"))
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: localSource.path + "-shm"))
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: localSource.path + "-journal"))
            }
            do {
                try FileManager.default.copyItem(at: source, to: localSource)
                let sourceWAL = URL(fileURLWithPath: source.path + "-wal")
                if FileManager.default.fileExists(atPath: sourceWAL.path) {
                    try FileManager.default.copyItem(at: sourceWAL,
                                                     to: URL(fileURLWithPath: localSource.path + "-wal"))
                }
            } catch {
                throw LibraryError.sourceOpen("Could not stage the selected file and its WAL: \(error.localizedDescription)")
            }
            do {
                try backup(from: localSource, to: destination)
            } catch let stagedError as SnapshotTransferError {
                throw LibraryError.backup(stagedError.message)
            }
        } catch let error as SnapshotTransferError {
            throw LibraryError.backup(error.message)
        }
    }

    private static func removeSnapshotFiles(at destination: URL) throws {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: destination.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private static func backup(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?
        let inputStatus = sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil)
        guard inputStatus == SQLITE_OK, let input else {
            let message = input.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(inputStatus))
            if let input { sqlite3_close(input) }
            throw LibraryError.sourceOpen(message)
        }
        defer { sqlite3_close(input) }
        sqlite3_busy_timeout(input, 5_000)

        var output: OpaquePointer?
        let outputStatus = sqlite3_open_v2(destination.path, &output,
                                           SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard outputStatus == SQLITE_OK, let output else {
            let message = output.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(outputStatus))
            if let output { sqlite3_close(output) }
            throw LibraryError.backup(message)
        }
        defer { sqlite3_close(output) }
        sqlite3_busy_timeout(output, 5_000)
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else {
            throw SnapshotTransferError(code: sqlite3_extended_errcode(output),
                                        message: String(cString: sqlite3_errmsg(output)))
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE, finish == SQLITE_OK else {
            throw SnapshotTransferError(code: step == SQLITE_DONE ? finish : step,
                                        message: String(cString: sqlite3_errmsg(output)))
        }

        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(output, "PRAGMA quick_check", -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw LibraryError.corrupt(String(cString: sqlite3_errmsg(output)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let result = sqlite3_column_text(statement, 0) else {
            throw LibraryError.corrupt(String(cString: sqlite3_errmsg(output)))
        }
        let checkResult = String(cString: result)
        guard checkResult == "ok" else { throw LibraryError.corrupt(checkResult) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryError.corrupt(String(cString: sqlite3_errmsg(output)))
        }
    }

    private static func protectDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func protectFile(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private static func protectContents(of directory: URL) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try protectFile(url)
        }
    }
}
