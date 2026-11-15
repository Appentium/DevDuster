import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleaner = "Cleaner"
    case flutterProjects = "Flutter Projects"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .dashboard: "internaldrive"
        case .cleaner: "sparkles"
        case .flutterProjects: "wrench.and.screwdriver"
        }
    }
}
