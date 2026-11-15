import SwiftUI

struct FullDiskAccessSheet: View {
    let model: FullDiskAccessModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access Required")
                        .font(.title3.bold())
                    Text("Sweep needs Full Disk Access to scan and clean protected caches, logs, and trash across your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How to enable:")
                    .font(.subheadline.weight(.semibold))
                Text("1. Click Open System Settings below.")
                Text("2. Turn on Sweep in Privacy & Security → Full Disk Access.")
                Text("3. Return to Sweep — access is checked automatically.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Continue Without Access") {
                    model.dismissForSession()
                }
                Spacer()
                Button("Check Again") {
                    model.check()
                }
                Button("Open System Settings") {
                    model.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
