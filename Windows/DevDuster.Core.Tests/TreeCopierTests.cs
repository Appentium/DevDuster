using DevDuster.Core.Relocate;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class TreeCopierTests
{
    private sealed class NoJunctions : IJunctionMaker
    {
        public void Create(string link, string target) { }
    }

    [Fact]
    public void CopiesFilesAndNestedFolders()
    {
        using var fixture = new Fixture();
        var source = fixture.MakeDirectory("source");
        fixture.MakeFile("source/one.txt", text: "one");
        fixture.MakeFile("source/sub/two.txt", text: "two");
        var target = fixture.At("target");

        new TreeCopier(new NoJunctions(), 100, null, CancellationToken.None).Copy(source, target);

        Assert.Equal("one", File.ReadAllText(Path.Combine(target, "one.txt")));
        Assert.Equal("two", File.ReadAllText(Path.Combine(target, "sub", "two.txt")));
    }

    [Fact]
    public void DoesNotFollowLinks()
    {
        using var fixture = new Fixture();
        var outside = fixture.MakeFile("outside/keep.txt", text: "keep");
        var source = fixture.MakeDirectory("source");
        try
        {
            fixture.MakeSymlink("source/link.txt", outside);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return;
        }
        var target = fixture.At("target");

        new TreeCopier(new NoJunctions(), 100, null, CancellationToken.None).Copy(source, target);

        var copied = Path.Combine(target, "link.txt");
        Assert.True(PathTools.IsLink(copied));
        Assert.True(PathTools.IsSame(PathTools.Real(copied)!, PathTools.Real(outside)!));
        Assert.True(File.Exists(outside));
    }
}