import SwiftUI

@main
struct SweepApp: App {
    var body: some Scene {
        Window("Sweep", id: "main") {
            RootView()
                .frame(minWidth: 820, minHeight: 540)
        }
        .defaultSize(width: 980, height: 660)
    }
}
