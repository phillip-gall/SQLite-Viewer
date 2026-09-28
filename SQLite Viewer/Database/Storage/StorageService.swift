import Foundation

nonisolated enum StorageError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidResult(String)
    case overflow
    case changingDatabase

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): "Storage analysis is unavailable. \(detail)"
        case .invalidResult(let detail): "Could not read storage information. \(detail)"
        case .overflow: "The database is too large to calculate storage totals."
        case .changingDatabase: "Storage totals changed while loading. Try refreshing."
        }
    }
}

nonisolated struct StorageFootprint: Equatable, Sendable {
    let bytes: Int64
    let pages: Int64
    let payload: Int64
    let unused: Int64

    static let zero = StorageFootprint(bytes: 0, pages: 0, payload: 0, unused: 0)

    func adding(_ other: StorageFootprint) throws -> StorageFootprint {
        func sum(_ left: Int64, _ right: Int64) throws -> Int64 {
            let (value, overflow) = left.addingReportingOverflow(right)
            if overflow { throw StorageError.overflow }
            return value
        }
        return try StorageFootprint(
            bytes: sum(bytes, other.bytes), pages: sum(pages, other.pages),
            payload: sum(payload, other.payload), unused: sum(unused, other.unused)
        )
    }
}

nonisolated struct StorageBTree: Identifiable, Equatable, Sendable {
    let name: String
    let footprint: StorageFootprint

    var id: String { name }
}

nonisolated struct StorageObject: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case table
        case virtualTable = "virtual table"
        case view
    }

    let name: String
    let kind: Kind
    let data: StorageBTree?
    let indexes: [StorageBTree]
    let indexFootprint: StorageFootprint
    let total: StorageFootprint

    var id: String { name }
}

nonisolated struct StorageOther: Identifiable, Sendable {
    let tree: StorageBTree
    let description: String

    var id: String { tree.name }
}

nonisolated struct StorageReport: Sendable {
    let pageSize: Int64
    let pageCount: Int64
    let freePages: Int64
    let logicalBytes: Int64
    let freeBytes: Int64
    let overheadBytes: Int64
    let walBytes: Int64
    let data: StorageFootprint
    let indexes: StorageFootprint
    let otherFootprint: StorageFootprint
    let objects: [StorageObject]
    let other: [StorageOther]
}

struct StorageService: Sendable {
    let session: DatabaseSession

    func load() async throws -> StorageReport {
        try await session.loadStorageReport()
    }
}

extension DatabaseSession {
    /// Runs all reads without suspension so this connection cannot change mid-analysis.
    func loadStorageReport() throws -> StorageReport {
        guard Self.compileOptionUsed("ENABLE_DBSTAT_VTAB") else {
            throw StorageError.unavailable("The bundled SQLite build has no dbstat table.")
        }
        for _ in 0..<2 {
            if let report = try readStorageReport() { return report }
        }
        throw StorageError.changingDatabase
    }

    private func readStorageReport() throws -> StorageReport? {
        let pageSize = try storagePragma("PRAGMA main.page_size")
        let pageCount = try storagePragma("PRAGMA main.page_count")
        let freePages = try storagePragma("PRAGMA main.freelist_count")
        guard pageSize > 0, pageCount >= 0, freePages >= 0 else {
            throw StorageError.invalidResult("SQLite returned negative page metrics.")
        }
        let (logicalBytes, logicalOverflow) = pageCount.multipliedReportingOverflow(by: pageSize)
        let (freeBytes, freeOverflow) = freePages.multipliedReportingOverflow(by: pageSize)
        guard !logicalOverflow, !freeOverflow else { throw StorageError.overflow }

        let statistics = try execute(
            "SELECT name, pageno AS pages, pgsize AS bytes, payload, unused " +
            "FROM main.dbstat WHERE aggregate = TRUE ORDER BY name COLLATE BINARY",
            rowLimit: Int.max
        )
        guard !statistics.truncated else { throw StorageError.invalidResult("The B-tree list was truncated.") }
        let statDecoder = try StorageDecoder(statistics)
        var trees: [String: StorageBTree] = [:]
        var allTrees = StorageFootprint.zero
        for row in statistics.rows {
            let name = try statDecoder.text("name", in: row)
            let footprint = StorageFootprint(
                bytes: try statDecoder.integer("bytes", in: row),
                pages: try statDecoder.integer("pages", in: row),
                payload: try statDecoder.integer("payload", in: row),
                unused: try statDecoder.integer("unused", in: row)
            )
            guard !name.isEmpty, trees[name] == nil,
                  footprint.bytes >= 0, footprint.pages >= 0,
                  footprint.payload >= 0, footprint.unused >= 0 else {
                throw StorageError.invalidResult("Invalid or duplicate B-tree statistics.")
            }
            trees[name] = StorageBTree(name: name, footprint: footprint)
            allTrees = try allTrees.adding(footprint)
        }

        let tableList = try execute("PRAGMA main.table_list", rowLimit: Int.max)
        guard !tableList.truncated else { throw StorageError.invalidResult("The table list was truncated.") }
        let tableDecoder = try StorageDecoder(tableList)
        var kinds: [String: String] = [:]
        for row in tableList.rows where try tableDecoder.text("schema", in: row) == "main" {
            kinds[try tableDecoder.text("name", in: row)] = try tableDecoder.text("type", in: row)
        }

        let catalog = try execute(
            "SELECT type, name, tbl_name FROM main.sqlite_schema " +
            "WHERE type IN ('table', 'view', 'index') ORDER BY name COLLATE BINARY",
            rowLimit: Int.max
        )
        guard !catalog.truncated else { throw StorageError.invalidResult("The schema list was truncated.") }
        let catalogDecoder = try StorageDecoder(catalog)
        var tableNames: [(name: String, kind: StorageObject.Kind)] = []
        var indexOwners: [String: String] = [:]
        for row in catalog.rows {
            let type = try catalogDecoder.text("type", in: row)
            let name = try catalogDecoder.text("name", in: row)
            if type == "index" {
                indexOwners[name] = try catalogDecoder.text("tbl_name", in: row)
            } else if type == "view" {
                tableNames.append((name, .view))
            } else if !name.lowercased().hasPrefix("sqlite_"), kinds[name] != "shadow" {
                tableNames.append((name, kinds[name] == "virtual" ? .virtualTable : .table))
            }
        }

        var assigned: Set<String> = []
        var objects: [StorageObject] = []
        var data = StorageFootprint.zero
        var indexes = StorageFootprint.zero
        for table in tableNames {
            if table.kind == .view {
                objects.append(StorageObject(name: table.name, kind: .view, data: nil,
                                             indexes: [], indexFootprint: .zero, total: .zero))
                continue
            }
            let ownTree = trees[table.name]
            if let ownTree {
                guard assigned.insert(ownTree.name).inserted else {
                    throw StorageError.invalidResult("A B-tree was assigned to two tables.")
                }
                data = try data.adding(ownTree.footprint)
            }
            let list = try execute(
                "PRAGMA main.index_list(\(SQLIdentifier.quote(table.name)))", rowLimit: Int.max
            )
            guard !list.truncated else { throw StorageError.invalidResult("Indexes for \(table.name) were truncated.") }
            let listDecoder = try StorageDecoder(list)
            var tableIndexes: [StorageBTree] = []
            var tableIndexFootprint = StorageFootprint.zero
            for row in list.rows {
                let name = try listDecoder.text("name", in: row)
                guard let tree = trees[name] else { continue }
                guard assigned.insert(name).inserted else {
                    throw StorageError.invalidResult("A B-tree was assigned more than once.")
                }
                tableIndexes.append(tree)
                tableIndexFootprint = try tableIndexFootprint.adding(tree.footprint)
            }
            tableIndexes.sort { $0.name < $1.name }
            indexes = try indexes.adding(tableIndexFootprint)
            objects.append(StorageObject(
                name: table.name, kind: table.kind, data: ownTree, indexes: tableIndexes,
                indexFootprint: tableIndexFootprint,
                total: try (ownTree?.footprint ?? .zero).adding(tableIndexFootprint)
            ))
        }

        var other: [StorageOther] = []
        var otherFootprint = StorageFootprint.zero
        for tree in trees.values where !assigned.contains(tree.name) {
            let description: String
            if kinds[tree.name] == "shadow" {
                description = "Virtual table shadow table"
            } else if let owner = indexOwners[tree.name], kinds[owner] == "shadow" {
                description = "Shadow table index"
            } else if tree.name == "sqlite_schema" || tree.name.lowercased().hasPrefix("sqlite_") {
                description = "SQLite internal"
            } else {
                description = "Unassigned B-tree"
            }
            other.append(StorageOther(tree: tree, description: description))
            otherFootprint = try otherFootprint.adding(tree.footprint)
        }
        other.sort { $0.tree.name < $1.tree.name }
        guard try data.adding(indexes).adding(otherFootprint) == allTrees else {
            throw StorageError.invalidResult("B-tree totals do not match their assignments.")
        }
        let (counted, countedOverflow) = allTrees.bytes.addingReportingOverflow(freeBytes)
        guard !countedOverflow else { throw StorageError.overflow }
        guard freePages <= pageCount, counted <= logicalBytes else { return nil }
        let walBytes = try storageWALBytes()
        return StorageReport(
            pageSize: pageSize, pageCount: pageCount, freePages: freePages,
            logicalBytes: logicalBytes, freeBytes: freeBytes,
            overheadBytes: logicalBytes - counted, walBytes: walBytes,
            data: data, indexes: indexes, otherFootprint: otherFootprint,
            objects: objects, other: other
        )
    }

    private func storagePragma(_ sql: String) throws -> Int64 {
        let result = try execute(sql, rowLimit: 1)
        guard result.rows.count == 1, result.rows[0].count == 1,
              case .integer(let number) = result.rows[0][0] else {
            throw StorageError.invalidResult("Unexpected result for \(sql).")
        }
        return number
    }

    private func storageWALBytes() throws -> Int64 {
        let result = try execute("PRAGMA database_list", rowLimit: Int.max)
        let decoder = try StorageDecoder(result)
        guard let main = try result.rows.first(where: { try decoder.text("name", in: $0) == "main" }) else {
            throw StorageError.invalidResult("The main database path is missing.")
        }
        let path = try decoder.text("file", in: main)
        guard !path.isEmpty else { return 0 }
        let wal = path + "-wal"
        guard FileManager.default.fileExists(atPath: wal) else { return 0 }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: wal)
            guard let size = attributes[.size] as? NSNumber else {
                throw StorageError.invalidResult("The WAL file size is unavailable.")
            }
            guard size.int64Value >= 0 else { throw StorageError.overflow }
            return size.int64Value
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.unavailable("Could not read the WAL file size: \(error.localizedDescription)")
        }
    }
}

nonisolated private struct StorageDecoder {
    private let positions: [String: Int]

    init(_ result: SQLiteResult) throws {
        positions = Dictionary(uniqueKeysWithValues: result.columns.enumerated().map { ($0.element.lowercased(), $0.offset) })
    }

    func text(_ name: String, in row: [SQLiteValue]) throws -> String {
        guard let index = positions[name], row.indices.contains(index),
              case .text(let value) = row[index] else {
            throw StorageError.invalidResult("Missing or invalid \(name) value.")
        }
        return value
    }

    func integer(_ name: String, in row: [SQLiteValue]) throws -> Int64 {
        guard let index = positions[name], row.indices.contains(index),
              case .integer(let value) = row[index] else {
            throw StorageError.invalidResult("Missing or invalid \(name) value.")
        }
        return value
    }
}
