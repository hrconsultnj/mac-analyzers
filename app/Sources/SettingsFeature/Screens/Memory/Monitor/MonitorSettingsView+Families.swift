import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory lens: everything that is made of more than one process — one line
/// per app, tool or service (see `MonitorFamilyRow`).
extension MonitorSettingsView {

    @ViewBuilder var familySection: some View {
        if !familyGroups.isEmpty {
            // searching always shows every match — folding a search result
            // would hide the thing that was asked for
            let folded = !showAllFamilies && search.isEmpty
                && familyGroups.count > Self.familyFold
            let visible = folded ? Array(familyGroups.prefix(Self.familyFold)) : familyGroups
            Section("Apps and services — \(familyGroups.count) · \(MemorySize.text(familyGroups.reduce(0) { $0 + $1.totalBytes }))") {
                ForEach(visible) { group in
                    MonitorFamilyRow(
                        group: group,
                        reload: { Task { await load() } },
                        openDossier: { process in
                            dossierPath.append(DossierRoute(name: process.friendlyName,
                                                            pid: process.pid))
                        })
                }
                if folded {
                    foldedTail(familyGroups.dropFirst(Self.familyFold))
                } else if showAllFamilies, search.isEmpty,
                          familyGroups.count > Self.familyFold {
                    Button("Show only the \(Self.familyFold) largest") { showAllFamilies = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// The long tail as one line: how many more, and what they add up to —
    /// so nothing is missing from the sum even while it is folded away.
    private func foldedTail(_ rest: ArraySlice<CensusGroup>) -> some View {
        Button {
            showAllFamilies = true
        } label: {
            HStack {
                Text("Show \(rest.count) smaller ones")
                Spacer()
                Text(MemorySize.text(rest.reduce(0) { $0 + $1.totalBytes }))
                    .font(Tokens.Typography.valueKey)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}
