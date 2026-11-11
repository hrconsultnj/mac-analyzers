import SwiftUI

extension Route {

    /// The screen for a route. Each case hands over to the group that owns
    /// the payload; the system back button is hidden because the shell owns
    /// the one back/forward pair.
    @MainActor @ViewBuilder var destination: some View {
        StackDepthReader(route: self) { content }
    }

    @MainActor @ViewBuilder private var content: some View {
        Group {
            switch self {
            case .overview(let route): OverviewGroup.destination(for: route)
            case .memory(let route): MemoryGroup.destination(for: route)
            case .storage(let route): StorageGroup.destination(for: route)
            case .system(let route): SystemGroup.destination(for: route)
            case .history(let route): HistoryGroup.destination(for: route)
            case .app(let route): AppGroup.destination(for: route)
            case .run(let run): RunScreen(reference: run)
            case .job(let id): JobScreen(id: id)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

/// Tells the screen how deep in its stack it is, so tab commands come only from the top one.
private struct StackDepthReader<Content: View>: View {
    let route: Route
    @ViewBuilder let content: Content
    @Environment(Navigator.self) private var navigator

    var body: some View {
        content.environment(\.stackDepth, (navigator.path.lastIndex(of: route) ?? -1) + 1)
    }
}
