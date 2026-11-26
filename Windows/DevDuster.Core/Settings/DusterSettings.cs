using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.Core.Settings;

public enum AppThemeChoice { System, Light, Dark }

public enum ScheduleFrequency { Daily, Weekly }

public sealed class DusterSettings
{
    private int _staleDays = 14;
    private int _systemThresholdGB = 20;
    private int _otherThresholdGB = 10;
    private int _scheduleHour = 3;
    private DayOfWeek _scheduleWeekday = DayOfWeek.Monday;

    public int StaleDays
    {
        get => _staleDays;
        set => _staleDays = Math.Max(value, 1);
    }

    public List<string> ExcludedPaths { get; set; } = [];
    public bool LowSpaceAlertsEnabled { get; set; } = true;

    public int SystemThresholdGB
    {
        get => _systemThresholdGB;
        set => _systemThresholdGB = Math.Max(value, 1);
    }

    public int OtherThresholdGB
    {
        get => _otherThresholdGB;
        set => _otherThresholdGB = Math.Max(value, 1);
    }

    public bool ScheduledCleanEnabled { get; set; }
    public ScheduleFrequency ScheduleFrequency { get; set; } = ScheduleFrequency.Daily;

    public DayOfWeek ScheduleWeekday
    {
        get => _scheduleWeekday;
        set => _scheduleWeekday = value is >= DayOfWeek.Sunday and <= DayOfWeek.Saturday ? value : DayOfWeek.Monday;
    }

    public int ScheduleHour
    {
        get => _scheduleHour;
        set => _scheduleHour = Math.Clamp(value, 0, 23);
    }

    public bool ScheduledCleanRecycles { get; set; } = true;
    public bool TrayEnabled { get; set; } = true;
    public AppThemeChoice Theme { get; set; } = AppThemeChoice.System;

    // Opt-in anonymous totals for the devduster.com counter; off until the user turns it on.
    public bool ShareStats { get; set; }
    public bool ShareStatsAsked { get; set; }
    public string? StatsInstallId { get; set; }
    public string? StatsPendingRemovalId { get; set; }
    public long? StatsLastSentBytes { get; set; }

    // Per tool, the folder its scans start from; "*" means everywhere. A tool missing here starts everywhere.
    public Dictionary<string, string> RememberedLocations { get; set; } = [];

    public ScanOptions ToScanOptions(IReadOnlySet<Tier>? tiers = null, IReadOnlyList<string>? scope = null) => new()
    {
        StaleDays = StaleDays,
        ExcludedPaths = ExcludedPaths,
        Tiers = tiers ?? Enum.GetValues<Tier>().ToHashSet(),
        Scope = scope,
    };
}
