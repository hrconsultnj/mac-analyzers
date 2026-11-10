import SwiftUI

extension Route {

    /// The screen for a route. Each case hands over to the group that owns
    /// the payload; the system back button is hidden because the shell owns
    /// the one back/forward pair.
    @MainActor @ViewBuilder var destination: some View {
        Group {
            switch self {
            case .memory(let route): MemoryGroup.destination(for: route)
            case .storage(let route): StorageGroup.destination(for: route)
            case .system(let route): SystemGroup.destination(for: route)
            case .history(let route): HistoryGroup.destination(for: route)
            case .app(let route): AppGroup.destination(for: route)
            case .job(let id): JobPlaceholderView(id: id)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

/// Stand-in for a job's screen until Activity exists.
private struct JobPlaceholderView: View {
    let id: UUID

    var body: some View {
        ContentUnavailableView("Job details are coming",
                               systemImage: "clock.arrow.circlepath",
                               description: Text("Tracked jobs open here once Activity is available."))
            .navigationTitle("Job")
    }
}
