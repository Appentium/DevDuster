using DevDuster.Core.Clean;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class CleanerTests
{
    private static ScanItem Item(Fixture fixture, string path, string rule = "windows.temp", long bytes = 10) =>
        new(fixture.Rule(rule), path, bytes);

    [Fact]
    public void RecycleCallsTheRemoverAndLogs()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("tmp/a.tmp");
        var remover = new FakeRemover();
        var log = new CleanLog(fixture.At("logs/clean.log"));

        var results = fixture.MakeCleaner(remover, log)
            .CleanAsync(new[] { Item(fixture, file) }, CleanMode.Recycle, null, CancellationToken.None)
            .GetAwaiter().GetResult();

        Assert.Null(results[0].Error);
        Assert.Contains(remover.Recycled, path => PathTools.IsSame(path, file));
        Assert.Equal(1, log.Records().Count);
    }

    [Fact]
    public void DeleteRemovesAndLogs()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("tmp/a.tmp");
        var remover = new FakeRemover();
        var log = new CleanLog(fixture.At("logs/clean.log"));

        var results = fixture.MakeCleaner(remover, log)
            .CleanAsync(new[] { Item(fixture, file) }, CleanMode.Delete, null, CancellationToken.None)
            .GetAwaiter().GetResult();

        Assert.Null(results[0].Error);
        Assert.False(File.Exists(file));
        Assert.Equal(1, log.Records().Count);
    }

    [Fact]
    public void RefusedItemIsNotRemovedAndReturnsAnError()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("home/Documents/report.pdf");
        var remover = new FakeRemover();
        var log = new CleanLog(fixture.At("logs/clean.log"));

        var results = fixture.MakeCleaner(remover, log)
            .CleanAsync(new[] { Item(fixture, file) }, CleanMode.Recycle, null, CancellationToken.None)
            .GetAwaiter().GetResult();

        Assert.NotNull(results[0].Error);
        Assert.Empty(remover.Recycled);
        Assert.True(File.Exists(file));
        Assert.Empty(log.Records());
    }
}