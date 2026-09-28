import Foundation

struct SharedFileImportGate {
    private var inFlight: Set<URL> = []
    private var recentlyCompleted: [URL: Date] = [:]
    private let repeatWindow: TimeInterval = 2

    mutating func begin(_ url: URL, at date: Date = Date()) -> Bool {
        guard !inFlight.contains(url) else { return false }
        if let completed = recentlyCompleted[url], date.timeIntervalSince(completed) < repeatWindow {
            return false
        }
        recentlyCompleted = recentlyCompleted.filter {
            date.timeIntervalSince($0.value) < repeatWindow
        }
        inFlight.insert(url)
        return true
    }

    mutating func finish(_ url: URL, succeeded: Bool, at date: Date = Date()) {
        inFlight.remove(url)
        if succeeded { recentlyCompleted[url] = date }
    }
}
