using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class SizeCalculatorTests
{
    [Fact]
    public void HardLinkIdCountsOnce()
    {
        using var fixture = new Fixture();
        var original = fixture.MakeFile("a/original.bin", bytes: 100_000);
        var link = fixture.MakeFile("a/link.bin", bytes: 100_000);

        // A shared id stands in for the one inode a hard link shares on every platform.
        var measure = new FakeMeasure(file => PathTools.IsSame(file.FullName, original) || PathTools.IsSame(file.FullName, link) ? "shared" : null);
        var sizes = new SizeCalculator(measure);
        Assert.Equal(100_000, sizes.AllocatedSize(fixture.At("a")));
    }
}