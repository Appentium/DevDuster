import DusterCore
import SwiftUI

struct MenuBarLabel: View {
    let model: VolumeMonitorModel

    var body: some View {
        Label(
            model.fullestVolume.map { ByteFormatter.string($0.availableBytes) } ?? "DevDuster",
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
        Button("Open DevDuster", action: onOpen)
        Button("Scan Now", action: onScan)
        Divider()
        Button("Quit DevDuster") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
