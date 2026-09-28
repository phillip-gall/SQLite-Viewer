import SwiftUI

struct StorageWorkspaceView: View {
    @ObservedObject var model: StorageWorkspaceModel

    var body: some View {
        Group {
            if let report = model.report {
                reportView(report)
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Storage unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { model.refresh() }
                }
                .accessibilityIdentifier("storage-error")
            } else {
                ProgressView("Analyzing storage")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Storage")
        .task {
            if model.report == nil && !model.isLoading && model.errorMessage == nil {
                model.refresh()
            }
        }
    }

    private func reportView(_ report: StorageReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Logical database")
                        .font(.title2.bold())
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                        .accessibilityIdentifier("storage-refresh")
                }
                Text(bytes(report.logicalBytes))
                    .font(.title.monospacedDigit().bold())
                    .accessibilityIdentifier("storage-total")
                Text("\(report.pageCount) pages × \(bytes(report.pageSize)) per page. WAL is shown separately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                distribution(report)

                if report.walBytes > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WAL sidecar: \(bytes(report.walBytes))")
                            .font(.headline)
                            .accessibilityIdentifier("storage-wal")
                        Text("WAL bytes are physical sidecar bytes outside the logical page total.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Tables and views").font(.title3.bold())
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $model.sort) {
                            ForEach(StorageWorkspaceModel.Sort.allCases, id: \.self) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }
                    } label: {
                        Label(model.sort.rawValue, systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("storage-sort")
                }

                if let selected = model.selectedObject {
                    selectedDetail(selected, logicalBytes: report.logicalBytes)
                }

                if model.sortedObjects.isEmpty {
                    ContentUnavailableView("No user tables", systemImage: "externaldrive")
                } else {
                    LazyVStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Table").frame(width: 68, alignment: .trailing)
                            Text("Index").frame(width: 68, alignment: .trailing)
                            Text("Total").frame(width: 68, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        ForEach(model.sortedObjects) { object in
                            Button { model.select(object.name) } label: {
                                tableRow(object)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("storage-table:\(object.name)")
                        }
                    }
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }

                if !report.other.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Other B-trees").font(.title3.bold())
                        Text("SQLite internal and unassigned trees stay here, including virtual table shadow storage.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(report.other) { item in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.tree.name)
                                        .font(.subheadline.monospaced())
                                    Text(item.description)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(bytes(item.tree.footprint.bytes)).monospacedDigit()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .accessibilityIdentifier("storage-other")
                }
            }
            .padding()
        }
    }

    private func distribution(_ report: StorageReport) -> some View {
        let segments: [(label: String, value: Int64, color: Color)] = [
            ("Table data", report.data.bytes, .blue),
            ("Indexes", report.indexes.bytes, .green),
            ("Other B-trees", report.otherFootprint.bytes, .purple),
            ("Free pages", report.freeBytes, .orange),
            ("Overhead", report.overheadBytes, .gray)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                if report.logicalBytes > 0 {
                    HStack(spacing: 0) {
                        ForEach(segments.indices, id: \.self) { index in
                            let segment = segments[index]
                            if segment.value > 0 {
                                segment.color
                                    .frame(width: geometry.size.width *
                                           CGFloat(Double(segment.value) / Double(report.logicalBytes)))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
            }
            .frame(height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(segments.map { "\($0.label) \(bytes($0.value))" }.joined(separator: ", "))
            .accessibilityIdentifier("storage-chart")

            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(segment.color)
                        .frame(width: 12, height: 12)
                    Text(segment.label)
                    Spacer()
                    Text(bytes(segment.value))
                        .monospacedDigit()
                    Text(percent(segment.value, of: report.logicalBytes))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
                .font(.subheadline)
            }
            Text("Free pages: \(report.freePages). Overhead includes pages dbstat does not assign to a B-tree.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tableRow(_ object: StorageObject) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(object.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(object.kind == .view ? "View" :
                     object.kind == .virtualTable ? "Virtual" : "Table")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(bytes(object.data?.footprint.bytes ?? 0))
                .frame(width: 68, alignment: .trailing)
            Text(bytes(object.indexFootprint.bytes))
                .frame(width: 68, alignment: .trailing)
            Text(bytes(object.total.bytes))
                .frame(width: 68, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .padding(12)
        .contentShape(Rectangle())
        .accessibilityLabel("\(object.name), \(object.kind.rawValue), table \(bytes(object.data?.footprint.bytes ?? 0)), indexes \(bytes(object.indexFootprint.bytes)), total \(bytes(object.total.bytes))")
    }

    private func selectedDetail(_ object: StorageObject, logicalBytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(object.name).font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") { model.select(object.name) }
                    .labelStyle(.iconOnly)
            }
            if object.kind == .view {
                Text("Views have no B-tree storage.")
            } else {
                if object.kind == .virtualTable {
                    Text("This virtual table's shadow B-trees appear in Other.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Table data", value: bytes(object.data?.footprint.bytes ?? 0))
                LabeledContent("Indexes", value: bytes(object.indexFootprint.bytes))
                LabeledContent("Inclusive total", value: bytes(object.total.bytes))
                LabeledContent("Logical share", value: percent(object.total.bytes, of: logicalBytes))
                LabeledContent("Pages", value: String(object.total.pages))
                LabeledContent("Payload", value: bytes(object.total.payload))
                LabeledContent("Unused", value: bytes(object.total.unused))
                if !object.indexes.isEmpty {
                    Divider()
                    Text("Index B-trees").font(.subheadline.bold())
                    ForEach(object.indexes) { index in
                        LabeledContent(index.name, value: bytes(index.footprint.bytes))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("storage-detail")
    }

    private func bytes(_ value: Int64) -> String {
        if value == 0 { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.1f%%", Double(value) * 100 / Double(total))
    }
}
