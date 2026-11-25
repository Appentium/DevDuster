using DevDuster.Core.Scan;

namespace DevDuster.Core.Automation;

public sealed class LowSpaceMonitor
{
    private const long RecoveryMargin = 2_000_000_000;

    private readonly HashSet<string> _alerted = new(PathTools.Comparer);

    public IReadOnlyList<LocalDrive> NewlyLow(IReadOnlyList<LocalDrive> drives, int systemGB, int otherGB)
    {
        long Threshold(LocalDrive drive) => (long)(drive.IsSystem ? systemGB : otherGB) * 1_000_000_000L;
        var below = drives.Where(drive => drive.AvailableBytes < Threshold(drive)).ToList();
        _alerted.ExceptWith(drives.Where(drive => drive.AvailableBytes >= Threshold(drive) + RecoveryMargin).Select(drive => drive.Root));
        _alerted.IntersectWith(drives.Select(drive => drive.Root));
        var fresh = below.Where(drive => !_alerted.Contains(drive.Root)).ToList();
        _alerted.UnionWith(fresh.Select(drive => drive.Root));
        return fresh;
    }
}
