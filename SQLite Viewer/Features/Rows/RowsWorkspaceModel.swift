import Combine
import Foundation

@MainActor
final class RowsWorkspaceModel: ObservableObject {
    @Published private(set) var selected: SchemaObject?
    @Published private(set) var page: RowPage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pageNumber = 1
    @Published private(set) var sort: RowSort?

    let databaseID: UUID
    private let library: DatabaseLibrary
    private var locations: [String: Location] = [:]
    private var revision = 0
    private var work: Task<Void, Never>?

    private struct Location {
        var page: Int = 1
        var sort: RowSort?
    }

    init(databaseID: UUID, library: DatabaseLibrary) {
        self.databaseID = databaseID
        self.library = library
    }

    func select(_ object: SchemaObject) {
        guard object.kind == .table || object.kind == .view else { return }
        guard selected?.id != object.id else { return }
        selected = object
        let location = locations[object.id] ?? Location()
        pageNumber = location.page
        sort = location.sort
        load()
    }

    func showPage(_ number: Int) {
        guard let selected, number > 0 else { return }
        pageNumber = number
        locations[selected.id] = Location(page: number, sort: sort)
        load()
    }

    func setSort(_ column: String) {
        guard let selected else { return }
        if sort?.column == column {
            sort = RowSort(column: column, descending: !(sort?.descending ?? false))
        } else {
            sort = RowSort(column: column, descending: false)
        }
        pageNumber = 1
        locations[selected.id] = Location(page: 1, sort: sort)
        load()
    }

    func clearSort() {
        guard let selected else { return }
        sort = nil
        pageNumber = 1
        locations[selected.id] = Location()
        load()
    }

    func reload() { if selected != nil { load() } }

    func invalidateVisiblePage() {
        revision += 1
        work?.cancel()
        page = nil
        errorMessage = nil
        isLoading = selected != nil
    }

    /// Call after a schema refresh or SQL write. No previously visited pages are retained.
    func invalidateAndReload(availableObjects: [SchemaObject]? = nil) {
        if let availableObjects {
            let valid = Set(availableObjects.map(\.id))
            locations = locations.filter { valid.contains($0.key) }
            if let selected {
                self.selected = availableObjects.first { $0.id == selected.id }
            }
        }
        if selected == nil {
            revision += 1
            work?.cancel()
            page = nil
            errorMessage = nil
            isLoading = false
        } else {
            load()
        }
    }

    func invalidate() {
        revision += 1
        work?.cancel()
        selected = nil
        page = nil
        locations = [:]
        errorMessage = nil
        isLoading = false
    }

    private func load() {
        revision += 1
        let current = revision
        work?.cancel()
        page = nil
        errorMessage = nil
        isLoading = true
        guard let selected else { isLoading = false; return }
        let number = pageNumber
        let sort = sort
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await library.session(for: databaseID)
                let loaded = try await RowsService(session: session).loadPage(
                    for: selected, number: number, sort: sort
                )
                guard current == revision, !Task.isCancelled else { return }
                page = loaded
                isLoading = false
            } catch {
                guard current == revision, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
