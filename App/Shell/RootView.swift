import AppKit
import SwiftUI

struct RootView: View {
    @State private var selection: SidebarSection? = .dashboard
    @State private var fdaModel = FullDiskAccessModel()
    @State private var dashboardModel = DashboardModel()
    @State private var cleanerModel = CleanerModel()
    @State private var flutterModel = FlutterProjectsModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detailView
        }
        .task {
            fdaModel.check()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fdaModel.check()
        }
        .sheet(isPresented: $fdaModel.isSheetPresented) {
            FullDiskAccessSheet(model: fdaModel)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView(model: dashboardModel) {
                selection = .cleaner
                cleanerModel.startScan()
            }
        case .cleaner:
            CleanerView(model: cleanerModel)
        case .flutterProjects:
            FlutterProjectsView(model: flutterModel)
        case nil:
            ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
        }
    }
}
