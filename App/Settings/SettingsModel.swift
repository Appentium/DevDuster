import Foundation
import Observation
import DusterCore

@MainActor
@Observable
final class SettingsModel {
    private let settings = DusterSettings()
    private let cliURL = Bundle.main.bundleURL.appending(path: "Contents/MacOS/duster")
    private var scheduleTask: Task<Void, Never>?

    private(set) var scheduleError: String?

    var staleDays: Int { didSet { settings.staleDays = staleDays } }
    var excludedPaths: [String] { didSet { settings.excludedPaths = excludedPaths } }
    var menuBarEnabled: Bool { didSet { settings.menuBarEnabled = menuBarEnabled } }
    var lowSpaceAlertsEnabled: Bool { didSet { settings.lowSpaceAlertsEnabled = lowSpaceAlertsEnabled } }
    var internalThresholdGB: Int { didSet { settings.internalThresholdGB = internalThresholdGB } }
    var externalThresholdGB: Int { didSet { settings.externalThresholdGB = externalThresholdGB } }
    var scheduledCleanEnabled: Bool { didSet { updateSchedule { $0.scheduledCleanEnabled = scheduledCleanEnabled } } }
    var scheduleFrequency: CleanSchedule.Frequency { didSet { updateSchedule { $0.schedule.frequency = scheduleFrequency } } }
    var scheduleWeekday: Int { didSet { updateSchedule { $0.schedule.weekday = scheduleWeekday } } }
    var scheduleHour: Int { didSet { updateSchedule { $0.schedule.hour = scheduleHour } } }
    var scheduledCleanMovesToTrash: Bool { didSet { updateSchedule { $0.scheduledCleanMovesToTrash = scheduledCleanMovesToTrash } } }

    init() {
        staleDays = settings.staleDays
        excludedPaths = settings.excludedPaths
        menuBarEnabled = settings.menuBarEnabled
        lowSpaceAlertsEnabled = settings.lowSpaceAlertsEnabled
        internalThresholdGB = settings.internalThresholdGB
        externalThresholdGB = settings.externalThresholdGB
        scheduledCleanEnabled = settings.scheduledCleanEnabled
        scheduleFrequency = settings.schedule.frequency
        scheduleWeekday = settings.schedule.weekday
        scheduleHour = settings.schedule.hour
        scheduledCleanMovesToTrash = settings.scheduledCleanMovesToTrash
    }

    func addExcludedFolders(_ urls: [URL]) {
        let added = urls.map { $0.path(percentEncoded: false) }.filter { !excludedPaths.contains($0) }
        excludedPaths += added
    }

    func removeExcludedPath(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }

    private func updateSchedule(_ change: (DusterSettings) -> Void) {
        change(settings)
        applySchedule()
    }

    func applySchedule() {
        let settings = settings
        let cliURL = cliURL
        let previous = scheduleTask
        scheduleTask = Task {
            await previous?.value
            do {
                try await Task.detached { try ScheduleInstaller().apply(settings, cli: cliURL) }.value
                scheduleError = nil
            } catch {
                scheduleError = error.localizedDescription
            }
        }
    }
}
