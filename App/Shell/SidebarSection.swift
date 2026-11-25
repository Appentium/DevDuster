import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleaner = "Cleaner"
    case uninstaller = "Uninstaller"
    case projects = "Projects"
    case largeFiles = "Large Files"
    case developerTools = "Developer Tools"
    case moveTools = "Move Tools"
    case diskMap = "Disk Map"
    case system = "System"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .dashboard: "internaldrive"
        case .cleaner: "sparkles"
        case .uninstaller: "trash.square"
        case .developerTools: "hammer"
        case .moveTools: "externaldrive.badge.plus"
        case .projects: "wrench.and.screwdriver"
        case .diskMap: "square.grid.3x3.square"
        case .largeFiles: "doc.badge.ellipsis"
        case .system: "gearshape.2"
        }
    }
}
