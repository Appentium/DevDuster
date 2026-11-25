using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Uninstall;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class LeftoverFinderTests
{
    private static InstalledProgram Program(string name, string publisher = "", string? location = null) =>
        new(name, name, publisher, "1.0", 0, location, "");

    private static IReadOnlyList<string> Find(Fixture fixture, InstalledProgram[] installed, params InstalledProgram[] removed) =>
        [.. new LeftoverFinder(fixture.Folders, fixture.Measure, new FakeProcesses())
            .Find(installed, removed).Select(leftover => leftover.Item.Name)];

    private static void MakeApp(Fixture fixture, string folder, double ageDays = 200)
    {
        fixture.MakeFile($"home/AppData/Roaming/{folder}/Local State", ageDays: ageDays);
    }

    [Fact]
    public void QuietUnclaimedAppFolderIsFound()
    {
        using var fixture = new Fixture();
        MakeApp(fixture, "Oldchat");
        Assert.Equal(["Oldchat"], Find(fixture, [Program("Something Else")]));
    }

    [Fact]
    public void EmptyInventoryFindsNothing()
    {
        using var fixture = new Fixture();
        MakeApp(fixture, "Oldchat");
        Assert.Empty(Find(fixture, []));
    }

    [Theory]
    [InlineData("Oldchat 2.1 (x64)", "")]
    [InlineData("Messenger", "Oldchat Inc.")]
    public void InstalledNameOrPublisherClaimsTheFolder(string name, string publisher)
    {
        using var fixture = new Fixture();
        MakeApp(fixture, "Oldchat");
        Assert.Empty(Find(fixture, [Program(name, publisher)]));
    }

    [Fact]
    public void RecentlyUsedAndUnmarkedFoldersAreLeftAlone()
    {
        using var fixture = new Fixture();
        MakeApp(fixture, "Freshchat", ageDays: 10);
        fixture.MakeFile("home/AppData/Roaming/Plaindata/notes.txt", ageDays: 200);
        Assert.Empty(Find(fixture, [Program("Something Else")]));
    }

    [Fact]
    public void ToolAndWindowsFoldersAreNeverLeftovers()
    {
        using var fixture = new Fixture();
        MakeApp(fixture, "npm");
        MakeApp(fixture, "Microsoft");
        Assert.Empty(Find(fixture, [Program("Something Else")]));
    }

    [Fact]
    public void JustRemovedProgramNeedsNoMarkerOrAge()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/AppData/Local/Plaindata/notes.txt");
        Assert.Equal(["Plaindata"], Find(fixture, [Program("Something Else")], Program("Plaindata 3.0")));
    }

    [Fact]
    public void GuardAllowsLeftoverShapeOnly()
    {
        using var fixture = new Fixture();
        var guard = new DenyGuard(fixture.Catalog);
        var app = fixture.MakeDirectory("home/AppData/Local/Oldchat");
        var windows = fixture.MakeDirectory("home/AppData/Local/Microsoft");
        var document = fixture.MakeDirectory("home/Documents/Oldchat");
        Assert.Equal(app, guard.Check(app, RuleCatalog.Leftover), ignoreCase: true);
        Assert.Throws<RefusedException>(() => guard.Check(windows, RuleCatalog.Leftover));
        Assert.Throws<RefusedException>(() => guard.Check(document, RuleCatalog.Leftover));
        Assert.Throws<RefusedException>(() => guard.Check(fixture.Folders.LocalAppData, RuleCatalog.Leftover));
    }
}
