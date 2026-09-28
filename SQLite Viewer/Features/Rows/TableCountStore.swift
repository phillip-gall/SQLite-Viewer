import Combine
import Foundation

@MainActor
final class TableCountStore: ObservableObject {
    enum State: Equatable {
        case counting
        case value(Int64)
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]

    private let databaseID: UUID
    private let library: DatabaseLibrary
    private var pending: [SchemaObject] = []
    private var worker: Task<Void, Never>?
    private var generation = 0

    init(databaseID: UUID, library: DatabaseLibrary) {
        self.databaseID = databaseID
        self.library = library
    }

    func state(for object: SchemaObject) -> State? { states[object.id] }

    func request(_ object: SchemaObject, priority: Bool = false) {
        guard object.kind == .table, states[object.id] == nil else { return }
        states[object.id] = .counting
        if priority { pending.insert(object, at: 0) }
        else { pending.append(object) }
        startWorkerIfNeeded()
    }

    func invalidate() {
        generation += 1
        worker?.cancel()
        worker = nil
        pending = []
        states = [:]
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !pending.isEmpty else { return }
        let current = generation
        worker = Task { [weak self] in
            await self?.process(current)
        }
    }

    private func process(_ current: Int) async {
        while current == generation, !Task.isCancelled, !pending.isEmpty {
            let object = pending.removeFirst()
            do {
                let session = try await library.session(for: databaseID)
                let count = try await TableCountService(session: session).count(object)
                guard current == generation, !Task.isCancelled else { return }
                states[object.id] = .value(count)
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                states[object.id] = .failed(error.localizedDescription)
            }
        }
        guard current == generation else { return }
        worker = nil
    }
}
