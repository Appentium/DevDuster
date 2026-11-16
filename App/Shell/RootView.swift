import AppKit
import SwiftUI

struct RootView: View {
    @Binding var selection: SidebarSection?
    let cleanerModel: CleanerModel
    let volumeMonitor: VolumeMonitorModel
    @State private var fdaModel = FullDiskAccessModel()
    @State private var dashboardModel = DashboardModel()
    @State private var uninstallerModel = UninstallerModel()
    @State private var developerJunkModel = CleanerModel(grouping: .platform)
    @State private var flutterModel = FlutterProjectsModel()
    @State private var diskMapModel = DiskMapModel()
    @State private var largeFilesModel = LargeFilesModel()
    @State private var systemModel = SystemModel()

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
            volumeMonitor.start()
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
        case .uninstaller:
            UninstallerView(model: uninstallerModel)
        case .developerJunk:
            CleanerView(model: developerJunkModel)
        case .flutterProjects:
            FlutterProjectsView(model: flutterModel)
        case .diskMap:
            DiskMapView(model: diskMapModel)
        case .largeFiles:
            LargeFilesView(model: largeFilesModel)
        case .system:
            SystemView(model: systemModel)
        case nil:
            ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
        }
    }
}
