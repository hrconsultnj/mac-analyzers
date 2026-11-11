import Foundation

/// What the menu-bar panel does with a row's Quit or Stop. The panel signals nothing itself:
/// it asks `MemoryStop` for a plan built from the live process table at that moment, shows a
/// refusal as the sentence it gives, confirms a plan with the person using the plan's own title,
/// detail and action word, and never goes on to a Force Stop (that stays in Monitor, which has the
/// second, separate confirmation).
///
/// This is the whole of the panel's decision, in the kernel so a probe can run exactly what the
/// panel runs against processes the probe started itself (`agent-runner --probe-panel-stop`).
@MainActor
public enum PanelStop {

    /// What a row offers before anything is clicked.
    public enum Offer: Equatable, Sendable {
        /// An app: ⌘Q semantics, still asking about unsaved work.
        case quit
        /// One program of command-line tools that may be stopped.
        case stop
        /// Nothing is offered, and this is why, in the sentence `MemoryStop` gives.
        case locked(String)
    }

    /// The offer for a row's group, from what the census saw. Cheap: it reads no process table (the
    /// plan that does is built when the button is pressed).
    public static func offer(for group: CensusGroup) -> Offer {
        switch group.quit {
        case .app:
            return .quit
        case .unavailable:
            return .locked(MemoryStop.plan(group: group).message)
        case .tools:
            // without the list of coding agents no Stop is offered at all (the panel says why once)
            if !CodingAgentHosts.isAvailable { return .locked(CodingAgentHosts.unavailableSentence) }
            if group.programs.contains(where: \.isStoppable) { return .stop }
            return .locked(MemoryStop.plan(group: group).message)
        }
    }

    /// What pressing the button leads to.
    public enum Step {
        /// Confirm with the person first: nothing has been sent.
        case ask(MemoryStop.Pending)
        /// Nothing was done, and why, to be shown on the row.
        case say(String)
        /// Several separate programs, or something only Monitor may do: the reason, and the deep link that opens it.
        case openMonitor(reason: String, link: String)
    }

    /// Plans the stop for a row, from the live process table now.
    public static func begin(group: CensusGroup) -> Step {
        switch MemoryStop.plan(group: group) {
        case .confirm(let pending): .ask(pending)
        case .refused(let why): .say(why)
        case .needsChoice(let reason, let link): .openMonitor(reason: reason, link: link)
        }
    }

    /// What a confirmed stop did.
    public struct Done: Sendable {
        /// A sentence for the row; nil when it stopped and there is nothing to add.
        public let message: String?
        /// Set when something is still running: the panel offers to open Monitor on the program,
        /// where Force Stop lives. The panel itself forces nothing.
        public let monitorLink: String?
    }

    /// Sends what the person confirmed.
    public static func confirm(_ pending: MemoryStop.Pending, group: String) async -> Done {
        let report = await pending.run()
        let link = report.force == nil ? nil : MemoryStop.monitorLink(forGroup: group)
        let ended = report.message.hasSuffix("stopped.")
        return Done(message: ended ? nil : report.message, monitorLink: link)
    }
}

extension CensusGroup {
    /// Test support: an app group built from one stand-in process the probe started, so the panel's Quit can be
    /// judged without quitting a real app. The real census only builds app groups from running applications.
    @_spi(TestSupport) public static func standInApp(name: String, root: ProcessIdentity) -> CensusGroup? {
        guard let lead = LiveStats.process(pid: root.pid) else { return nil }
        return CensusGroup(id: "stand-in:\(name)", name: name, category: .apps, role: nil, lead: lead, members: [lead],
                           parts: [], quit: .app([root]), programs: [], hostedSessions: [:])
    }
}
