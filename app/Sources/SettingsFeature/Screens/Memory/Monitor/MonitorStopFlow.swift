import SwiftUI
import AnalyzersKit

/// Every way Monitor ends something goes through here: a confirmation that
/// says what will happen, the stop itself (which re-checks each process's
/// start time), and an honest word when some of it could not be reached.
@MainActor @Observable
final class MonitorStopFlow {

    enum Pending: Identifiable {
        case quitApp(name: String, identities: [ProcessIdentity], count: Int, bytes: Int64, hosted: [String: Int])
        case stopProgram(StopTarget)
        case stopProcess(LiveProcess, ProcessIdentity)
        case choose(group: String, programs: [StopTarget])

        var id: String {
            switch self {
            case .quitApp(let name, _, _, _, _): "app-\(name)"
            case .stopProgram(let program): program.id
            case .stopProcess(_, let identity): "process-\(identity.pid)"
            case .choose(let group, _): "choose-\(group)"
            }
        }
    }

    var pending: Pending?
    /// Said after a stop that could not reach everything.
    var notice: String?
    /// The plan for the program being confirmed: the reach, worked out when the dialog opened.
    private(set) var planned: MemoryStop.Pending?
    /// Said in the Quit dialog when what runs inside the app could not be told yet.
    private(set) var quitCaution: String?
    /// Said first in the Quit dialog when Sparehold never quits the app by itself (Never Close, a Connection Tool, in front).
    private(set) var quitProtection: String?
    /// Said first in a single process's Stop dialog when a live coding session is part of it or runs below it.
    private(set) var processProtection: String?
    /// Step two of a stop: what is still running, offered for Force Stop. Each is its own confirmation.
    private(set) var forceOffer: MemoryStop.Pending?
    private var forceQueue: [MemoryStop.Pending] = []

    /// What pressing Stop or Quit on a row starts.
    func begin(_ stop: MonitorStop) {
        switch stop {
        case .none, .unavailable:
            break
        case .quitApp(let name, let identities, let count, let bytes, _, let protection):
            // the sessions inside the app are read live when the dialog opens, like a program's reach
            let live = MemoryStop.quitReach(of: identities, name: name)
            quitCaution = live.caution
            quitProtection = protection
            pending = .quitApp(name: name, identities: identities, count: count, bytes: bytes, hosted: live.hosted)
        case .stopProgram(let program):
            beginProgram(program)
        case .stopProcess(let process, let identity):
            // what protects it is read from the live process table now, like a program's reach
            processProtection = MemoryStop.protectionText(ofProcess: process)
            pending = .stopProcess(process, identity)
        case .choosePrograms(let group, let programs):
            // one program that can be stopped is just that program: no list to choose from
            let stoppable = programs.filter(\.isStoppableByPerson)
            if programs.count == 1, let only = stoppable.first {
                beginProgram(only)
            } else {
                pending = .choose(group: group, programs: programs)
            }
        }
    }

    /// The confirmation for one program says how many processes it will really reach,
    /// computed now; a program the rules refuse never reaches a dialog.
    private func beginProgram(_ program: StopTarget) {
        switch MemoryStop.plan(target: program, asPerson: true) {
        case .refused(let why), .needsChoice(let why, _):
            notice = why
        case .confirm(let plan):
            planned = plan
            pending = .stopProgram(program)
        }
    }

    // MARK: - doing it

    /// Stops what was confirmed. The polite request goes out in the background; a
    /// program that is still running afterwards is said so in `notice`, with Force Stop offered.
    func confirm(_ pending: Pending, chosen: [StopTarget] = []) {
        self.pending = nil
        switch pending {
        case .quitApp(_, let identities, _, _, _):
            report(asked: identities.count, reached: GuardControl.quitApp(identities).count)
        case .stopProgram:
            if let plan = planned { run([plan]) }
            planned = nil
        case .stopProcess(let process, let identity):
            // the person chose it, in a dialog that named what protects it; a session that started meanwhile was not named
            if processProtection == nil, let now = MemoryStop.protectionText(ofProcess: process) {
                _ = now
                notice = "A live coding session became part of \(process.friendlyName) while you were deciding, so nothing was stopped. Press Stop again to see what it would end."
                return
            }
            switch GuardControl.stopProcess(process, identity: identity, overridingProtection: true) {
            case .stopped: break
            case .gone: report(asked: 1, reached: 0)
            case .refused(let why): notice = why
            }
        case .choose:
            var plans: [MemoryStop.Pending] = []
            var refused: [String] = []
            for program in chosen.filter(\.isStoppableByPerson) {
                switch MemoryStop.plan(target: program, asPerson: true) {
                case .confirm(let plan): plans.append(plan)
                case .refused(let why), .needsChoice(let why, _): refused.append(why)
                }
            }
            if !refused.isEmpty { notice = refused.joined(separator: "\n") }
            run(plans)
        }
    }

    /// Step two, confirmed by the person: the processes that did not stop are forced.
    func confirmForce() {
        guard let offer = forceOffer else { return }
        forceOffer = nil
        run([offer])
    }

    func declineForce() {
        forceOffer = nil
        showNextForce()
    }

    private func run(_ steps: [MemoryStop.Pending]) {
        Task {
            var lines: [String] = []
            for step in steps {
                let report = await step.run()
                if let force = report.force {
                    forceQueue.append(force)
                    lines.append(report.message)
                } else if !report.message.hasSuffix("stopped.") {
                    lines.append(report.message)
                }
            }
            if !lines.isEmpty { notice = lines.joined(separator: "\n") }
            showNextForce()
        }
    }

    private func showNextForce() {
        // the notice is read first; the Force Stop question follows it
        guard forceOffer == nil, notice == nil, !forceQueue.isEmpty else { return }
        forceOffer = forceQueue.removeFirst()
    }

    /// Called when the notice is dismissed.
    func noticeDismissed() {
        notice = nil
        showNextForce()
    }

    private func report(asked: Int, reached: Int) {
        guard asked > 0, reached < asked else { return }
        notice = reached == 0
            ? "Nothing was stopped. What you picked had already ended or had changed, so it was left alone."
            : "Stopped \(reached) of \(asked). The rest had already ended or had changed, so they were left alone."
    }
}

// MARK: - the dialogs

struct MonitorStopDialogs: ViewModifier {
    @Bindable var flow: MonitorStopFlow
    /// Look again once macOS has had time to act on a stop.
    let afterStop: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: dialogShown, titleVisibility: .visible) {
                if let pending = flow.pending, !isChoice(pending) {
                    // always destructive-styled; a protected one says "Anyway", because Sparehold would never do this by itself
                    Button(confirmLabel(pending), role: .destructive) { go(pending) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text(message)
            }
            .sheet(item: choiceBinding) { pending in
                if case .choose(let group, let programs) = pending {
                    MonitorStopSheet(group: group, programs: programs,
                                     onCancel: { flow.pending = nil },
                                     onStop: { chosen in go(pending, chosen: chosen) })
                }
            }
            .alert(Names.Stop.leftAlone, isPresented: noticeShown) {
                Button("OK") { flow.noticeDismissed() }
            } message: {
                Text(flow.notice ?? "")
            }
            .confirmationDialog(flow.forceOffer?.title ?? "", isPresented: forceShown, titleVisibility: .visible) {
                if let offer = flow.forceOffer {
                    Button(offer.actionTitle, role: .destructive) { flow.confirmForce() }
                    Button(Names.Stop.leaveRunning, role: .cancel) { flow.declineForce() }
                }
            } message: {
                Text(flow.forceOffer?.detail ?? "")
            }
    }

    private func go(_ pending: MonitorStopFlow.Pending, chosen: [StopTarget] = []) {
        flow.confirm(pending, chosen: chosen)
        Task {
            // an app takes a moment to close its helpers behind it
            try? await Task.sleep(for: .seconds(2))
            afterStop()
        }
    }

    private func isChoice(_ pending: MonitorStopFlow.Pending) -> Bool {
        if case .choose = pending { true } else { false }
    }

    private var dialogShown: Binding<Bool> {
        Binding(get: { flow.pending.map { !isChoice($0) } ?? false },
                set: { if !$0, let pending = flow.pending, !isChoice(pending) { flow.pending = nil } })
    }

    private var choiceBinding: Binding<MonitorStopFlow.Pending?> {
        Binding(get: { flow.pending.flatMap { isChoice($0) ? $0 : nil } },
                set: { if $0 == nil, let pending = flow.pending, isChoice(pending) { flow.pending = nil } })
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { flow.notice != nil }, set: { if !$0 { flow.noticeDismissed() } })
    }

    private var forceShown: Binding<Bool> {
        Binding(get: { flow.forceOffer != nil }, set: { if !$0 { flow.declineForce() } })
    }

    // MARK: - words

    private var title: String {
        switch flow.pending {
        case .quitApp(let name, _, _, _, _): "Quit \(name)?"
        case .stopProgram(let program): "Stop \(program.label)?"
        case .stopProcess(let process, _): "Stop \(process.friendlyName)?"
        case .choose, .none: ""
        }
    }

    private func confirmLabel(_ pending: MonitorStopFlow.Pending) -> String {
        switch pending {
        case .quitApp(let name, _, _, _, _): flow.quitProtection == nil ? "Quit \(name)" : "Quit \(name) Anyway"
        case .stopProgram(let program): flow.planned?.warning == nil ? "Stop \(program.name)" : "Stop \(program.name) Anyway"
        case .stopProcess(let process, _): flow.processProtection == nil ? "Stop \(process.friendlyName)" : "Stop \(process.friendlyName) Anyway"
        case .choose: "Stop"
        }
    }

    private var message: String {
        switch flow.pending {
        case .quitApp(let name, _, let count, let bytes, let hosted):
            let helpers = count - 1
            let who = helpers > 0
                ? "\(name) and its \(helpers) helper process\(helpers == 1 ? "" : "es") will close"
                : "\(name) will close"
            var text = (flow.quitProtection.map { "\($0) " } ?? "")
                + "\(who), giving back about \(MemorySize.text(bytes)). It will still ask before discarding unsaved work."
            if let note = MemoryStop.hostedNote(hosted, appName: name) { text += " \(note)" }
            if let caution = flow.quitCaution { text += " \(caution)" }
            return text
        case .stopProgram(let program):
            // the reach was computed when the dialog opened, and says how many processes it is
            return "\(flow.planned?.detail ?? "It will be asked to stop.") About \(program.totalText) of memory is listed for it."
        case .stopProcess:
            return (flow.processProtection.map { "\($0) " } ?? "") + "It will be asked to stop. Anything it is doing is interrupted."
        case .choose, .none:
            return ""
        }
    }
}

extension View {
    func monitorStopDialogs(_ flow: MonitorStopFlow, afterStop: @escaping () -> Void) -> some View {
        modifier(MonitorStopDialogs(flow: flow, afterStop: afterStop))
    }
}
