import Foundation

/// What each state of a development channel says to a person, in full sentences: the Updates screen shows
/// them and `agent-runner --probe-channels` prints them, so what is proved is what is read.
extension ChannelState {

    /// The line under the channel's rows.
    public func sentence(for channel: UpdateChannel, facts: CloneFacts? = nil) -> String {
        switch self {
        case .unavailable(let reason), .differs(let reason), .ahead(let reason), .unknown(let reason):
            return reason
        case .upToDate:
            return channel == .beta ? "You have the newest beta." : "This copy matches your clone."
        case .behind(let changes, let uncommitted):
            switch channel {
            case .beta:
                guard let changes else { return "This copy doesn't record where it was built from, so the newest beta is offered once to start the record." }
                return changes == 1 ? "There is 1 newer change on the development branch." : "There are \(changes) newer changes on the development branch."
            default:
                guard let changes else {
                    return "This copy doesn't record where it was built from. Rebuilding from your clone starts the record."
                }
                var parts: [String] = []
                if changes > 0 { parts.append(changes == 1 ? "1 commit that is not in this copy" : "\(changes) commits that are not in this copy") }
                if uncommitted { parts.append("changes that are not committed yet") }
                let named = parts.joined(separator: ", and ")
                return named.isEmpty ? "Your clone has changes that are not in this copy." : "Your clone has \(named)."
            }
        }
    }

}
