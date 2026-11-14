import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-onboarding [--state fresh|upgraded|continuing|lostFDA]`: when the Welcome flow appears on its own and
// with which steps, judged on example states (exit 1 when a rule breaks). With `--state` it prints that one state's plan.
// It reads nothing of this Mac and writes only to a scratch folder.

private func describe(_ plan: WelcomePlan?) -> String {
    guard let plan else { return "does not appear" }
    return "\(plan.title): \(plan.steps.map(\.rawValue).joined(separator: ", ")) (opens on \(plan.steps[plan.start].rawValue))"
}

func probeOnboarding(state: String?) -> Never {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }
    func plan(_ i: WelcomeInputs) -> WelcomePlan? { WelcomePlanner.autoPlan(i) }
    func base(_ mutate: (inout WelcomeInputs) -> Void = { _ in }) -> WelcomeInputs {
        var i = WelcomeInputs()
        i.version = "2.72.0"
        i.hasTimeMachine = true
        i.satisfied = [.welcome, .done]
        mutate(&i)
        return i
    }
    func ids(_ plan: WelcomePlan?) -> [WelcomeStep] { plan?.steps ?? [] }

    // the states a person can be in
    let fresh = base()
    // an install that already had Setup (2.61 and later): nothing it asks for is new
    let existing = base { i in
        i.state = nil
        i.configExists = true; i.anyJobLoaded = true
        i.satisfied.formUnion([.background, .notifications, .timeMachine, .fullDiskAccess])
    }
    let existingNoFDA = base { i in
        i.state = nil
        i.configExists = true; i.anyJobLoaded = true
        i.satisfied.formUnion([.background, .notifications, .timeMachine])
    }
    let lostFDA = base { i in
        i.state = SetupState(seenVersion: "2.72.0", answers: [:], finished: true)
        i.configExists = true; i.anyJobLoaded = true
    }
    if let state {
        switch state {
        case "fresh": print("fresh: \(describe(plan(fresh)))")
        case "existing": print("existing: \(describe(plan(existing)))")
        case "existingNoFDA": print("existingNoFDA: \(describe(plan(existingNoFDA)))")
        case "continuing": print("continuing: \(describe(WelcomePlanner.continuePlan(existingNoFDA)))")
        case "lostFDA": print("lostFDA: \(describe(plan(lostFDA)))")
        default: print("unknown state \(state)")
        }
        exit(0)
    }

    // 1. first launch: a new install gets the whole flow, in order, with Time Machine only where there is a backup disk
    let first = plan(fresh)
    check("a new install gets the whole flow, in order", first?.reason == .firstLaunch && ids(first) == WelcomeStep.allCases, describe(first))
    check("without a Time Machine disk that step is left out", ids(plan(base { $0.hasTimeMachine = false })) == WelcomeStep.allCases.filter { $0 != .timeMachine })
    check("a tool that sets the never-open key never gets the flow", plan(base { $0.neverOpen = true }) == nil)
    check("the key's name is the one the tools set", WelcomePlanner.neverOpenKey == "welcome.neverOpen")
    // 2. each step is stamped with the release that first had what it asks for
    func introduced(_ step: WelcomeStep) -> String? { WelcomeSpec.all.first { $0.step == step }?.introducedIn }
    check("Background, Notifications and Full Disk Access date from 2.61.0 (Setup), Time Machine from 2.70.0; the rest are 2.72.0",
          introduced(.background) == "2.61.0" && introduced(.notifications) == "2.61.0" && introduced(.fullDiskAccess) == "2.61.0"
          && introduced(.timeMachine) == "2.70.0" && [.welcome, .guardPreview, .done].allSatisfy { introduced($0) == "2.72.0" })
    // 3. an existing install is not re-onboarded
    check("an existing 2.71 install with nothing missing gets no window", plan(existing) == nil && WelcomePlanner.launchAction(existing) == .nothing)
    check("an existing install missing Full Disk Access gets no window either (Setup's badge says so)",
          plan(existingNoFDA) == nil && WelcomePlanner.launchAction(existingNoFDA) == .nothing)
    check("the guard preview only informs: it is never a reason to open the window after an update",
          plan(base { i in i.configExists = true; i.anyJobLoaded = true; i.satisfied.formUnion([.background, .notifications, .timeMachine, .fullDiskAccess]) }) == nil)
    check("an install with no record that is already set up (settings or jobs) is not a new install",
          !WelcomePlanner.isFreshInstall(existing) && WelcomePlanner.isFreshInstall(fresh))
    // 4. a step a later release adds that is not satisfied: shown once as New in This Version, and never takes focus at login
    let later = [WelcomeSpec(step: .welcome, introducedIn: "2.72.0"), WelcomeSpec(step: .fullDiskAccess, introducedIn: "9.0.0"),
                 WelcomeSpec(step: .notifications, introducedIn: "9.0.0"), WelcomeSpec(step: .done, introducedIn: "2.72.0")]
    let seen = base { i in
        i.state = SetupState(seenVersion: "2.72.0"); i.configExists = true; i.anyJobLoaded = true; i.specs = later
        i.satisfied.formUnion([.notifications])
    }
    let newStep = plan(seen)
    check("a genuinely new step that is not satisfied is the update's flow (and a satisfied one is not)",
          newStep?.reason == .newInThisVersion && ids(newStep) == [.fullDiskAccess, .done] && newStep?.title == "New in This Version", describe(newStep))
    check("at login that flow does not open the window: Setup is badged and waits", WelcomePlanner.launchAction(seen) == .badgeSetup)
    check("a new install at login does open the window (it is the first launch)", {
        if case .openWindow = WelcomePlanner.launchAction(fresh) { return true } else { return false }
    }())
    check("the optional Time Machine step never turns up after an update", !ids(plan(base { i in
        i.state = SetupState(seenVersion: "2.72.0"); i.configExists = true; i.anyJobLoaded = true
        i.specs = [WelcomeSpec(step: .timeMachine, introducedIn: "9.0.0"), WelcomeSpec(step: .done, introducedIn: "2.72.0")]
    })).contains(.timeMachine))
    check("a step the person answered, even skipped, is not put in front of them again on its own", plan(base { i in
        i.state = SetupState(seenVersion: "2.72.0", answers: ["fullDiskAccess": .skipped]); i.configExists = true; i.anyJobLoaded = true
        i.specs = later; i.satisfied.formUnion([.notifications])
    }) == nil)
    check("a finished flow never reappears by itself", plan(lostFDA) == nil)
    check("a permission lost after an update is Setup's to show, not the flow's (same version, Full Disk Access off)",
          plan(base { i in i.state = SetupState(seenVersion: "2.72.0"); i.configExists = true; i.anyJobLoaded = true }) == nil)
    // 5. a development build is numbered as the release before: showing the flow once must stop it coming back
    let devRelease = "2.71.0"
    let devSpecs = [WelcomeSpec(step: .welcome, introducedIn: "2.72.0"), WelcomeSpec(step: .fullDiskAccess, introducedIn: "2.72.0"), WelcomeSpec(step: .done, introducedIn: "2.72.0")]
    func dev(_ seenVersion: String) -> WelcomeInputs {
        base { i in i.state = SetupState(seenVersion: seenVersion); i.version = devRelease; i.configExists = true; i.anyJobLoaded = true; i.specs = devSpecs }
    }
    check("a dev build (release 2.71.0, a step from 2.72.0) shows the flow once", ids(plan(dev(devRelease))) == [.fullDiskAccess, .done])
    let stamped = WelcomePlanner.stampVersion(current: devRelease, specs: devSpecs)
    check("what is saved is the newer of the release and the newest step, so it cannot loop", stamped == "2.72.0", stamped)
    check("with that saved the same dev build does not show it again", plan(dev(stamped)) == nil)
    check("a normal release saves its own number", WelcomePlanner.stampVersion(current: "2.73.0", specs: devSpecs) == "2.73.0")
    check("versions compare as numbers", WelcomePlanner.isNewer("2.72.0", than: "2.9.1") && !WelcomePlanner.isNewer("2.9.1", than: "2.72.0")
          && !WelcomePlanner.isNewer("2.72.0", than: "2.72.0") && WelcomePlanner.isNewer("3.0", than: "2.99.9"))
    // 5. Continue Setup…: the open steps, from the first with no answer, else the first skipped
    let skipped = base { i in
        i.state = SetupState(seenVersion: "2.72.0", answers: ["background": .done, "guardPreview": .done, "notifications": .done, "fullDiskAccess": .skipped])
        i.configExists = true; i.anyJobLoaded = true; i.satisfied.formUnion([.background, .guardPreview, .notifications, .timeMachine])
    }
    let carry = WelcomePlanner.continuePlan(skipped)
    check("Continue Setup… carries on with a skipped step that is still not satisfied", carry?.reason == .continuing && ids(carry) == [.fullDiskAccess, .done]
          && carry?.start == 0, describe(carry))
    check("Continue Setup… is not offered when every step is satisfied", WelcomePlanner.continuePlan(base { i in
        i.satisfied = Set(WelcomeStep.allCases)
    }) == nil)
    let unanswered = base { i in
        i.state = SetupState(seenVersion: "2.72.0", answers: ["fullDiskAccess": .skipped]); i.satisfied.formUnion([.background])
    }
    check("it opens on the first step with no answer", WelcomePlanner.continuePlan(unanswered).map { $0.steps[$0.start] } == .guardPreview,
          describe(WelcomePlanner.continuePlan(unanswered)))
    // 6. the fixtures the render tool uses give the same answers
    let (_, freshWelcome) = SetupFixtures.welcome("fresh")
    let (_, upgradedWelcome) = SetupFixtures.welcome("upgraded")
    let (_, continuingWelcome) = SetupFixtures.welcome("continuing")
    check("the render fixtures: fresh is the whole flow, upgraded only what is new, continuing the open steps",
          ids(plan(freshWelcome)) == WelcomeStep.allCases && ids(plan(upgradedWelcome)) == [.fullDiskAccess, .done]
          && ids(WelcomePlanner.continuePlan(continuingWelcome)) == [.fullDiskAccess, .done],
          "\(describe(plan(freshWelcome))) | \(describe(plan(upgradedWelcome))) | \(describe(WelcomePlanner.continuePlan(continuingWelcome)))")
    // 7. what the flow saves, and the key the What's New card reads
    let folder = ProbeScratch.folder("ma-probe-onboarding")
    let file = folder.appending(path: "setup-state.json")
    check("no record yet: nothing read", SetupState.load(at: file) == nil && !SetupState.exists(at: file))
    var state = SetupState(seenVersion: "2.72.0")
    state.record(.notifications, .done); state.record(.fullDiskAccess, .skipped); state.finished = true
    check("what was answered is saved and read back", state.save(to: file) && SetupState.load(at: file) == state)
    check("Remove deletes the record (and a missing one is fine), so a reinstall is a new install",
          SetupState.remove(at: file) && !SetupState.exists(at: file) && SetupState.remove(at: file))
    // Remove, then the next launch: with the record gone (and the settings and jobs removed) it is a new install again
    state.save(to: file)
    SetupState.remove(at: file)
    let afterRemove = base { i in i.state = SetupState.load(at: file) }
    check("after Remove the next launch is a fresh install and gets the whole flow",
          WelcomePlanner.isFreshInstall(afterRemove) && WelcomePlanner.autoPlan(afterRemove)?.reason == .firstLaunch)
    try? "not json".write(to: file, atomically: true, encoding: .utf8)
    check("a damaged record is no record", SetupState.load(at: file) == nil)
    let defaults = UserDefaults(suiteName: "ma-probe-onboarding-\(UUID().uuidString)")!
    check("a new install is taken to have seen the version it came with (What's New's key is set once)",
          WelcomePlanner.markWhatsNewSeen(version: "2.72.0", defaults: defaults) && defaults.string(forKey: "whatsNew.seenVersion") == "2.72.0"
          && !WelcomePlanner.markWhatsNewSeen(version: "2.73.0", defaults: defaults) && defaults.string(forKey: "whatsNew.seenVersion") == "2.72.0")

    print(failures == 0 ? "\nPASS  every check holds" : "\n\(failures) checks FAILED")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
