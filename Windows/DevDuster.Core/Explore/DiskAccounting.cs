using DevDuster.Core.Scan;

namespace DevDuster.Core.Explore;

public static class DiskAccounting
{
    public const string UnseenLabel = "Not visible to this scan";

    // On a whole drive the blocks must add up to what Windows reports as used.
    public static DiskNode WithUnseen(DiskNode root, LocalDrive drive)
    {
        var unseen = drive.UsedBytes - root.Bytes;
        if (!PathTools.IsSame(Path.TrimEndingDirectorySeparator(root.Path), Path.TrimEndingDirectorySeparator(drive.Root)) || unseen <= 0) return root;
        var block = new DiskNode(Path.Combine(root.Path, "#unseen"), UnseenLabel, unseen, false, [], 1);
        return new DiskNode(root.Path, root.Name, drive.UsedBytes, true, [.. root.Children.Append(block).OrderByDescending(node => node.Bytes)])
        {
            Unreadable = root.Unreadable,
            Insights = root.Insights,
        };
    }
}
