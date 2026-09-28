import UniformTypeIdentifiers

enum SQLiteDocumentTypes {
    static let identifier = "vnd.sqlite3"
    static let supportedExtensions = ["sqlite", "sqlite3", "db"]
    static let contentTypes: [UTType] = [
        UTType(identifier) ?? UTType(importedAs: identifier, conformingTo: .data)
    ]
}
