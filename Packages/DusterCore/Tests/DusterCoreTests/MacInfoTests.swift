import Testing
@testable import DusterCore

@Suite struct MacInfoTests {
    @Test func describesThisMac() {
        let info = MacInfo.current()
        #expect(info.memoryBytes > 0)
        #expect(info.coreCount > 0)
        #expect(!info.chip.isEmpty)
        #expect(info.osVersion.hasPrefix("macOS "))
    }
}
