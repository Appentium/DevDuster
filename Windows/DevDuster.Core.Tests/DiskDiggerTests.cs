using DevDuster.Core.Clean;
using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DiskDiggerTests
{
    private static IEnumerable<(string, long)> Named(string prefix, int count) =>
        Enumerable.Range(1, count).Select(index => ($"{prefix}{index}", 10L));

    private static DeleteAssessment Assess(Fixture fixture, string path, params string[] running) =>
        new DeleteRisk(fixture.Catalog, new FakeProcesses(running)).Assess(path);

    [Fact]
    public void TwentySiblingsMakeACloneSetAndNineteenDoNot()
    {
        Assert.Empty(Insights.CloneSets(Named("demo_t_x_test_", 19)));
        var set = Assert.Single(Insights.CloneSets(Named("demo_t_x_test_", 1484).Concat(Named("other", 3))));
        Assert.Equal("demo_", set.Prefix);
        Assert.Equal(1484, set.Names.Count);
        Assert.Equal(2, Insights.CloneSets(Named("a_", 30).Concat(Named("b_", 30))).Count);
    }

    [Theory]
    [InlineData("mysql.ibd", DatabaseKind.MySql)]
    [InlineData("PG_VERSION,global", DatabaseKind.Postgres)]
    [InlineData("PG_VERSION", null)]
    [InlineData("notes.txt", null)]
    public void DatabaseFoldersAreDetected(string names, DatabaseKind? expected) =>
        Assert.Equal(expected, Insights.Database(names.Split(',').ToHashSet()));

    [Fact]
    public void KnowledgeGradesDatabaseFolders()
    {
        Assert.Equal(RiskLevel.Critical, PathKnowledge.Match(@"C:\xampp\mysql\data\foo")!.Risk);
        Assert.Null(PathKnowledge.Match(@"C:\Users\me\Documents"));
    }

    [Fact]
    public void RiskLevels()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/app/package.json");
        var modules = fixture.MakeDirectory("home/Code/app/node_modules");
        var document = fixture.MakeFile("home/Documents/a.bin");
        fixture.MakeFile("home/Code/data/db/mysql.ibd");
        var database = fixture.At("home/Code/data/db");
        fixture.MakeDirectory("home/Code/repo/.git");
        Assert.Equal(RiskLevel.Safe, Assess(fixture, modules).Level);
        Assert.Equal(RiskLevel.Review, Assess(fixture, document).Level);
        Assert.Equal(RiskLevel.Critical, Assess(fixture, database).Level);
        Assert.Equal(RiskLevel.Blocked, Assess(fixture, database, "mysqld").Level);
        Assert.Equal(RiskLevel.Critical, Assess(fixture, fixture.At("home/Code/repo")).Level);
        Assert.Equal(RiskLevel.Blocked, Assess(fixture, fixture.Folders.Home).Level);
    }

    [Fact]
    public void TypedNameMustMatchExactly()
    {
        var assessment = new DeleteAssessment(Path.Combine(Path.GetTempPath(), "Data"), RiskLevel.Critical, []);
        Assert.True(assessment.Confirms("Data"));
        Assert.False(assessment.Confirms("data"));
    }

    [Fact]
    public void SystemDatabasesAreNeverOfferedOrDropped()
    {
        var parsed = MySqlInspector.Parse("mysql\t5\r\nsys\t1\r\ninformation_schema\t0\r\nperformance_schema\t0\r\nshop\t42\r\n");
        Assert.Equal([new MySqlDatabase("shop", 42)], parsed);
        var statements = new List<string>();
        var inspector = new MySqlInspector((arguments, _) => { statements.Add(arguments[^1]); return ""; });
        Assert.False(inspector.Drop("mysql"));
        Assert.False(inspector.Drop(@"a\! calc"));
        Assert.True(inspector.Drop("odd`name"));
        Assert.Equal(["DROP DATABASE `odd``name`"], statements);
    }

    [Fact]
    public void UnseenBlockMakesADriveAddUpToUsedSpace()
    {
        var root = Path.GetPathRoot(Path.GetTempPath())!;
        var tree = new DiskNode(root, root, 170, true, []);
        var drive = new LocalDrive(root, "", "NTFS", 300, 60, true, false);
        var counted = DiskAccounting.WithUnseen(tree, drive);
        Assert.Equal(240, counted.Bytes);
        Assert.Equal(70, Assert.Single(counted.Children).Bytes);
        Assert.Same(tree, DiskAccounting.WithUnseen(tree, drive with { AvailableBytes = 200 }));
    }
}
