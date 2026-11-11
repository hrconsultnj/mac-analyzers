import AppKit
import AnalyzersKit
import SwiftUI

/// The selected startup item in full: what it is, where it lives, what it
/// runs and why the audit flagged it. Actions sit at the bottom.
struct StartupItemInspector: View {
    let item: StartupItem
    let onShowInFinder: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Form {
            Section {
                Label { Text(item.name) } icon: { StartupIcon(item: item) }.font(.headline)
                LabeledContent("Belongs To", value: item.owner)
                LabeledContent("Kind", value: item.kindTitle)
                LabeledContent("State", value: item.stateTitle)
                LabeledContent("Needs Administrator", value: item.administratorTitle)
            }
            Section("What the Audit Found") {
                Text(item.findingTitle.isEmpty ? "No problem" : item.findingTitle)
                    .font(.headline)
                    .foregroundStyle(item.findingColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                Text(item.explanation).foregroundStyle(.secondary)
            }
            Section("Where It Lives") {
                Text(item.whereItLives)
                if let plist = item.plistPath { path("Settings file", plist) }
            }
            if let target = item.targetPath {
                Section("What It Runs") { path(nil, target) }
            }
            if let command = item.fixCommand {
                Section("To Remove It") {
                    Text("This needs an administrator. Run it yourself in Terminal if you decide to remove it.")
                        .foregroundStyle(.secondary)
                    Text(command).font(.callout.monospaced()).textSelection(.enabled)
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                }
            }
            Section {
                Button("Show in Finder", action: onShowInFinder).disabled(item.revealPath == nil)
                if item.canRemove {
                    Button(StartupRemoval.canNarrowToSelection ? "Remove Leftover…" : "Remove Leftovers…",
                           role: .destructive, action: onRemove)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func path(_ title: String?, _ value: String) -> some View {
        let text = Text(value).font(.callout.monospaced()).textSelection(.enabled)
        if let title { LabeledContent(title) { text } } else { text }
    }
}

/// A selected group: the app or developer, and its items at a glance.
struct StartupGroupInspector: View {
    let group: StartupGroup

    var body: some View {
        Form {
            Section {
                Text(group.name).font(.headline)
                LabeledContent("Items", value: group.countText)
                LabeledContent("State", value: group.stateSummary)
            }
            Section("Items") {
                ForEach(group.items) { item in
                    LabeledContent(item.name) {
                        Text([item.kind.title, item.findingTitle].filter { !$0.isEmpty }.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
