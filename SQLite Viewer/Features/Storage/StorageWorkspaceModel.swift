import Combine
import Foundation

@MainActor
final class StorageWorkspaceModel: ObservableObject {
    enum Sort: String, CaseIterable {
        case total = "Total bytes"
        case data = "Table bytes"
        case indexes = "Index bytes"
        case name = "Name"
    }

    @Published private(set) var report: StorageReport?
    @Published private(set) var selectedName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var sort: Sort = .total

    let databaseID: UUID
    private let library: DatabaseLibrary
    private var revision = 0
    private var work: Task<Void, Never>?

    init(databaseID: UUID, library: DatabaseLibrary) {
        self.databaseID = databaseID
        self.library = library
    }

    var selectedObject: StorageObject? {
        report?.objects.first { $0.name == selectedName }
    }

    var sortedObjects: [StorageObject] {
        guard let report else { return [] }
        return report.objects.sorted { left, right in
            switch sort {
            case .name:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .total:
                if left.total.bytes != right.total.bytes { return left.total.bytes > right.total.bytes }
            case .data:
                let leftBytes = left.data?.footprint.bytes ?? 0
                let rightBytes = right.data?.footprint.bytes ?? 0
                if leftBytes != rightBytes {
                    return leftBytes > rightBytes
                }
            case .indexes:
                if left.indexFootprint.bytes != right.indexFootprint.bytes {
                    return left.indexFootprint.bytes > right.indexFootprint.bytes
                }
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    func select(_ name: String) {
        selectedName = selectedName == name ? nil : name
    }

    func refresh() {
        revision += 1
        let current = revision
        work?.cancel()
        report = nil
        errorMessage = nil
        isLoading = true
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await library.session(for: databaseID)
                let loaded = try await StorageService(session: session).load()
                guard current == revision, !Task.isCancelled else { return }
                report = loaded
                if !loaded.objects.contains(where: { $0.name == self.selectedName }) {
                    selectedName = nil
                }
                isLoading = false
            } catch {
                guard current == revision, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
