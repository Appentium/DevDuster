using DevDuster.Core.Rules;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class FolderRuleExpanderTests
{
    [Fact]
    public void VersionOfParsesTrailingVersion()
    {
        Assert.Equal(new Version(8, 10, 2), FolderRuleExpander.VersionOf("gradle-8.10.2-all"));
    }

    [Fact]
    public void VersionOfPadsSingleNumber()
    {
        Assert.Equal(new Version(34, 0), FolderRuleExpander.VersionOf("34"));
    }

    [Fact]
    public void VersionOfIgnoresText()
    {
        Assert.Null(FolderRuleExpander.VersionOf("android"));
    }

    [Fact]
    public void OnlyNewestVersionIsOffered()
    {
        using var fixture = new Fixture();
        foreach (var name in new[] { "gradle-8.9-bin", "gradle-8.14.3-all", "gradle-9.3.1-all" })
            fixture.MakeFile($"home/.gradle/wrapper/dists/{name}/dist.zip");

        var expansion = new FolderRuleExpander(fixture.Folders).Expand(fixture.Rule("gradle.wrapper"));
        var offered = expansion.Offered.Select(Path.GetFileName).ToHashSet();
        Assert.Equal(3, expansion.All.Count);
        Assert.Contains("gradle-8.9-bin", offered);
        Assert.Contains("gradle-8.14.3-all", offered);
        Assert.DoesNotContain("gradle-9.3.1-all", offered);
    }

    [Fact]
    public void UsedAvdImageIsKeptAndTheOtherOffered()
    {
        using var fixture = new Fixture();
        var images = "home/AppData/Local/Android/Sdk/system-images";
        fixture.MakeFile($"{images}/android-35/google_apis/arm64-v8a/system.img");
        fixture.MakeFile($"{images}/android-37.0/google_apis_playstore/arm64-v8a/system.img");
        fixture.MakeFile("home/.android/avd/Pixel.avd/config.ini", text: "image.sysdir.1=system-images/android-37.0/google_apis_playstore/arm64-v8a/\n");

        var expansion = new FolderRuleExpander(fixture.Folders).Expand(fixture.Rule("android.system-images"));
        Assert.Contains(expansion.Offered, path => path.Contains("android-35", StringComparison.Ordinal));
        Assert.DoesNotContain(expansion.Offered, path => path.Contains("android-37.0", StringComparison.Ordinal));
    }

    [Fact]
    public void UnreadableAvdConfigOffersNoImage()
    {
        using var fixture = new Fixture();
        fixture.MakeFile("home/AppData/Local/Android/Sdk/system-images/android-35/google_apis/arm64-v8a/system.img");
        fixture.MakeDirectory("home/.android/avd/Broken.avd");

        var expansion = new FolderRuleExpander(fixture.Folders).Expand(fixture.Rule("android.system-images"));
        Assert.Empty(expansion.Offered);
    }
}