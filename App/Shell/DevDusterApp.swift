import SwiftUI

@main
struct DevDusterApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SidebarSection? = .dashboard
    @State private var cleanerModel = CleanerModel()
    @State private var settingsModel = SettingsModel()
    @State private var volumeMonitor = VolumeMonitorModel()
    @State private var updater = UpdaterModel()

    var body: some Scene {
        Window("DevDuster", id: "main") {
            RootView(selection: $selection, cleanerModel: cleanerModel, volumeMonitor: volumeMonitor)
                .frame(minWidth: 820, minHeight: 540)
                .task { settingsModel.applySchedule() }
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra(isInserted: $settingsModel.menuBarEnabled) {
            MenuBarContent(model: volumeMonitor, onOpen: openMainWindow, onScan: scanNow)
        } label: {
            MenuBarLabel(model: volumeMonitor)
        }

        Settings {
            SettingsView(model: settingsModel)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }

    private func scanNow() {
        selection = .cleaner
        cleanerModel.startScan()
        openMainWindow()
    }
}
