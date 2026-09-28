import Combine
import Foundation

@MainActor
final class SQLConsoleModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var result: SQLScriptResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false
    @Published private(set) var completedVersion = 0

    let databaseID: UUID
    private let library: DatabaseLibrary
    private var cancellation: SQLCancellationToken?
    private var work: Task<Void, Never>?

    init(databaseID: UUID, library: DatabaseLibrary) {
        self.databaseID = databaseID
        self.library = library
    }

    func run() {
        guard !isRunning else { return }
        let submitted = draft
        let token = SQLCancellationToken()
        cancellation = token
        result = nil
        errorMessage = nil
        isRunning = true
        isCancelling = false
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await library.session(for: databaseID)
                let output = try await SQLService(session: session).run(submitted, cancellation: token)
                result = output
                if !output.blocks.isEmpty { completedVersion += 1 }
            } catch {
                errorMessage = error.localizedDescription
            }
            cancellation = nil
            isRunning = false
            isCancelling = false
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancellation?.cancel()
        isCancelling = true
    }
}
