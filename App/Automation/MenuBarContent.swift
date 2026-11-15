import SweepCore
import SwiftUI

struct MenuBarLabel: View {
    let model: VolumeMonitorModel

    var body: some View {
        Label(
            model.fullestVolume.map { ByteFormatter.string($0.availableBytes) } ?? "Sweep",
            systemImage: "internaldrive"
        )
        .task { model.start() }
    }
}

struct MenuBarContent: View {
    let model: VolumeMonitorModel
    let onOpen: () -> Void
    let onScan: () -> Void

    var body: some View {
        ForEach(model.volumes) { volume in
            Text("\(volume.name): \(ByteFormatter.string(volume.availableBytes)) free of \(ByteFormatter.string(volume.totalBytes))")
        }
        Divider()
        Button("Open Sweep", action: onOpen)
        Button("Scan Now", action: onScan)
        Divider()
        Button("Quit Sweep") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
