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
    @Published private(set) var filters: [RowFilter] = []
    @Published private(set) var matchingCount: Int64?
    @Published private(set) var matchingCountError: String?
    @Published private(set) var removedFilterMessage: String?

    let databaseID: UUID
    private let library: DatabaseLibrary
    private var locations: [String: Location] = [:]
    private var revision = 0
    private var work: Task<Void, Never>?

    private struct Location {
        var page: Int = 1
        var sort: RowSort?
        var filters: [RowFilter] = []
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
        filters = location.filters
        removedFilterMessage = nil
        load()
    }

    func showPage(_ number: Int) {
        guard let selected, number > 0 else { return }
        pageNumber = number
        locations[selected.id] = Location(page: number, sort: sort, filters: filters)
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
        locations[selected.id] = Location(page: 1, sort: sort, filters: filters)
        load()
    }

    func clearSort() {
        guard let selected else { return }
        sort = nil
        pageNumber = 1
        locations[selected.id] = Location(page: 1, sort: nil, filters: filters)
        load()
    }

    func applyFilters(_ updated: [RowFilter]) {
        guard let selected else { return }
        filters = updated
        pageNumber = 1
        removedFilterMessage = nil
        locations[selected.id] = Location(page: 1, sort: sort, filters: updated)
        load()
    }

    func reload() { if selected != nil { load() } }

    func invalidateVisiblePage() {
        revision += 1
        work?.cancel()
        page = nil
        matchingCount = nil
        matchingCountError = nil
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
            matchingCount = nil
            matchingCountError = nil
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
        filters = []
        matchingCount = nil
        matchingCountError = nil
        removedFilterMessage = nil
        locations = [:]
        errorMessage = nil
        isLoading = false
    }

    private func load() {
        revision += 1
        let current = revision
        work?.cancel()
        page = nil
        matchingCount = nil
        matchingCountError = nil
        errorMessage = nil
        isLoading = true
        guard let selected else { isLoading = false; return }
        let number = pageNumber
        let sort = sort
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await library.session(for: databaseID)
                let detail = try await SchemaService(session: session).loadTableViewDetail(selected)
                guard current == revision, !Task.isCancelled else { return }
                let names = Set(detail.columns.map(\.name))
                let validFilters = filters.filter { names.contains($0.column) }
                let removed = filters.filter { !names.contains($0.column) }
                if !removed.isEmpty {
                    filters = validFilters
                    locations[selected.id] = Location(page: number, sort: sort, filters: validFilters)
                    removedFilterMessage = "Removed filters for missing columns: " +
                        removed.map(\.column).joined(separator: ", ")
                }
                let loaded = try await RowsService(session: session).loadPage(
                    for: selected, number: number, sort: sort, filters: validFilters
                )
                guard current == revision, !Task.isCancelled else { return }
                page = loaded
                isLoading = false
                if !validFilters.isEmpty {
                    do {
                        let count = try await TableCountService(session: session).countMatching(
                            selected, filters: validFilters
                        )
                        guard current == revision, !Task.isCancelled else { return }
                        matchingCount = count
                    } catch {
                        guard current == revision, !Task.isCancelled else { return }
                        matchingCountError = error.localizedDescription
                    }
                }
            } catch {
                guard current == revision, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
