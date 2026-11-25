using DevDuster.Core.Rules;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class RuleGlobTests
{
    [Fact]
    public void StarMatchesEveryVisibleChild()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/glob/Alpha/x");
        fixture.MakeFile("home/glob/beta/x");
        fixture.MakeFile("home/glob/.hidden/x");

        var matches = new RuleGlob(fixture.Folders, "~/glob/*").Matches();
        Assert.Contains(fixture.At("home/glob/Alpha"), matches);
        Assert.Contains(fixture.At("home/glob/beta"), matches);
        Assert.DoesNotContain(fixture.At("home/glob/.hidden"), matches);
    }

    [Fact]
    public void QuestionMarkMatchesSingleCharacter()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/glob/Alpha/x");
        fixture.MakeFile("home/glob/beta/x");
        var glob = new RuleGlob(fixture.Folders, "~/glob/?????");

        Assert.True(glob.Contains(fixture.At("home/glob/Alpha")));
        Assert.False(glob.Contains(fixture.At("home/glob/beta")));
    }

    [Fact]
    public void MatchingIsCaseInsensitive()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/glob/Alpha/x");
        var glob = new RuleGlob(fixture.Folders, "~/glob/alpha");

        Assert.True(glob.Contains(fixture.At("home/glob/Alpha")));
    }

    [Fact]
    public void StarNeverMatchesDotFolder()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/glob/.hidden/x");
        var glob = new RuleGlob(fixture.Folders, "~/glob/*");

        Assert.False(glob.Contains(fixture.At("home/glob/.hidden")));
    }
}