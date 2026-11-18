import Foundation
import Testing
@testable import DusterCore

@Suite struct ScanItemTests {
    private func derivedData(_ fixture: Fixture, workspacePath: String?) throws -> ScanItem {
        let folder = try fixture.directory("home/Library/Developer/Xcode/DerivedData/Runner-abc")
        if let workspacePath {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspacePath], format: .xml, options: 0)
            try plist.write(to: folder.appending(path: "info.plist"))
        }
        return ScanItem(rule: try fixture.rule("xcode.derived-data"), url: folder, bytes: 0)
    }

    @Test(arguments: [
        ("/Projects/gardeniac/ios/Runner.xcworkspace", "gardeniac"),
        ("/Projects/expenseum_app/macos/Runner.xcworkspace", "expenseum_app"),
        ("/Projects/DevDuster/DevDuster.xcodeproj", "DevDuster"),
        ("/Projects/Other/Runner.xcworkspace", "Runner"),
    ])
    func derivedDataIsNamedAfterItsProject(workspacePath: String, name: String) throws {
        let item = try derivedData(Fixture(), workspacePath: workspacePath)
        #expect(item.workspace?.filePath == workspacePath)
        #expect(item.projectName == name)
    }

    @Test func derivedDataWithoutInfoPlistHasNoProject() throws {
        let item = try derivedData(Fixture(), workspacePath: nil)
        #expect(item.workspace == nil)
        #expect(item.projectName == nil)
    }
}
