using DevDuster.Core.Automation;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class LowSpaceMonitorTests
{
    private static LocalDrive Drive(string root, long available, bool system) =>
        new(root, root, "NTFS", available * 2, available, system, false);

    [Fact]
    public void AvailableExactlyAtThresholdIsNotLow()
    {
        var monitor = new LowSpaceMonitor();
        var drive = Drive("C:", 20_000_000_000, system: true);

        var fresh = monitor.NewlyLow([drive], 20, 10);

        Assert.Empty(fresh);
    }

    [Fact]
    public void AvailableOneByteBelowThresholdIsLow()
    {
        var monitor = new LowSpaceMonitor();
        var drive = Drive("C:", 20_000_000_000 - 1, system: true);

        var fresh = monitor.NewlyLow([drive], 20, 10);

        Assert.Equal("C:", Assert.Single(fresh).Root);
    }

    [Fact]
    public void NonSystemDriveUsesOtherThreshold()
    {
        var monitor = new LowSpaceMonitor();
        var drive = Drive("D:", 10_000_000_000 - 1, system: false);

        var fresh = monitor.NewlyLow([drive], 20, 10);

        Assert.Equal("D:", Assert.Single(fresh).Root);
    }

    [Fact]
    public void AlertsOnceUntilRecovery()
    {
        var monitor = new LowSpaceMonitor();
        var low = Drive("C:", 5_000_000_000, system: true);

        Assert.Single(monitor.NewlyLow([low], 20, 10));
        Assert.Empty(monitor.NewlyLow([low], 20, 10));

        var recovered = Drive("C:", 25_000_000_000, system: true);
        Assert.Empty(monitor.NewlyLow([recovered], 20, 10));
        Assert.Single(monitor.NewlyLow([low], 20, 10));
    }
}