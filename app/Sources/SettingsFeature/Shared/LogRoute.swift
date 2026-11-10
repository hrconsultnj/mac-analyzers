import AnalyzersKit
import Foundation

/// Push target: a run inside a specific log (the kind carries icon/colors).
struct RunRoute: Hashable {
    let kind: LogKind
    let run: LogRun
}

/// ONE typed route for everything pushable in the logs world — a typed path
/// array ([LogRoute]) instead of an opaque NavigationPath is what lets the
/// shell snapshot and restore navigation for browser-style back/forward.
enum LogRoute: Hashable {
    case log(LogKind)
    case run(RunRoute)
    case forensics(ForensicsRoute)
}
