using DevDuster.Core.Clean;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class TreeRemoverTests
{
    [Fact]
    public void ReadOnlyFileIsRemoved()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("a/keep.bin");
        File.SetAttributes(file, FileAttributes.ReadOnly);

        var failures = TreeRemover.Remove(file);
        Assert.Empty(failures);
        Assert.False(File.Exists(file));
    }

    [Fact]
    public void SymlinkIsRemovedButItsTargetSurvives()
    {
        using var fixture = new Fixture();
        var target = fixture.MakeFile("outside/keep.bin");
        var folder = fixture.MakeDirectory("item");
        try
        {
            fixture.MakeSymlink("item/link.bin", target);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return;
        }
        fixture.MakeFile("item/data.bin");

        var failures = TreeRemover.Remove(folder);
        Assert.Empty(failures);
        Assert.False(Directory.Exists(folder));
        Assert.True(File.Exists(target));
    }
}