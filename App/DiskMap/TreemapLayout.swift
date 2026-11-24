import CoreGraphics
import DusterCore

struct TreemapTile: Identifiable {
    let node: DiskNode
    let rect: CGRect

    var id: String { node.id }
}

enum TreemapLayout {
    private struct Item {
        let node: DiskNode
        let area: Double
    }

    private static let minTileArea: CGFloat = 90 * 48
    private static let maxWidthMultiple: CGFloat = 8
    private static let minCanvasWidth: CGFloat = 640

    static func canvasSize(for nodes: [DiskNode], viewport: CGSize) -> CGSize {
        let height = viewport.height
        let baseWidth = max(viewport.width, minCanvasWidth)
        let sizes = nodes.map(\.bytes).filter { $0 > 0 }
        guard let smallest = sizes.min(), height > 1 else { return CGSize(width: baseWidth, height: height) }
        let total = CGFloat(sizes.reduce(0, +))
        let needed = total / CGFloat(smallest) * minTileArea / height
        return CGSize(width: min(max(baseWidth, needed), baseWidth * maxWidthMultiple), height: height)
    }

    static func tiles(for nodes: [DiskNode], in bounds: CGRect) -> [TreemapTile] {
        let positive = nodes.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard !positive.isEmpty, bounds.width > 1, bounds.height > 1 else { return [] }

        let totalBytes = Double(positive.reduce(0) { $0 + $1.bytes })
        let totalArea = Double(bounds.width * bounds.height)
        guard totalBytes > 0, totalArea > 0 else { return [] }

        var remaining = positive.map { Item(node: $0, area: Double($0.bytes) / totalBytes * totalArea) }[...]
        var rect = bounds
        var row: [Item] = []
        var result: [TreemapTile] = []

        while let next = remaining.first {
            let shortSide = Double(min(rect.width, rect.height))
            guard shortSide > 0 else { break }

            if row.isEmpty || worstRatio(row + [next], side: shortSide) <= worstRatio(row, side: shortSide) {
                row.append(next)
                remaining = remaining.dropFirst()
            } else {
                let laid = layoutRow(row, in: rect)
                result.append(contentsOf: laid.tiles)
                rect = laid.remaining
                row = []
            }
        }

        if !row.isEmpty {
            result.append(contentsOf: layoutRow(row, in: rect).tiles)
        }

        return result
    }

    private static func worstRatio(_ row: [Item], side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, side > 0 else { return .infinity }
        let minArea = row.map(\.area).min() ?? 0
        let maxArea = row.map(\.area).max() ?? 0
        guard minArea > 0 else { return .infinity }
        let sum2 = sum * sum
        let side2 = side * side
        return max((side2 * maxArea) / sum2, sum2 / (side2 * minArea))
    }

    private static func layoutRow(_ row: [Item], in rect: CGRect) -> (tiles: [TreemapTile], remaining: CGRect) {
        let rowArea = row.reduce(0) { $0 + $1.area }
        guard rowArea > 0, rect.width > 0, rect.height > 0 else { return ([], rect) }

        var tiles: [TreemapTile] = []
        if rect.width >= rect.height {
            let width = min(rect.width, CGFloat(rowArea / Double(rect.height)))
            var y = rect.minY
            for item in row {
                let height = width > 0 ? CGFloat(item.area / Double(width)) : 0
                let raw = CGRect(x: rect.minX, y: y, width: width, height: min(height, rect.maxY - y))
                if let tile = makeTile(node: item.node, rect: raw) { tiles.append(tile) }
                y += height
            }
            let remaining = CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
            return (tiles, remaining)
        }

        let height = min(rect.height, CGFloat(rowArea / Double(rect.width)))
        var x = rect.minX
        for item in row {
            let width = height > 0 ? CGFloat(item.area / Double(height)) : 0
            let raw = CGRect(x: x, y: rect.minY, width: min(width, rect.maxX - x), height: height)
            if let tile = makeTile(node: item.node, rect: raw) { tiles.append(tile) }
            x += width
        }
        let remaining = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
        return (tiles, remaining)
    }

    private static func makeTile(node: DiskNode, rect: CGRect) -> TreemapTile? {
        let inset = rect.width > 4 && rect.height > 4 ? rect.insetBy(dx: 1, dy: 1) : rect
        guard inset.width >= 1, inset.height >= 1 else { return nil }
        return TreemapTile(node: node, rect: inset)
    }
}
