import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// Reports: the memory and storage reports the analyzers write, as a reader.
/// The list of reports is on the left, named for when each was written; the
/// selected one is drawn on the right as a document, not as raw text.
///
/// One job per file next to it:
///   ReportsModel.swift      the reports on disk, the open one, the jobs that write new ones
///   ReportList.swift        the left side (the months and their reports)
///   ReportBlocksView.swift  the right side: headings, tables, lists, code
///   (the Markdown as written is the shared RawOutputScreen, opened from the top)
///   ReportFile.swift        what Export hands to the save panel
///
/// Toolbar, in the order it gives up space: Write Report stays; Stop, Export
/// and Show Source move into the system's overflow first.
struct ReportsView: View {

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = ReportsModel()
    @State private var kind: ReportDocument.Kind = .memory
    @State private var expanded: Set<String> = []
    /// The months that are open, kept across window close and relaunch.
    @State private var monthsOpen = RememberedExpansion<String>(screen: "reports")
    /// The section a "Sections" menu entry asked to scroll to.
    @State private var jumpTo: String?
    @State private var exporting = false

    private var months: [ReportMonth] { ReportMonth.months(of: model.reports(of: kind)) }

    var body: some View {
        // The left side is a list and the right a document. Not an HSplitView:
        // inside the main window's detail column it took the sum of its panes'
        // ideal widths as its minimum, so at 900 points the sidebar was squeezed
        // and the window's contents ran past its edges (rendered and checked).
        DataScreen(title: Names.Screen.reports, subtitle: subtitle) {
        HStack(spacing: 0) {
            ReportList(months: months, selection: $model.selection, expansion: monthsOpen,
                       onShowInFinder: reveal)
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
            Divider()
            reader
                .frame(minWidth: 280, idealWidth: 480, maxWidth: .infinity)
        }
        }
        .scopeTabsToolbar(screen: "reports", items: tabs, selection: $kind)
        .toolbar { toolbar }
        .fileExporter(isPresented: $exporting,
                      document: ReportFile(text: model.selected?.text() ?? ""),
                      contentType: ReportFile.markdown,
                      defaultFilename: model.selected?.url.deletingPathExtension().lastPathComponent ?? "Report") { _ in }
        .task {
            model.adopt(from: store)
            await model.reload()
            if let newest = model.reports.first { kind = newest.kind }
            applyPendingLink()
        }
        .onChange(of: kind) {
            if model.selected?.kind != kind { model.selection = months.first?.reports.first?.id }
        }
        .onChange(of: model.selection) { openFirstSections() }
        // the newest month starts open; never once a person opened or closed one
        .onChange(of: months.first?.id, initial: true) {
            monthsOpen.seedIfUntouched(months.first.map { [ReportList.key($0)] } ?? [])
        }
        .onChange(of: model.sections) { openFirstSections() }
        // a link opened while Reports is already showing
        .onChange(of: navigator.pendingIntent) { applyPendingLink() }
        // when a report job ends, read what it wrote and show it
        .onChange(of: model.stamps) { old, new in
            for (kind, (before, after)) in zip(ReportDocument.Kind.allCases, zip(old, new))
            where before != after && after.stage == .succeeded {
                Task { await model.reload(selectNewestOf: kind) }
            }
        }
    }

    @ViewBuilder private var reader: some View {
        if let report = model.selected, model.blocksFor == report.id {
            ReportBlocksView(preface: model.preface, sections: model.sections, expanded: $expanded,
                             jumpTo: $jumpTo)
        } else if model.selected != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No Report Selected", systemImage: "doc.text")
            } description: {
                Text(model.loaded ? "Pick a report on the left, or write a new one." : "Looking for reports…")
            }
        }
    }

    /// A report opens with its first two sections open; the rest are one click each.
    private func openFirstSections() {
        expanded = Set(model.sections.prefix(2).map(\.id))
    }

    private var tabs: [ScopeTabItem<ReportDocument.Kind>] {
        ReportDocument.Kind.allCases.map {
            ScopeTabItem(value: $0, title: $0.tabTitle, symbol: $0.symbol,
                         count: model.loaded ? model.reports(of: $0).count : nil)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(ReportDocument.Kind.allCases, id: \.self) { kind in
                    Button { model.write(kind, in: store) } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                    .help(kind == .memory ? "Takes a few seconds" : "Takes a minute or two on a full disk")
                }
            } label: {
                Label("Write Report", systemImage: "doc.badge.plus")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.writing != nil)
            .help("Write a new report. Reports only read; nothing is moved, deleted or stopped.")
        }
        .toolbarRank(.primary)

        ToolbarItem(placement: .primaryAction) {
            Button { navigator.open(target: "activity:find:\(Names.job(kind == .memory ? .memoryReport : .storageReport))") } label: {
                Label("Past Runs", systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.titleAndIcon)
            .help("See every earlier report in Activity")
        }
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                .labelStyle(.titleAndIcon)
                .disabled(model.writing == nil)
                .help("Stop writing the report")
        }
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(model.sections) { section in
                    Button(section.title) {
                        expanded.insert(section.id)
                        jumpTo = section.id
                    }
                }
            } label: {
                Label("Sections", systemImage: "list.number")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.sections.isEmpty)
            .help("Jump to a section of this report")
        }
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Button { exporting = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .labelStyle(.titleAndIcon)
                .disabled(model.selected == nil)
                .help("Save a copy of this report")
        }
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let report = model.selected { navigator.push(.overview(.raw(.file(report.url, fromTop: true)))) }
            } label: { Label("Show Source", systemImage: "curlybraces") }
                .labelStyle(.titleAndIcon)
                .disabled(model.selected == nil)
                .help("See the report's text exactly as written")
        }
        .toolbarRank(.secondary)
    }

    private var subtitle: String {
        if let kind = model.writing {
            return "Writing the \(kind == .memory ? "memory" : "storage") report…"
        }
        if let failure = model.failure { return failure }
        let ofKind = model.reports(of: kind)
        guard let newest = ofKind.first else { return model.loaded ? "No reports yet" : "Looking…" }
        // one short fact; the count is on the tab
        return "Newest \(newest.date.formatted(.relative(presentation: .named)))"
    }

    /// A deep link's request: open the nth report, or push its source.
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: SystemGroup.reports) else { return }
        if payload.hasPrefix("pick:"), let n = Int(payload.dropFirst("pick:".count)) {
            let all = months.flatMap(\.reports)
            if all.indices.contains(n) { model.selection = all[n].id }
        }
        // month:<n> opens the nth month; section:<n> jumps to the nth section
        if payload.hasPrefix("month:"), let n = Int(payload.dropFirst("month:".count)), months.indices.contains(n) {
            let open = monthsOpen.binding
            open.wrappedValue.insert(ReportList.key(months[n]))
        }
        if payload.hasPrefix("section:"), let n = Int(payload.dropFirst("section:".count)), model.sections.indices.contains(n) {
            expanded.insert(model.sections[n].id)
            jumpTo = model.sections[n].id
        }
        if payload == "storage" { kind = .storage }
        if payload == "memory" { kind = .memory }
        if payload == "raw", let report = model.selected {
            navigator.push(.overview(.raw(.file(report.url, fromTop: true))))
        }
    }

    private func reveal(_ report: ReportDocument) {
        NSWorkspace.shared.activateFileViewerSelecting([report.url])
    }
}
