using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using DevDuster.Core.Scan;
using DevDuster.Core.Settings;

namespace DevDuster.App.Settings;

public sealed partial class SettingsViewModel : ObservableObject
{
    private static readonly DayOfWeek[] Weekdays =
    [
        DayOfWeek.Monday,
        DayOfWeek.Tuesday,
        DayOfWeek.Wednesday,
        DayOfWeek.Thursday,
        DayOfWeek.Friday,
        DayOfWeek.Saturday,
        DayOfWeek.Sunday,
    ];

    private readonly AppServices _services;
    private readonly bool _initialized;

    public SettingsViewModel(AppServices services)
    {
        _services = services;
        var s = services.Settings;
        SelectedThemeIndex = (int)s.Theme;
        StaleDaysValue = s.StaleDays;
        ExcludedPaths = new ObservableCollection<string>(s.ExcludedPaths);
        HasExcluded = ExcludedPaths.Count > 0;
        LowSpaceAlertsEnabled = s.LowSpaceAlertsEnabled;
        SystemThresholdGB = s.SystemThresholdGB;
        OtherThresholdGB = s.OtherThresholdGB;
        ScheduledCleanEnabled = s.ScheduledCleanEnabled;
        SelectedFrequencyIndex = s.ScheduleFrequency == ScheduleFrequency.Weekly ? 1 : 0;
        IsWeekly = s.ScheduleFrequency == ScheduleFrequency.Weekly;
        var dayIdx = Array.IndexOf(Weekdays, s.ScheduleWeekday);
        SelectedWeekdayIndex = dayIdx < 0 ? 0 : dayIdx;
        SelectedHourIndex = Math.Clamp(s.ScheduleHour, 0, 23);
        ScheduledCleanRecycles = s.ScheduledCleanRecycles;
        TrayEnabled = s.TrayEnabled;
        Hours = [.. Enumerable.Range(0, 24).Select(h => $"{h:00}:00")];
        _initialized = true;
    }

    public IReadOnlyList<string> Hours { get; }
    public ObservableCollection<string> ExcludedPaths { get; }

    [ObservableProperty]
    public partial int SelectedThemeIndex { get; set; }

    [ObservableProperty]
    public partial double StaleDaysValue { get; set; }

    [ObservableProperty]
    public partial bool LowSpaceAlertsEnabled { get; set; }

    [ObservableProperty]
    public partial double SystemThresholdGB { get; set; }

    [ObservableProperty]
    public partial double OtherThresholdGB { get; set; }

    [ObservableProperty]
    public partial bool ScheduledCleanEnabled { get; set; }

    [ObservableProperty]
    public partial int SelectedFrequencyIndex { get; set; }

    [ObservableProperty]
    public partial bool IsWeekly { get; set; }

    [ObservableProperty]
    public partial int SelectedWeekdayIndex { get; set; }

    [ObservableProperty]
    public partial int SelectedHourIndex { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ScheduledCleanRecyclesCheck))]
    public partial bool ScheduledCleanRecycles { get; set; }

    public bool? ScheduledCleanRecyclesCheck
    {
        get => ScheduledCleanRecycles;
        set
        {
            if (value is { } recycles && recycles != ScheduledCleanRecycles) ScheduledCleanRecycles = recycles;
        }
    }

    [ObservableProperty]
    public partial bool HasExcluded { get; set; }

    [ObservableProperty]
    public partial string? ScheduleError { get; set; }

    [ObservableProperty]
    public partial bool TrayEnabled { get; set; }

    partial void OnTrayEnabledChanged(bool value)
    {
        if (!_initialized) return;
        _services.ApplyTrayEnabled(value);
    }

    partial void OnSelectedThemeIndexChanged(int value)
    {
        if (!_initialized) return;
        var choice = Enum.IsDefined(typeof(AppThemeChoice), value) ? (AppThemeChoice)value : AppThemeChoice.System;
        _services.ApplyTheme(choice);
    }

    partial void OnStaleDaysValueChanged(double value)
    {
        if (!_initialized || double.IsNaN(value)) return;
        _services.Settings.StaleDays = (int)Math.Round(value);
        _services.SettingsStore.Save(_services.Settings);
    }

    partial void OnLowSpaceAlertsEnabledChanged(bool value) => SaveLowSpace();
    partial void OnSystemThresholdGBChanged(double value) => SaveLowSpace();
    partial void OnOtherThresholdGBChanged(double value) => SaveLowSpace();

    partial void OnScheduledCleanEnabledChanged(bool value) => SaveAndApplySchedule();

    partial void OnSelectedFrequencyIndexChanged(int value)
    {
        IsWeekly = value == 1;
        SaveAndApplySchedule();
    }

    partial void OnSelectedWeekdayIndexChanged(int value) => SaveAndApplySchedule();
    partial void OnSelectedHourIndexChanged(int value) => SaveAndApplySchedule();
    partial void OnScheduledCleanRecyclesChanged(bool value) => SaveAndApplySchedule();

    public void AddExcludedPath(string path)
    {
        if (ExcludedPaths.Contains(path, PathTools.Comparer)) return;
        ExcludedPaths.Add(path);
        HasExcluded = ExcludedPaths.Count > 0;
        _services.Settings.ExcludedPaths = [.. ExcludedPaths];
        _services.SettingsStore.Save(_services.Settings);
    }

    public void RemoveExcludedPath(string path)
    {
        if (!ExcludedPaths.Remove(path)) return;
        HasExcluded = ExcludedPaths.Count > 0;
        _services.Settings.ExcludedPaths = [.. ExcludedPaths];
        _services.SettingsStore.Save(_services.Settings);
    }

    private void SaveLowSpace()
    {
        if (!_initialized) return;
        _services.Settings.LowSpaceAlertsEnabled = LowSpaceAlertsEnabled;
        if (!double.IsNaN(SystemThresholdGB)) _services.Settings.SystemThresholdGB = (int)Math.Round(SystemThresholdGB);
        if (!double.IsNaN(OtherThresholdGB)) _services.Settings.OtherThresholdGB = (int)Math.Round(OtherThresholdGB);
        _services.SettingsStore.Save(_services.Settings);
    }

    private void SaveAndApplySchedule()
    {
        if (!_initialized) return;
        var settings = _services.Settings;
        settings.ScheduledCleanEnabled = ScheduledCleanEnabled;
        settings.ScheduleFrequency = SelectedFrequencyIndex == 1 ? ScheduleFrequency.Weekly : ScheduleFrequency.Daily;
        settings.ScheduleWeekday = Weekdays[Math.Clamp(SelectedWeekdayIndex, 0, Weekdays.Length - 1)];
        settings.ScheduleHour = Math.Clamp(SelectedHourIndex, 0, 23);
        settings.ScheduledCleanRecycles = ScheduledCleanRecycles;
        _services.SettingsStore.Save(settings);
        _ = ApplySchedulerAsync(settings);
    }

    private async Task ApplySchedulerAsync(DusterSettings settings)
    {
        try
        {
            // The package folder changes with every update; the execution alias does not.
            var cliPath = Path.Combine(_services.Folders.LocalAppData, "Microsoft", "WindowsApps", "duster.exe");
            await Task.Run(() => _services.CleanScheduler.Apply(settings, cliPath));
            ScheduleError = null;
        }
        catch (Exception error)
        {
            ScheduleError = error.Message;
        }
    }
}
