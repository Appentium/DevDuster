using DevDuster.Core.Relocate;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class TreeSnapshotTests
{
    private static readonly DateTime Fixed = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    private static TreeSnapshot Snapshot(Fixture fixture, string root) =>
        TreeSnapshot.Of(root, CancellationToken.None);

    private static void Pin(Fixture fixture, params string[] files)
    {
        foreach (var file in files) File.SetLastWriteTimeUtc(fixture.At(file), Fixed);
    }

    [Fact]
    public void EqualTreesMatch()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("a/one.txt", text: "one");
        fixture.MakeFile("a/sub/two.txt", text: "two");
        fixture.MakeFile("b/one.txt", text: "one");
        fixture.MakeFile("b/sub/two.txt", text: "two");
        Pin(fixture, "a/one.txt", "a/sub/two.txt", "b/one.txt", "b/sub/two.txt");

        var difference = Snapshot(fixture, fixture.At("a")).FirstDifference(Snapshot(fixture, fixture.At("b")));

        Assert.Null(difference);
    }

    [Fact]
    public void ChangedSizeDiffers()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("a/one.txt", bytes: 100);
        fixture.MakeFile("b/one.txt", bytes: 200);

        var difference = Snapshot(fixture, fixture.At("a")).FirstDifference(Snapshot(fixture, fixture.At("b")));

        Assert.Equal("one.txt", difference);
    }

    [Fact]
    public void ChangedTimeDiffers()
    {
        using var fixture = new Fixture();
        var a = fixture.MakeFile("a/one.txt", bytes: 100);
        var b = fixture.MakeFile("b/one.txt", bytes: 100);
        File.SetLastWriteTimeUtc(a, new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        File.SetLastWriteTimeUtc(b, new DateTime(2021, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        var difference = Snapshot(fixture, fixture.At("a")).FirstDifference(Snapshot(fixture, fixture.At("b")));

        Assert.Equal("one.txt", difference);
    }

    [Fact]
    public void AddedFileDiffers()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("a/one.txt", text: "one");
        fixture.MakeFile("b/one.txt", text: "one");
        fixture.MakeFile("b/two.txt", text: "two");
        Pin(fixture, "a/one.txt", "b/one.txt", "b/two.txt");

        var difference = Snapshot(fixture, fixture.At("a")).FirstDifference(Snapshot(fixture, fixture.At("b")));

        Assert.Equal("two.txt", difference);
    }

    [Fact]
    public void RemovedFileDiffers()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("a/one.txt", text: "one");
        fixture.MakeFile("a/two.txt", text: "two");
        fixture.MakeFile("b/one.txt", text: "one");
        Pin(fixture, "a/one.txt", "a/two.txt", "b/one.txt");

        var difference = Snapshot(fixture, fixture.At("a")).FirstDifference(Snapshot(fixture, fixture.At("b")));

        Assert.Equal("two.txt", difference);
    }
}