import SwiftUI

extension Route {

    /// The screen for a route. Each case hands over to the group that owns
    /// the payload; the system back button is hidden because the shell owns
    /// the one back/forward pair.
    @MainActor @ViewBuilder var destination: some View {
        Group {
            switch self {
            case .overview(let route): OverviewGroup.destination(for: route)
            case .memory(let route): MemoryGroup.destination(for: route)
            case .storage(let route): StorageGroup.destination(for: route)
            case .system(let route): SystemGroup.destination(for: route)
            case .history(let route): HistoryGroup.destination(for: route)
            case .app(let route): AppGroup.destination(for: route)
            case .run(let run): RunDetailView(route: run)
            case .job(let id): JobScreen(id: id)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
