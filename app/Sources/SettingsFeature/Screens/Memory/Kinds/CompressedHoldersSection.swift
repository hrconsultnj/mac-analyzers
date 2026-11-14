import SwiftUI
import AnalyzersKit
import UIComponents

/// Who holds the most compressed memory: what the system's own `top` says, read when the screen opens and when asked.
struct CompressedHoldersSection: View {

    /// A row of the table: flat, nothing opens.
    struct Row: Identifiable {
        let id: Int
        let name: String
        let account: String
        let footprint: Int64
        let compressed: Int64
        var children: [Row]? { nil }
        var compressedSort: Int64 { compressed }
        var footprintSort: Int64 { footprint }
    }

    @State private var reading: CompressedHoldersReading?
    @State private var loading = false
    @State private var selection: Int?
    @State private var expanded: Set<Int> = []
    @State private var sortOrder = [KeyPathComparator(\Row.compressedSort, order: .reverse)]

    /// Names of the user's own processes as the app knows them ("Claude Code", not the 16 characters `top` has room for, or a
    /// version number); every other process keeps the name `top` gave it.
    @State private var names: [Int: String] = [:]

    private var rows: [Row] {
        (reading?.holders ?? []).map {
            Row(id: $0.pid, name: names[$0.pid] ?? $0.command, account: $0.user, footprint: $0.footprintBytes, compressed: $0.compressedBytes)
        }.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text(Names.MemoryKind.whoHoldsTheMost).font(.title3.weight(.semibold))
                Spacer()
                if let at = reading?.readAt {
                    Text("Read at \(at.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                }
                Button("Refresh") { Task { await load() } }.disabled(loading)
            }
            if let failure = reading?.failure {
                Text("\(failure). The memory the compressor holds, above, is read another way and is unaffected.")
                    .foregroundStyle(.secondary)
            } else {
                OutlineTable(rows, children: \.children, selection: $selection, sortOrder: $sortOrder,
                             expanded: $expanded, autosave: "memory.compressed") {
                    OutlineColumn("name", "Process", text: { $0.name }).width(min: 140, ideal: 240)
                    OutlineColumn("account", "Account", text: { $0.account }).textStyle { _ in .secondary }.width(min: 90, ideal: 130)
                    OutlineColumn("footprint", Names.Monitor.memory, text: { MemorySize.text($0.footprint) },
                                  sortUsing: KeyPathComparator(\Row.footprintSort))
                        .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }.width(min: 76, ideal: 90)
                    OutlineColumn("compressed", Names.MemoryKind.compressed, text: { MemorySize.text($0.compressed) },
                                  sortUsing: KeyPathComparator(\Row.compressedSort))
                        .alignment(.trailing).monospacedDigits().width(min: 90, ideal: 100)
                }
                .emptyContent(isLoading: loading) { Text("Reading…").foregroundStyle(.secondary) }
                .frame(height: 420)     // a table inside a scrolling screen needs a height
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        let fresh = await Task.detached(priority: .userInitiated) { CompressedHolders.read() }.value
        let known = await Task.detached(priority: .userInitiated) { () -> [Int: String] in
            var found: [Int: String] = [:]
            for holder in fresh.holders {
                if let name = LiveStats.process(pid: holder.pid)?.friendlyName, !name.isEmpty { found[holder.pid] = name }
            }
            return found
        }.value
        names = known
        reading = fresh
        loading = false
    }
}
