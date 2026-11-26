import DusterCore
import Foundation

// The opt-in anonymous totals behind the devduster.com counter. Every call is a no-op while sharing is off,
// apart from deleting the server entry once after the user turns it off.
enum StatsSharing {
    static let privacyURL = URL(string: "https://devduster.com/privacy.html#stats")!

    static let reporter = StatsReporter(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    )

    static func sync() {
        Task.detached(priority: .utility) {
            await reporter.sync {
                let home = FileManager.default.homeDirectoryForCurrentUser
                return CleanHistory(logs: [
                    CleanLog(home: home),
                    CleanLog(url: URL(filePath: "/Library/Logs/DevDuster/helper.log")),
                ]).totalBytes
            }
        }
    }

    static func setSharing(_ isOn: Bool) {
        Task.detached(priority: .utility) {
            if isOn {
                await reporter.enable()
            } else {
                await reporter.disable()
            }
            sync()
        }
    }

    static func decline() {
        DusterSettings().shareStatsAsked = true
    }
}
