import DusterCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(model: model)
            }
            Tab("Automation", systemImage: "clock.arrow.2.circlepath") {
                AutomationSettingsView(model: model)
            }
        }
        .frame(width: 520, height: 460)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var isChoosingFolder = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $model.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Stepper("Stale after \(model.staleDays) days", value: $model.staleDays, in: 1...365)
            } footer: {
                Text("Project build folders are offered for cleaning once the project has had no activity for this long.")
            }

            Section("Excluded Paths") {
                if model.excludedPaths.isEmpty {
                    Text("Nothing is excluded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.excludedPaths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { model.removeExcludedPath(path) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { isChoosingFolder = true }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addExcludedFolders(urls) }
        }
    }
}

private struct AutomationSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show free space in the menu bar", isOn: $model.menuBarEnabled)
            }

            Section("Low Space Alerts") {
                Toggle("Notify when a volume runs low", isOn: $model.lowSpaceAlertsEnabled)
                Stepper("Internal volumes below \(model.internalThresholdGB) GB", value: $model.internalThresholdGB, in: 1...500)
                    .disabled(!model.lowSpaceAlertsEnabled)
                Stepper("External volumes below \(model.externalThresholdGB) GB", value: $model.externalThresholdGB, in: 1...500)
                    .disabled(!model.lowSpaceAlertsEnabled)
            }

            Section {
                Toggle("Clean the Safe tier on a schedule", isOn: $model.scheduledCleanEnabled)
                Picker("Repeat", selection: $model.scheduleFrequency) {
                    Text("Daily").tag(CleanSchedule.Frequency.daily)
                    Text("Weekly").tag(CleanSchedule.Frequency.weekly)
                }
                .disabled(!model.scheduledCleanEnabled)
                if model.scheduleFrequency == .weekly {
                    Picker("Day", selection: $model.scheduleWeekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                    .disabled(!model.scheduledCleanEnabled)
                }
                Picker("Time", selection: $model.scheduleHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .disabled(!model.scheduledCleanEnabled)
                Toggle("Move to Trash", isOn: $model.scheduledCleanMovesToTrash)
                    .disabled(!model.scheduledCleanEnabled)
                Text("Trashed items only free space once that volume's Trash is emptied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = model.scheduleError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Scheduled Clean")
            }
        }
        .formStyle(.grouped)
    }
}
