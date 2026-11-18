import Foundation
import Testing
@testable import DusterCore

@Suite final class DusterSettingsTests {
    private let suiteName = Fixture.defaultsSuite()

    deinit {
        Fixture.removeDefaultsSuite(suiteName)
    }

    private func settings() -> DusterSettings {
        DusterSettings(suiteName: suiteName)
    }

    @Test func defaultsMatchTheSpec() {
        let settings = settings()
        #expect(settings.staleDays == 14)
        #expect(settings.excludedPaths.isEmpty)
        #expect(settings.menuBarEnabled)
        #expect(settings.lowSpaceAlertsEnabled)
        #expect(settings.lowSpaceThresholds == LowSpaceThresholds(internalGB: 20, externalGB: 10))
        #expect(!settings.scheduledCleanEnabled)
        #expect(settings.schedule == CleanSchedule(frequency: .daily, weekday: 2, hour: 3))
        #expect(settings.scheduledCleanMovesToTrash)
    }

    @Test func valuesPersistAcrossInstancesOfTheSameSuite() {
        let first = settings()
        first.staleDays = 30
        first.menuBarEnabled = false
        first.excludedPaths = ["/Volumes/Work"]
        first.schedule = CleanSchedule(frequency: .weekly, weekday: 6, hour: 22)
        first.scheduledCleanMovesToTrash = false

        let second = settings()
        #expect(second.staleDays == 30)
        #expect(!second.menuBarEnabled)
        #expect(second.excludedPaths == ["/Volumes/Work"])
        #expect(second.schedule == CleanSchedule(frequency: .weekly, weekday: 6, hour: 22))
        #expect(!second.scheduledCleanMovesToTrash)
    }

    @Test func scanOptionsCarryStaleDaysExclusionsTiersAndScope() {
        let settings = settings()
        settings.staleDays = 45
        settings.excludedPaths = ["/Volumes/Work", "/Users/me/keep"]
        let scope = [URL(filePath: "/Users/me")]
        let options = settings.scanOptions(tiers: [.safe], scope: scope)

        #expect(options.staleDays == 45)
        #expect(options.excludedPaths == [URL(filePath: "/Volumes/Work"), URL(filePath: "/Users/me/keep")])
        #expect(options.tiers == [.safe])
        #expect(options.scope == scope)
        #expect(settings.scanOptions().tiers == Set(Tier.allCases))
    }

    @Test func outOfRangeValuesAreClamped() {
        let settings = settings()
        settings.staleDays = 0
        settings.internalThresholdGB = -5
        #expect(settings.staleDays == 1)
        #expect(settings.internalThresholdGB == 1)
        #expect(CleanSchedule(frequency: .weekly, weekday: 9, hour: 40) == CleanSchedule(frequency: .weekly, weekday: 7, hour: 23))
    }
}
