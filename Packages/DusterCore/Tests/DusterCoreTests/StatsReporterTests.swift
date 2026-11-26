import Foundation
import Testing
@testable import DusterCore

private actor FakeServer {
    private var bodies: [[String: Any]] = []
    var status = 204
    var offline = false

    func set(status: Int, offline: Bool = false) {
        self.status = status
        self.offline = offline
    }

    func handle(_ request: URLRequest) throws -> Int {
        if offline { throw URLError(.notConnectedToInternet) }
        #expect(request.httpMethod == "POST")
        #expect(request.url == StatsReporter.endpoint)
        let object = try JSONSerialization.jsonObject(with: request.httpBody ?? Data())
        bodies.append(object as? [String: Any] ?? [:])
        return status
    }

    func count() -> Int { bodies.count }
    func string(_ index: Int, _ key: String) -> String? { bodies[index][key] as? String }
    func int(_ index: Int, _ key: String) -> Int64? { (bodies[index][key] as? NSNumber)?.int64Value }
    func bool(_ index: Int, _ key: String) -> Bool? { (bodies[index][key] as? NSNumber)?.boolValue }
    func keys(_ index: Int) -> [String] { bodies[index].keys.sorted() }
}

@Suite final class StatsReporterTests {
    private let suiteName = Fixture.defaultsSuite()
    private let server = FakeServer()

    deinit {
        Fixture.removeDefaultsSuite(suiteName)
    }

    private func make() -> (StatsReporter, DusterSettings) {
        let settings = DusterSettings(suiteName: suiteName)
        let server = server
        return (StatsReporter(settings: settings, version: "1.2.3") { try await server.handle($0) }, settings)
    }

    @Test func sharesByDefaultOnlyAfterTheNotice() async {
        let (reporter, settings) = make()
        #expect(settings.shareStats)
        await reporter.sync { 500 }
        #expect(await server.count() == 0)
        settings.shareStatsAsked = true
        await reporter.sync { 500 }
        #expect(await server.count() == 1)
    }

    @Test func sendsNothingAfterTurningOff() async {
        let (reporter, settings) = make()
        await reporter.disable()
        await reporter.sync { 500 }
        #expect(await server.count() == 0)
        #expect(settings.statsInstallID == nil)
    }

    @Test func reportsOnlyTheAllowedFields() async throws {
        let (reporter, settings) = make()
        await reporter.enable()
        await reporter.sync { 500 }

        #expect(await server.count() == 1)
        #expect(await server.keys(0) == ["freed", "id", "platform", "version"])
        let id = try #require(settings.statsInstallID)
        #expect(UUID(uuidString: id) != nil)
        #expect(await server.string(0, "id") == id)
        #expect(await server.string(0, "platform") == "mac")
        #expect(await server.string(0, "version") == "1.2.3")
        #expect(await server.int(0, "freed") == 500)
        #expect(settings.shareStatsAsked)
    }

    @Test func skipsWhenTheTotalHasNotChanged() async {
        let (reporter, settings) = make()
        await reporter.enable()
        await reporter.sync { 500 }
        await reporter.sync { 500 }
        await reporter.sync { 900 }

        #expect(await server.count() == 2)
        #expect(await server.int(1, "freed") == 900)
        #expect(await server.string(0, "id") == server.string(1, "id"))
        #expect(settings.statsLastSentBytes == 900)
    }

    @Test func retriesAfterAFailedSend() async {
        let (reporter, settings) = make()
        await reporter.enable()
        await server.set(status: 204, offline: true)
        await reporter.sync { 500 }
        #expect(settings.statsLastSentBytes == nil)

        await server.set(status: 500)
        await reporter.sync { 500 }
        #expect(settings.statsLastSentBytes == nil)

        await server.set(status: 204)
        await reporter.sync { 500 }
        #expect(settings.statsLastSentBytes == 500)
    }

    @Test func disablingDeletesTheServerEntryAndForgetsTheID() async {
        let (reporter, settings) = make()
        await reporter.enable()
        await reporter.sync { 500 }
        let id = settings.statsInstallID

        await reporter.disable()
        #expect(settings.statsInstallID == nil)
        #expect(settings.statsPendingRemovalID == id)

        await server.set(status: 204, offline: true)
        await reporter.sync { 500 }
        #expect(settings.statsPendingRemovalID == id)

        await server.set(status: 204)
        await reporter.sync { 500 }
        #expect(await server.count() == 2)
        #expect(await server.string(1, "id") == id)
        #expect(await server.bool(1, "remove") == true)
        #expect(settings.statsPendingRemovalID == nil)
    }

    @Test func reEnablingUsesAFreshID() async {
        let (reporter, settings) = make()
        await reporter.enable()
        await reporter.sync { 500 }
        let first = settings.statsInstallID
        await reporter.disable()
        await reporter.enable()
        await reporter.sync { 500 }

        #expect(await server.bool(1, "remove") == true)
        #expect(await server.string(1, "id") == first)
        #expect(await server.string(2, "id") != first)
    }
}
