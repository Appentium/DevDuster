namespace DevDuster.Core.Explore;

public readonly record struct TreemapRect(double X, double Y, double Width, double Height);

public sealed record TreemapTile(DiskNode Node, TreemapRect Rect);

public static class TreemapLayout
{
    private readonly record struct Item(DiskNode Node, double Area);

    public static IReadOnlyList<TreemapTile> Squarify(IReadOnlyList<DiskNode> nodes, double width, double height)
    {
        var positive = nodes.Where(node => node.Bytes > 0).OrderByDescending(node => node.Bytes).ToList();
        if (positive.Count == 0 || width <= 1 || height <= 1) return [];
        var totalBytes = (double)positive.Sum(node => node.Bytes);
        var totalArea = width * height;
        if (totalBytes <= 0 || totalArea <= 0) return [];

        var remaining = new Queue<Item>(positive.Select(node => new Item(node, node.Bytes / totalBytes * totalArea)));
        var rect = new TreemapRect(0, 0, width, height);
        var row = new List<Item>();
        var result = new List<TreemapTile>();
        while (remaining.Count > 0)
        {
            var next = remaining.Peek();
            var shortSide = Math.Min(rect.Width, rect.Height);
            if (shortSide <= 0) break;
            if (row.Count == 0 || WorstRatio([.. row, next], shortSide) <= WorstRatio(row, shortSide))
            {
                row.Add(remaining.Dequeue());
            }
            else
            {
                var laid = LayoutRow(row, rect);
                result.AddRange(laid.Tiles);
                rect = laid.Remaining;
                row = [];
            }
        }
        if (row.Count > 0) result.AddRange(LayoutRow(row, rect).Tiles);
        return result;
    }

    private static double WorstRatio(IReadOnlyList<Item> row, double side)
    {
        var sum = row.Sum(item => item.Area);
        if (sum <= 0 || side <= 0) return double.PositiveInfinity;
        var min = row.Min(item => item.Area);
        var max = row.Max(item => item.Area);
        if (min <= 0) return double.PositiveInfinity;
        var sum2 = sum * sum;
        var side2 = side * side;
        return Math.Max(side2 * max / sum2, sum2 / (side2 * min));
    }

    private static (IReadOnlyList<TreemapTile> Tiles, TreemapRect Remaining) LayoutRow(IReadOnlyList<Item> row, TreemapRect rect)
    {
        var rowArea = row.Sum(item => item.Area);
        if (rowArea <= 0 || rect.Width <= 0 || rect.Height <= 0) return ([], rect);

        var tiles = new List<TreemapTile>();
        if (rect.Width >= rect.Height)
        {
            var width = Math.Min(rect.Width, rowArea / rect.Height);
            var y = rect.Y;
            foreach (var item in row)
            {
                var height = width > 0 ? item.Area / width : 0;
                var raw = new TreemapRect(rect.X, y, width, Math.Min(height, rect.Y + rect.Height - y));
                if (MakeTile(item.Node, raw) is { } tile) tiles.Add(tile);
                y += height;
            }
            var restWide = new TreemapRect(rect.X + width, rect.Y, Math.Max(0, rect.Width - width), rect.Height);
            return (tiles, restWide);
        }

        var rowHeight = Math.Min(rect.Height, rowArea / rect.Width);
        var x = rect.X;
        foreach (var item in row)
        {
            var width = rowHeight > 0 ? item.Area / rowHeight : 0;
            var raw = new TreemapRect(x, rect.Y, Math.Min(width, rect.X + rect.Width - x), rowHeight);
            if (MakeTile(item.Node, raw) is { } tile) tiles.Add(tile);
            x += width;
        }
        var restTall = new TreemapRect(rect.X, rect.Y + rowHeight, rect.Width, Math.Max(0, rect.Height - rowHeight));
        return (tiles, restTall);
    }

    private static TreemapTile? MakeTile(DiskNode node, TreemapRect rect)
    {
        var inset = rect.Width > 4 && rect.Height > 4
            ? new TreemapRect(rect.X + 1, rect.Y + 1, rect.Width - 2, rect.Height - 2)
            : rect;
        return inset.Width >= 1 && inset.Height >= 1 ? new TreemapTile(node, inset) : null;
    }
}
