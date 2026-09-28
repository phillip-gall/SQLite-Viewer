import Combine
import Foundation

@MainActor
final class SchemaWorkspaceModel: ObservableObject {
    @Published private(set) var catalog: [SchemaObject] = []
    @Published private(set) var shadowNames: Set<String> = []
    @Published private(set) var selected: SchemaObject?
    @Published private(set) var tableDetail: TableViewDetail?
    @Published private(set) var indexes: [SchemaIndex] = []
    @Published private(set) var selectedIndex: SchemaIndex?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshVersion = 0

    let databaseID: UUID
    private let library: DatabaseLibrary
    private var revision = 0
    private var work: Task<Void, Never>?

    init(databaseID: UUID, library: DatabaseLibrary) {
        self.databaseID = databaseID
        self.library = library
    }

    var selectedID: String? { selected?.id }

    func select(id: String?) {
        revision += 1
        let current = revision
        work?.cancel()
        selected = catalog.first { $0.id == id }
        clearDetails()
        errorMessage = nil
        guard let selected else { isLoading = false; return }
        isLoading = true
        work = Task { [weak self] in
            await self?.loadDetails(for: selected, revision: current)
        }
    }

    func refreshSchema() {
        revision += 1
        let current = revision
        work?.cancel()
        isLoading = true
        errorMessage = nil
        clearDetails()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await library.session(for: databaseID)
                let service = SchemaService(session: session)
                let objects = try await service.loadCatalog()
                let shadows = try await service.loadShadowTableNames()
                guard current == revision, !Task.isCancelled else { return }
                catalog = objects
                shadowNames = shadows
                selected = selected.flatMap { previous in objects.first { $0.id == previous.id } }
                refreshVersion += 1
                if let selected {
                    await loadDetails(for: selected, revision: current, service: service)
                } else {
                    isLoading = false
                }
            } catch {
                guard current == revision, !Task.isCancelled else { return }
                catalog = []
                shadowNames = []
                selected = nil
                clearDetails()
                errorMessage = error.localizedDescription
                isLoading = false
                refreshVersion += 1
            }
        }
    }

    func invalidate() {
        revision += 1
        work?.cancel()
        catalog = []
        shadowNames = []
        selected = nil
        clearDetails()
        isLoading = false
    }

    private func loadDetails(for object: SchemaObject, revision current: Int,
                             service existing: SchemaService? = nil) async {
        do {
            let service: SchemaService
            if let existing { service = existing }
            else { service = SchemaService(session: try await library.session(for: databaseID)) }
            var table: TableViewDetail?
            var loadedIndexes: [SchemaIndex] = []
            var index: SchemaIndex?
            switch object.kind {
            case .table:
                table = try await service.loadTableViewDetail(object)
                if table?.tableKind == .ordinary { loadedIndexes = try await service.loadIndexes(for: object) }
            case .view:
                table = try await service.loadTableViewDetail(object)
            case .index:
                guard let owner = try await service.loadCatalog().first(where: {
                    $0.kind == .table && $0.name == object.tableName
                }) else { throw SchemaError.missingObject(object.tableName) }
                index = try await service.loadIndexes(for: owner).first { $0.name == object.name }
                if index == nil { throw SchemaError.missingObject(object.name) }
            case .trigger: break
            }
            guard current == revision, !Task.isCancelled else { return }
            tableDetail = table
            indexes = loadedIndexes
            selectedIndex = index
            errorMessage = nil
            isLoading = false
        } catch {
            guard current == revision, !Task.isCancelled else { return }
            clearDetails()
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func clearDetails() {
        tableDetail = nil
        indexes = []
        selectedIndex = nil
    }
}
