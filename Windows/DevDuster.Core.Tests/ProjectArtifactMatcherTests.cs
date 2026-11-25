using DevDuster.Core.Rules;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class ProjectArtifactMatcherTests
{
    [Fact]
    public void BinWithoutProofIsUnmatched()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/app/Api.csproj");
        var bin = fixture.MakeDirectory("home/Code/app/bin");
        fixture.MakeFile("home/Code/app/bin/out.dll");

        var matcher = new ProjectArtifactMatcher(fixture.Catalog);
        Assert.Null(matcher.RuleForArtifact(bin));
    }

    [Fact]
    public void UnityNestedMarkerLevelsOneAboveItsFolder()
    {
        using var fixture = new Fixture();
        var marker = fixture.At("home/Code/game/ProjectSettings/ProjectVersion.txt");

        var matcher = new ProjectArtifactMatcher(fixture.Catalog);
        Assert.Equal(new[] { 1 }, matcher.ProjectLevels(marker));
    }
}