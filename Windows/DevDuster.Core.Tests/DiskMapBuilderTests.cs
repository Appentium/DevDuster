using DevDuster.Core.Explore;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DiskMapBuilderTests
{
    private static DiskMapBuilder Builder(Fixture fixture) => new(fixture.Measure);

    private static DiskNode? Run(Fixture fixture, string root, IReadOnlyList<string>? excluded = null) =>
        Builder(fixture).RunAsync(root, excluded ?? [], null, CancellationToken.None).GetAwaiter().GetResult();

    [Fact]
    public void SizesSumFileLengths()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("map");
        fixture.MakeFile("map/a.bin", bytes: 3_000_000);
        fixture.MakeFile("map/sub/b.bin", bytes: 2_000_000);

        var node = Run(fixture, root);

        Assert.NotNull(node);
        Assert.Equal(5_000_000, node.Bytes);
        Assert.True(node.IsDirectory);
    }

    [Fact]
    public void SmallFilesFoldIntoOther()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("map");
        for (var i = 0; i < 5; i++)
            fixture.MakeFile($"map/f{i}.bin", bytes: 1_000);

        var node = Run(fixture, root);

        Assert.NotNull(node);
        var other = Assert.Single(node.Children);
        Assert.Equal("Other (5 items)", other.Name);
        Assert.Equal(5_000, other.Bytes);
        Assert.Equal(5, other.FoldedCount);
    }

    [Fact]
    public void ExcludedFolderIsNotCounted()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("map");
        fixture.MakeFile("map/keep.bin", bytes: 4_000_000);
        var skip = fixture.MakeDirectory("map/skip");
        fixture.MakeFile("map/skip/big.bin", bytes: 9_000_000);

        var node = Run(fixture, root, [skip]);

        Assert.NotNull(node);
        Assert.Equal(4_000_000, node.Bytes);
        Assert.DoesNotContain(node.Children, child => PathTools.IsSame(child.Path, skip));
    }

    [Fact]
    public void UnreadableFolderIsListed()
    {
        if (OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("map");
        fixture.MakeFile("map/keep.bin", bytes: 1_000);
        var locked = fixture.MakeDirectory("map/locked");
        File.SetUnixFileMode(locked, UnixFileMode.None);
        if (PathTools.TryChildren(locked) is not null) return;

        var node = Run(fixture, root);

        Assert.NotNull(node);
        Assert.Contains(node.Unreadable, path => PathTools.IsSame(path, locked));
    }
}