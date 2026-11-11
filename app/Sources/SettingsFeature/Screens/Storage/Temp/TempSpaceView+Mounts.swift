import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Mounted disk images, told apart from real disk use, with Eject.
extension TempSpaceView {

    // MARK: - mounted disk images

    @ViewBuilder func mountsSection(_ run: TempCleanRun) -> some View {
        Section {
            ForEach(run.mounts) { mount in
                mountRow(mount)
            }
        } header: {
            Text("Mounted Disk Images")
        } footer: {
            Text("Their contents are not on your disk. A file that backs an image can't free space until the image is ejected — clearing it in Actions ejects it first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mountRow(_ mount: TempMount) -> some View {
        let badge: (String, Color) = switch mount.status {
        case .mounted: mount.imageLivesInTemp ? ("Image in Temp", .orange) : ("Mounted", .purple)
        case .ejected: ("Ejected", .green)
        case .ejectFailed: ("Eject Failed", .red)
        }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                DataCard(symbol: "opticaldiscdrive", color: .purple,
                         title: (mount.mountPoint as NSString).lastPathComponent,
                         subtitle: "from \(mount.imagePath)",
                         trailing: ByteSize.format(mount.sizeBytes), badge: badge)
                    .help(mount.mountPoint)
                if mount.status == .mounted {
                    Button("Eject…") { ejecting = mount }
                        .controlSize(.small)
                        .disabled(isBusy)
                }
                if FileManager.default.fileExists(atPath: mount.imagePath) {
                    revealButton(mount.imagePath, help: "Show the image file in Finder")
                }
            }
            if !mount.alsoEjects.isEmpty {
                Text("Also ejects: " + mount.alsoEjects.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(mount.details.filter { !$0.contains("lives in temp") && !$0.hasPrefix("ejecting it also") },
                    id: \.self) { detail in
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
