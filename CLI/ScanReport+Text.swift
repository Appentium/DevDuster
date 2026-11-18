import DusterCore

extension ScanReport {
    var groups: [(rule: Rule, items: [ScanItem])] {
        var groups: [(rule: Rule, items: [ScanItem])] = []
        for item in items {
            if groups.last?.rule == item.rule {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((item.rule, [item]))
            }
        }
        return groups
    }

    var text: String {
        var lines: [String] = []
        for group in groups {
            let total = group.items.reduce(0) { $0 + $1.bytes }
            lines.append("[\(group.rule.tier.rawValue)] \(group.rule.title): \(total.fileSize) in \(group.items.count) item(s)")
            lines += group.items.map { "  \($0.bytes.fileSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \($0.url.path(percentEncoded: false))" }
        }
        lines += skipped.map { "Skipped \($0.rule.title): \($0.runningProcess) is running" }
        lines += skippedItems.map { "Skipped \($0.item.bytes.fileSize) \($0.item.url.path(percentEncoded: false)): quit \($0.runningApp) to clean it" }
        lines.append("Total: \(totalBytes.fileSize) in \(items.count) item(s)")
        return lines.joined(separator: "\n")
    }
}
