import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleaner = "Cleaner"
    case flutterProjects = "Flutter Projects"
    case diskMap = "Disk Map"
    case largeFiles = "Large Files"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .dashboard: "internaldrive"
        case .cleaner: "sparkles"
        case .flutterProjects: "wrench.and.screwdriver"
        case .diskMap: "square.grid.3x3.square"
        case .largeFiles: "doc.badge.ellipsis"
        }
    }
}
