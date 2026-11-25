using DevDuster.App.Shared;
using DevDuster.Core.Automation;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace DevDuster.App;

public sealed class LowSpaceAlerts
{
    private readonly AppServices _services;
    private readonly LowSpaceMonitor _monitor = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMinutes(5) };

    public LowSpaceAlerts(AppServices services)
    {
        _services = services;
        _timer.Tick += async (_, _) => await CheckAsync();
    }

    public void Start() => _timer.Start();

    private async Task CheckAsync()
    {
        var settings = _services.Settings;
        if (!settings.LowSpaceAlertsEnabled) return;
        var drives = await Task.Run(_services.Drives.Drives);
        foreach (var drive in _monitor.NewlyLow(drives, settings.SystemThresholdGB, settings.OtherThresholdGB))
        {
            var alert = new AppNotificationBuilder()
                .AddText($"{drive.Root} is low on space")
                .AddText($"{ByteText.Format(drive.AvailableBytes)} free. Open DevDuster to clean caches.");
            AppNotificationManager.Default.Show(alert.BuildNotification());
        }
    }
}
