import Foundation

extension MemoryCensus {
    /// Which helpers outside any app bundle are grouped with an app by bundle identifier right now
    /// (`io.tailscale.ipn.macsys.network-extension` with Tailscale). For the probe, which prints them.
    @_spi(TestSupport)
    public static func helpersJoinedToApps() -> [(helper: String, app: String)] {
        let builder = CensusBuilder()
        return builder.table.values.compactMap { entry in
            builder.appOwningHelper(entry).map { ((entry.path as NSString).lastPathComponent, $0) }
        }
        .sorted { ($0.app, $0.helper) < ($1.app, $1.helper) }
    }
}
