import Foundation

nonisolated enum StorageCategory: String, CaseIterable, Sendable {
    case tableData
    case indexes
    case other
    case free
    case overhead

    var label: String {
        switch self {
        case .tableData: "Table data"
        case .indexes: "Indexes"
        case .other: "Other B-trees"
        case .free: "Free pages"
        case .overhead: "Overhead"
        }
    }
}

nonisolated struct StorageContributor: Identifiable, Sendable {
    let name: String
    let description: String?
    let bytes: Int64

    var id: String { name }
}

nonisolated struct StorageCategoryBreakdown: Sendable {
    let category: StorageCategory
    let bytes: Int64
    let logicalBytes: Int64
    let contributors: [StorageContributor]

    var shareOfLogical: Double {
        logicalBytes > 0 ? Double(bytes) / Double(logicalBytes) : 0
    }

    func share(of contributor: StorageContributor) -> Double {
        bytes > 0 ? Double(contributor.bytes) / Double(bytes) : 0
    }

    static func all(from report: StorageReport) throws -> [StorageCategory: StorageCategoryBreakdown] {
        let totals: [StorageCategory: Int64] = [
            .tableData: report.data.bytes,
            .indexes: report.indexes.bytes,
            .other: report.otherFootprint.bytes,
            .free: report.freeBytes,
            .overhead: report.overheadBytes
        ]
        var result: [StorageCategory: StorageCategoryBreakdown] = [:]
        for category in StorageCategory.allCases {
            let total = totals[category] ?? 0
            guard total >= 0 else { throw StorageError.invalidResult("Negative category bytes.") }
            var contributors: [StorageContributor]
            switch category {
            case .tableData:
                contributors = report.objects.compactMap { object in
                    guard let tree = object.data else { return nil }
                    return StorageContributor(name: object.name, description: nil,
                                              bytes: tree.footprint.bytes)
                }
            case .indexes:
                contributors = report.objects.compactMap { object in
                    guard object.indexFootprint.bytes > 0 else { return nil }
                    return StorageContributor(name: object.name, description: nil,
                                              bytes: object.indexFootprint.bytes)
                }
            case .other:
                contributors = report.other.map {
                    StorageContributor(name: $0.tree.name, description: $0.description,
                                       bytes: $0.tree.footprint.bytes)
                }
            case .free:
                contributors = total > 0 ? [StorageContributor(
                    name: "Unassigned", description: "Free pages have no table owner.", bytes: total
                )] : []
            case .overhead:
                contributors = total > 0 ? [StorageContributor(
                    name: "Unassigned", description: "Pages not assigned to a B-tree by dbstat.", bytes: total
                )] : []
            }
            guard !contributors.contains(where: { $0.bytes < 0 }) else {
                throw StorageError.invalidResult("Negative contributor bytes.")
            }
            contributors.removeAll { $0.bytes == 0 }
            contributors.sort {
                if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
                return $0.name < $1.name
            }
            var sum: Int64 = 0
            for item in contributors {
                let (next, overflow) = sum.addingReportingOverflow(item.bytes)
                guard !overflow else { throw StorageError.overflow }
                sum = next
            }
            guard sum == total else {
                throw StorageError.invalidResult("\(category.label) contributors do not match the category total.")
            }
            result[category] = StorageCategoryBreakdown(
                category: category, bytes: total, logicalBytes: report.logicalBytes,
                contributors: contributors
            )
        }
        let sum = try result.values.reduce(Int64(0)) { partial, item in
            let (next, overflow) = partial.addingReportingOverflow(item.bytes)
            guard !overflow else { throw StorageError.overflow }
            return next
        }
        guard sum == report.logicalBytes else {
            throw StorageError.invalidResult("Storage categories do not match the logical total.")
        }
        return result
    }
}
