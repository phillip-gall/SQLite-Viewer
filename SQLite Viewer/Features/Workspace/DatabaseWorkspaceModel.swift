import Combine
import Foundation

/// Coordinates cross-feature invalidation and selection outside the view layer.
@MainActor
final class DatabaseWorkspaceModel: ObservableObject {
    enum Destination: String, CaseIterable, Identifiable {
        case schema, rows, sql, storage
        var id: String { rawValue }
        var title: String {
            switch self {
            case .schema: "Schema"
            case .rows: "Rows"
            case .sql: "SQL"
            case .storage: "Storage"
            }
        }
        var symbol: String {
            switch self {
            case .schema: "square.stack.3d.up"
            case .rows: "tablecells"
            case .sql: "chevron.left.forwardslash.chevron.right"
            case .storage: "externaldrive"
            }
        }
    }

    @Published var destination: Destination = .schema
    let schema: SchemaWorkspaceModel
    let rows: RowsWorkspaceModel
    let storage: StorageWorkspaceModel
    let sql: SQLConsoleModel
    let counts: TableCountStore
    private var subscriptions = Set<AnyCancellable>()

    init(databaseID: UUID, library: DatabaseLibrary) {
        schema = SchemaWorkspaceModel(databaseID: databaseID, library: library)
        rows = RowsWorkspaceModel(databaseID: databaseID, library: library)
        storage = StorageWorkspaceModel(databaseID: databaseID, library: library)
        sql = SQLConsoleModel(databaseID: databaseID, library: library)
        counts = TableCountStore(databaseID: databaseID, library: library)

        schema.$refreshVersion.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            rows.invalidateAndReload(availableObjects: schema.catalog)
        }.store(in: &subscriptions)
        sql.$completedVersion.dropFirst().sink { [weak self] _ in
            self?.refreshSchema()
            self?.storage.refresh()
        }.store(in: &subscriptions)
    }

    func refreshSchema() {
        counts.invalidate()
        rows.invalidateVisiblePage()
        schema.refreshSchema()
    }

    func browseRows(_ object: SchemaObject) {
        rows.select(object)
        destination = .rows
    }

    func select(_ object: SchemaObject) {
        schema.select(id: object.id)
        if destination == .rows, object.kind == .table || object.kind == .view {
            rows.select(object)
        } else {
            destination = .schema
        }
    }
}
