import Foundation

// Sends the anonymous totals behind the devduster.com counter and world map:
// a random install id, the platform, the app version and the lifetime bytes freed. Nothing else.
public actor StatsReporter {
    public typealias Transport = @Sendable (URLRequest) async throws -> Int

    public static let endpoint = URL(string: "https://devduster.com/api/report.php")!
    public static let platform = "mac"

    private let settings: DusterSettings
    private let version: String
    private let transport: Transport

    public init(settings: DusterSettings = DusterSettings(), version: String, transport: @escaping Transport = StatsReporter.urlSession) {
        self.settings = settings
        self.version = version
        self.transport = transport
    }

    public static let urlSession: Transport = { request in
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    public func enable() {
        settings.shareStatsAsked = true
        settings.shareStats = true
    }

    // Turning sharing off forgets the install id; the server entry is deleted on the next sync.
    public func disable() {
        settings.shareStatsAsked = true
        if let id = settings.statsInstallID {
            settings.statsPendingRemovalID = id
        }
        settings.shareStats = false
        settings.statsInstallID = nil
        settings.statsLastSentBytes = nil
    }

    // Removes a pending entry, then reports the lifetime total if sharing is on and it changed.
    // Syncs run one after another, so a removal never overtakes a report still in flight.
    public func sync(lifetimeBytes: @escaping @Sendable () async -> Int64) async {
        let previous = tail
        let task = Task {
            await previous?.value
            await self.runSync(lifetimeBytes: lifetimeBytes)
        }
        tail = task
        await task.value
    }

    private var tail: Task<Void, Never>?

    private func runSync(lifetimeBytes: @Sendable () async -> Int64) async {
        if let removal = settings.statsPendingRemovalID {
            guard await post(RemoveBody(id: removal, remove: true)) else { return }
            settings.statsPendingRemovalID = nil
        }
        // On by default, but nothing is sent before the one-time notice has been shown.
        guard settings.shareStats, settings.shareStatsAsked else { return }
        let bytes = max(await lifetimeBytes(), 0)
        if settings.statsInstallID != nil, settings.statsLastSentBytes == bytes { return }
        let id = settings.statsInstallID ?? UUID().uuidString.lowercased()
        settings.statsInstallID = id
        guard await post(ReportBody(id: id, platform: Self.platform, version: version, freed: bytes)),
              settings.statsInstallID == id else { return }
        settings.statsLastSentBytes = bytes
    }

    private func post(_ body: some Encodable) async -> Bool {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DevDuster/\(version)", forHTTPHeaderField: "User-Agent")
        guard let data = try? JSONEncoder().encode(body) else { return false }
        request.httpBody = data
        guard let status = try? await transport(request) else { return false }
        return (200..<300).contains(status)
    }

    private struct ReportBody: Encodable {
        let id: String
        let platform: String
        let version: String
        let freed: Int64
    }

    private struct RemoveBody: Encodable {
        let id: String
        let remove: Bool
    }
}
