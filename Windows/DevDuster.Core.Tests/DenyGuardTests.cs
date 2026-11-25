using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DenyGuardTests
{
    private static DenyGuard Guard(Fixture fixture) => new(fixture.Catalog);

    [Fact]
    public void UserSelectedRefusesHome()
    {
        using var fixture = new Fixture();
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(fixture.Folders.Home, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.HomeOrDriveRoot, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesParentOfHome()
    {
        using var fixture = new Fixture();
        var parent = Path.GetDirectoryName(fixture.Folders.Home)!;
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(parent, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.HomeOrDriveRoot, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesDriveRoot()
    {
        using var fixture = new Fixture();
        var root = Path.GetPathRoot(fixture.Root)!;
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(root, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.HomeOrDriveRoot, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesDirectChildOfHome()
    {
        using var fixture = new Fixture();
        var folder = fixture.MakeDirectory("home/Documents");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(folder, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesLocalAppData()
    {
        using var fixture = new Fixture();
        var folder = fixture.MakeDirectory("home/AppData/Local");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(folder, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesLocalAppDataChild()
    {
        using var fixture = new Fixture();
        var folder = fixture.MakeDirectory("home/AppData/Local/SomeApp");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(folder, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesSshKey()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("home/.ssh/id");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(file, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesCloudFolderChild()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("OneDrive/doc.txt");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(file, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedRefusesSystemFolderChild()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("Windows/evil.txt");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(file, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Protected, error.Refusal);
    }

    [Fact]
    public void UserSelectedAllowsFileInsideHomeFolder()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("home/Documents/a.bin");
        var resolved = Guard(fixture).Check(file, RuleCatalog.UserSelected);
        Assert.True(PathTools.IsSame(resolved, file));
    }

    [Fact]
    public void FolderRuleRefusesPathOutsideItsPattern()
    {
        using var fixture = new Fixture();
        var file = fixture.MakeFile("home/Documents/a.bin");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(file, fixture.Rule("npm.cache")));
        Assert.Equal(Refusal.OutsideRule, error.Refusal);
    }

    [Fact]
    public void MissingPathIsRefused()
    {
        using var fixture = new Fixture();
        fixture.MakeDirectory("home/Documents");
        var missing = fixture.At("home/Documents/gone");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(missing, RuleCatalog.UserSelected));
        Assert.Equal(Refusal.Missing, error.Refusal);
    }

    [Fact]
    public void RelativePathIsUnsupported()
    {
        using var fixture = new Fixture();
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check("relative/path", RuleCatalog.UserSelected));
        Assert.Equal(Refusal.UnsupportedPath, error.Refusal);
    }

    [Fact]
    public void NodeModulesWithoutPackageJsonIsOutsideRule()
    {
        using var fixture = new Fixture();
        var folder = fixture.MakeDirectory("home/Code/app/node_modules");
        var error = Assert.Throws<RefusedException>(() => Guard(fixture).Check(folder, fixture.Rule("project.node-modules")));
        Assert.Equal(Refusal.OutsideRule, error.Refusal);
    }

    [Fact]
    public void NodeModulesWithPackageJsonIsAllowed()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/app/package.json");
        var folder = fixture.MakeDirectory("home/Code/app/node_modules");
        var resolved = Guard(fixture).Check(folder, fixture.Rule("project.node-modules"));
        Assert.True(PathTools.IsSame(resolved, folder));
    }
}