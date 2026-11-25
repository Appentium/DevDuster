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
    @State private var projectsModel = ProjectsModel()
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
            DashboardView(
                model: dashboardModel,
                cleaner: cleanerModel,
                onScan: {
                    selection = .cleaner
                    cleanerModel.startScan()
                },
                onOpen: { selection = $0 }
            )
        case .cleaner:
            CleanerView(model: cleanerModel)
        case .uninstaller:
            UninstallerView(model: uninstallerModel)
        case .developerJunk:
            CleanerView(model: developerJunkModel)
        case .projects:
            ProjectsView(model: projectsModel)
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
