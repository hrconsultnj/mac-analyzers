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
    let upgraded = base { i in
        i.state = SetupState(seenVersion: WelcomePlanner.baseline)
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
        case "upgraded": print("upgraded: \(describe(plan(upgraded)))")
        case "continuing": print("continuing: \(describe(WelcomePlanner.continuePlan(upgraded)))")
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
    check("not even for a new install, as far as the key is concerned", WelcomePlanner.neverOpenKey == "welcome.neverOpen")
    // 2. an update adds steps: only the new, unsatisfied ones, and "Done"
    let update = plan(upgraded)
    check("an update shows only what is new and not yet satisfied (the guard preview, Full Disk Access) and Done",
          update?.reason == .newInThisVersion && ids(update) == [.guardPreview, .fullDiskAccess, .done], describe(update))
    check("an update's flow is titled New in This Version", update?.title == "New in This Version")
    check("a step already satisfied (background, notifications) is not shown again after an update",
          !ids(update).contains(.background) && !ids(update).contains(.notifications) && !ids(update).contains(.welcome))
    check("the optional Time Machine step never turns up after an update", !ids(update).contains(.timeMachine))
    // 3. nothing new: the flow does not come back on its own
    check("everything satisfied or answered: nothing new", plan(base { i in
        i.state = SetupState(seenVersion: WelcomePlanner.baseline, answers: ["guardPreview": .done])
        i.configExists = true; i.anyJobLoaded = true
        i.satisfied.formUnion([.background, .notifications, .timeMachine, .fullDiskAccess, .guardPreview])
    }) == nil)
    check("a step the person answered, even skipped, is not put in front of them again on its own", !ids(plan(base { i in
        i.state = SetupState(seenVersion: WelcomePlanner.baseline, answers: ["fullDiskAccess": .skipped])
        i.configExists = true; i.anyJobLoaded = true
        i.satisfied.formUnion([.background, .notifications, .timeMachine])
    })).contains(.fullDiskAccess))
    check("a finished flow never reappears by itself", plan(lostFDA) == nil)
    check("a permission lost after an update is Setup's to show, not the flow's (same version, Full Disk Access off)",
          plan(base { i in i.state = SetupState(seenVersion: "2.72.0"); i.configExists = true; i.anyJobLoaded = true }) == nil)
    check("an install with no record that is already set up (settings or jobs) is an update, not a new install",
          plan(base { i in i.configExists = true })?.reason == .newInThisVersion && !WelcomePlanner.isFreshInstall(base { i in i.configExists = true }))
    // 4. a step added by a later version: shown when unsatisfied, not when satisfied
    let later = [WelcomeSpec(step: .welcome, introducedIn: "2.72.0"), WelcomeSpec(step: .fullDiskAccess, introducedIn: "9.0.0"),
                 WelcomeSpec(step: .notifications, introducedIn: "9.0.0"), WelcomeSpec(step: .done, introducedIn: "2.72.0")]
    let seen272 = base { i in
        i.state = SetupState(seenVersion: "2.72.0"); i.configExists = true; i.anyJobLoaded = true; i.specs = later
        i.satisfied.formUnion([.notifications])
    }
    check("a new step from a later version is shown when it is not satisfied, and a satisfied one is not",
          ids(plan(seen272)) == [.fullDiskAccess, .done], describe(plan(seen272)))
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
          ids(plan(freshWelcome)) == WelcomeStep.allCases && ids(plan(upgradedWelcome)) == [.guardPreview, .fullDiskAccess, .done]
          && ids(WelcomePlanner.continuePlan(continuingWelcome)) == [.fullDiskAccess, .done],
          "\(describe(plan(freshWelcome))) | \(describe(plan(upgradedWelcome))) | \(describe(WelcomePlanner.continuePlan(continuingWelcome)))")
    // 7. what the flow saves, and the key the What's New card reads
    let folder = ProbeScratch.folder("ma-probe-onboarding")
    let file = folder.appending(path: "setup-state.json")
    check("no record yet: nothing read", SetupState.load(at: file) == nil && !SetupState.exists(at: file))
    var state = SetupState(seenVersion: "2.72.0")
    state.record(.notifications, .done); state.record(.fullDiskAccess, .skipped); state.finished = true
    check("what was answered is saved and read back", state.save(to: file) && SetupState.load(at: file) == state)
    try? "not json".write(to: file, atomically: true, encoding: .utf8)
    check("a damaged record is no record", SetupState.load(at: file) == nil)
    let defaults = UserDefaults(suiteName: "ma-probe-onboarding-\(UUID().uuidString)")!
    check("a new install is taken to have seen the version it came with (What's New's key is set once)",
          WelcomePlanner.markWhatsNewSeen(version: "2.72.0", defaults: defaults) && defaults.string(forKey: "whatsNew.seenVersion") == "2.72.0"
          && !WelcomePlanner.markWhatsNewSeen(version: "2.73.0", defaults: defaults) && defaults.string(forKey: "whatsNew.seenVersion") == "2.72.0")

    print(failures == 0 ? "\nPASS  every check holds" : "\n\(failures) checks FAILED")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
