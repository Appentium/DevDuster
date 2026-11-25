using DevDuster.Core.Scan;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class DusterScannerTests
{
    private static ScanOptions Options(Fixture fixture) => new() { Scope = new[] { fixture.Root } };

    [Fact]
    public void RunningProcessSkipsItsRuleAndReportsIt()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/.gradle/caches/build-cache-1/entry.bin");

        var report = fixture.Scan(Options(fixture), "java");
        Assert.DoesNotContain(report.Items, item => item.Rule.Id == "gradle.build-cache");
        Assert.Contains(report.Skipped, skipped => skipped.Rule.Id == "gradle.build-cache" && skipped.RunningProcess == "java");

        var free = fixture.Scan(Options(fixture));
        Assert.Contains(free.Items, item => item.Rule.Id == "gradle.build-cache");
    }

    [Fact]
    public void TempFileNewerThanSevenDaysIsNotOffered()
    {
        using var fixture = new Fixture();
        var fresh = fixture.MakeFile("tmp/fresh.tmp", ageDays: 0);
        var old = fixture.MakeFile("tmp/old.tmp", ageDays: 10);

        var offered = fixture.Scan(Options(fixture)).Items
            .Where(item => item.Rule.Id == "windows.temp")
            .Select(item => item.Path)
            .ToHashSet();
        Assert.Contains(old, offered);
        Assert.DoesNotContain(fresh, offered);
    }

    [Fact]
    public void StaleNodeModulesIsOfferedAndFreshOneIsNot()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/Code/old/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/old/index.js", ageDays: 40);
        fixture.MakeFile("home/Code/old/node_modules/lib/index.js", ageDays: 40);
        fixture.MakeFile("home/Code/new/package.json", ageDays: 40);
        fixture.MakeFile("home/Code/new/index.js", ageDays: 2);
        fixture.MakeFile("home/Code/new/node_modules/lib/index.js", ageDays: 40);

        var offered = fixture.Scan(Options(fixture)).Items
            .Where(item => item.Rule.Id == "project.node-modules")
            .Select(item => item.Path)
            .ToList();
        var staleFolder = fixture.At("home/Code/old/node_modules");
        var freshFolder = fixture.At("home/Code/new/node_modules");
        Assert.Contains(offered, path => PathTools.IsSame(path, staleFolder));
        Assert.DoesNotContain(offered, path => PathTools.IsSame(path, freshFolder));
    }
}