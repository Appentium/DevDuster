using DevDuster.Core.Explore;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class LargeFileFinderTests
{
    private static LargeFileFinder Finder(Fixture fixture) => new(fixture.Folders, fixture.Drives, fixture.Measure);

    private static IReadOnlyList<LargeFile> Run(Fixture fixture, LargeFileOptions options) =>
        Finder(fixture).RunAsync(options, null, CancellationToken.None).GetAwaiter().GetResult();

    [Fact]
    public void OnlyFilesAtOrAboveMinBytesAreReturned()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("find");
        fixture.MakeFile("find/big.bin", bytes: 2_000_000);
        fixture.MakeFile("find/small.bin", bytes: 100);

        var found = Run(fixture, new LargeFileOptions { MinBytes = 1_000_000, Roots = [root] });

        var path = Assert.Single(found).Path;
        Assert.True(PathTools.IsSame(path, fixture.At("find/big.bin")));
    }

    [Fact]
    public void ResultsAreOrderedLargestFirst()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("find");
        fixture.MakeFile("find/small.bin", bytes: 1_500_000);
        fixture.MakeFile("find/big.bin", bytes: 3_000_000);
        fixture.MakeFile("find/mid.bin", bytes: 2_000_000);

        var found = Run(fixture, new LargeFileOptions { MinBytes = 1_000_000, Roots = [root] });

        Assert.Equal(new long[] { 3_000_000, 2_000_000, 1_500_000 }, found.Select(file => file.Bytes).ToArray());
    }

    [Fact]
    public void ExcludedPathIsSkipped()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("find");
        fixture.MakeFile("find/keep.bin", bytes: 2_000_000);
        var skip = fixture.MakeDirectory("find/skip");
        fixture.MakeFile("find/skip/big.bin", bytes: 9_000_000);

        var found = Run(fixture, new LargeFileOptions { MinBytes = 1_000_000, Roots = [root], ExcludedPaths = [skip] });

        var path = Assert.Single(found).Path;
        Assert.True(PathTools.IsSame(path, fixture.At("find/keep.bin")));
    }

    [Fact]
    public void MinAgeDaysSkipsFreshFiles()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("find");
        fixture.MakeFile("find/old.bin", bytes: 2_000_000, ageDays: 40);
        fixture.MakeFile("find/fresh.bin", bytes: 2_000_000, ageDays: 0);

        var found = Run(fixture, new LargeFileOptions { MinBytes = 1_000_000, MinAgeDays = 7, Roots = [root] });

        var path = Assert.Single(found).Path;
        Assert.True(PathTools.IsSame(path, fixture.At("find/old.bin")));
    }
}