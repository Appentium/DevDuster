using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DevStorageTests
{
    private static DevTool Tool(string root) =>
        new("mytool", "My Tool", RulePlatform.OtherLanguages, [root], [new DevToolEssential("Cache", "cache")]);

    private static DevStorageAnalyzer Analyzer(Fixture fixture, params DevTool[] tools) =>
        new(fixture.Folders, tools, fixture.Measure);

    [Fact]
    public void RootOfReturnsNullWhenMissing()
    {
        using var fixture = new Fixture();

        Assert.Null(Analyzer(fixture, Tool("~/nope")).RootOf(Tool("~/nope")));
    }

    [Fact]
    public void RootOfResolvesExistingFolder()
    {
        using var fixture = new Fixture();
        var root = fixture.MakeDirectory("home/mytool");

        var resolved = Analyzer(fixture, Tool("~/mytool")).RootOf(Tool("~/mytool"));

        Assert.True(PathTools.IsSame(resolved, root));
    }

    [Fact]
    public void EssentialAndOtherPartsAreReported()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/mytool/cache/lib.bin", bytes: 1_000);
        fixture.MakeFile("home/mytool/data.bin", bytes: 500);

        var usages = Analyzer(fixture, Tool("~/mytool")).RunAsync([], CancellationToken.None).GetAwaiter().GetResult();

        var usage = Assert.Single(usages);
        Assert.Equal(1_500, usage.TotalBytes);
        Assert.Equal("Cache", usage.Parts[0].Title);
        Assert.Equal(DevPartKind.Essential, usage.Parts[0].Kind);
        Assert.Equal(1_000, usage.Parts[0].Bytes);
        Assert.Equal("Other files", usage.Parts[1].Title);
        Assert.Equal(500, usage.Parts[1].Bytes);
    }

    [Fact]
    public void CleanableItemBecomesAPartAndClaimsItsBytes()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/mytool/cache/lib.bin", bytes: 1_000);
        fixture.MakeFile("home/mytool/data.bin", bytes: 500);
        var item = new ScanItem(fixture.Rule("windows.temp"), fixture.At("home/mytool/cache/lib.bin"), 1_000);

        var usages = Analyzer(fixture, Tool("~/mytool")).RunAsync([item], CancellationToken.None).GetAwaiter().GetResult();

        var usage = Assert.Single(usages);
        var cleanable = Assert.Single(usage.Parts, part => part.Kind == DevPartKind.Cleanable);
        Assert.Equal(1_000, cleanable.Bytes);
        Assert.Equal(500, usage.TotalBytes - cleanable.Bytes);
        Assert.DoesNotContain(usage.Parts, part => part.Kind == DevPartKind.Essential);
    }

    [Fact]
    public void ToolsWithNoBytesAreOmitted()
    {
        using var fixture = new Fixture();
        fixture.MakeDirectory("home/empty");

        var usages = Analyzer(fixture, Tool("~/empty")).RunAsync([], CancellationToken.None).GetAwaiter().GetResult();

        Assert.Empty(usages);
    }
}