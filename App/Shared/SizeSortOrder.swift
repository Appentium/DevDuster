import Foundation

enum SizeSortOrder: String, CaseIterable, Identifiable {
    case standard = "Default"
    case size = "Size"
    case name = "Name"

    var id: Self { self }

    func sorted<Element>(_ elements: [Element], bytes: (Element) -> Int64, name: (Element) -> String) -> [Element] {
        guard self != .standard else { return elements }
        return elements.sorted { first, second in
            if self == .size {
                let firstBytes = bytes(first)
                let secondBytes = bytes(second)
                if firstBytes != secondBytes { return firstBytes > secondBytes }
            }
            return name(first).localizedStandardCompare(name(second)) == .orderedAscending
        }
    }
}
