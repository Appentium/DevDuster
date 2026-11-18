import Foundation
import Testing
@testable import DusterCore

@Suite struct SimulatorsTests {
    @Test func keepsTheNewestRuntimePerPlatform() {
        let runtimes = [
            runtime("ios-17", platform: "iphonesimulator", version: "17.5"),
            runtime("ios-18", platform: "iphonesimulator", version: "18.2"),
            runtime("ios-27", platform: "iphonesimulator", version: "27.2"),
            runtime("ios-27-device", platform: "iphonesimulator", version: "27.2"),
            runtime("watch-11", platform: "watchsimulator", version: "11.0"),
            runtime("ios-16-locked", platform: "iphonesimulator", version: "16.4", deletable: false),
        ]

        let old = Simulators.olderThanNewest(runtimes).map(\.identifier)
        #expect(Set(old) == ["ios-17", "ios-18"])
    }

    private func runtime(_ identifier: String, platform: String, version: String, deletable: Bool = true) -> Simulators.Runtime {
        Simulators.Runtime(
            identifier: identifier, platformIdentifier: platform, version: version,
            runtimeBundlePath: "/runtimes/\(identifier).simruntime", sizeBytes: 1_000, deletable: deletable
        )
    }
}
