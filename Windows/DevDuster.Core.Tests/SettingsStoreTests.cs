using DevDuster.Core.Settings;
using Xunit;

namespace DevDuster.Core.Tests;

public sealed class SettingsStoreTests
{
    private static SettingsStore Store(Fixture fixture) => new(fixture.Folders);

    [Fact]
    public void SaveThenLoadRoundTrips()
    {
        using var fixture = new Fixture();
        var settings = new DusterSettings
        {
            StaleDays = 30,
            SystemThresholdGB = 50,
            OtherThresholdGB = 5,
            ScheduleHour = 7,
            ScheduleWeekday = DayOfWeek.Friday,
            Theme = AppThemeChoice.Dark,
            LowSpaceAlertsEnabled = false,
            ExcludedPaths = ["~/skip"],
        };

        Store(fixture).Save(settings);
        var loaded = Store(fixture).Load();

        Assert.Equal(30, loaded.StaleDays);
        Assert.Equal(50, loaded.SystemThresholdGB);
        Assert.Equal(5, loaded.OtherThresholdGB);
        Assert.Equal(7, loaded.ScheduleHour);
        Assert.Equal(DayOfWeek.Friday, loaded.ScheduleWeekday);
        Assert.Equal(AppThemeChoice.Dark, loaded.Theme);
        Assert.False(loaded.LowSpaceAlertsEnabled);
        Assert.Equal(new[] { "~/skip" }, loaded.ExcludedPaths);
    }

    [Fact]
    public void MissingFileGivesDefaults()
    {
        using var fixture = new Fixture();

        var loaded = Store(fixture).Load();

        Assert.Equal(14, loaded.StaleDays);
        Assert.Equal(20, loaded.SystemThresholdGB);
        Assert.Equal(10, loaded.OtherThresholdGB);
        Assert.Equal(3, loaded.ScheduleHour);
    }

    [Fact]
    public void CorruptJsonGivesDefaults()
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Folders.DusterData, "settings.json");
        Directory.CreateDirectory(fixture.Folders.DusterData);
        File.WriteAllText(path, "{ not json");

        var loaded = Store(fixture).Load();

        Assert.Equal(14, loaded.StaleDays);
    }

    [Fact]
    public void ValuesAreClamped()
    {
        using var fixture = new Fixture();
        var settings = new DusterSettings
        {
            StaleDays = 0,
            SystemThresholdGB = 0,
            OtherThresholdGB = -5,
            ScheduleHour = 99,
            ScheduleWeekday = (DayOfWeek)200,
        };

        Assert.Equal(1, settings.StaleDays);
        Assert.Equal(1, settings.SystemThresholdGB);
        Assert.Equal(1, settings.OtherThresholdGB);
        Assert.Equal(23, settings.ScheduleHour);
        Assert.Equal(DayOfWeek.Monday, settings.ScheduleWeekday);
    }
}