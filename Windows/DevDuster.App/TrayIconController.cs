using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using DevDuster.App.Shared;
using DevDuster.Core.Scan;
using H.NotifyIcon;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace DevDuster.App;

public sealed class TrayIconController : IDisposable
{
    private const int MaxToolTipLength = 127;

    private readonly AppServices _services;
    private readonly DispatcherQueue _dispatcher;
    private readonly ICommand _openCommand;
    private readonly ICommand _scanNowCommand;
    private readonly ICommand _quitCommand;
    private TaskbarIcon? _icon;
    private MenuFlyout? _menu;
    private MenuFlyoutSeparator? _topSeparator;
    private bool _disposed;

    public TrayIconController(AppServices services, DispatcherQueue dispatcher, Action openWindow, Action scanNow, Action quit)
    {
        _services = services;
        _dispatcher = dispatcher;
        _openCommand = new RelayCommand(openWindow);
        _scanNowCommand = new RelayCommand(scanNow);
        _quitCommand = new RelayCommand(quit);
        _services.TrayEnabledChanged += OnTrayEnabledChanged;
        if (_services.Settings.TrayEnabled) Enable();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _services.TrayEnabledChanged -= OnTrayEnabledChanged;
        Disable();
    }

    private void OnTrayEnabledChanged(bool enabled) =>
        _dispatcher.TryEnqueue(() =>
        {
            if (_disposed) return;
            if (enabled) Enable();
            else Disable();
        });

    private void Enable()
    {
        if (_icon is not null) return;

        _topSeparator = new MenuFlyoutSeparator();
        _menu = new MenuFlyout();
        _menu.Items.Add(_topSeparator);
        _menu.Items.Add(new MenuFlyoutItem { Text = "Open DevDuster", Command = _openCommand });
        _menu.Items.Add(new MenuFlyoutItem { Text = "Scan now", Command = _scanNowCommand });
        _menu.Items.Add(new MenuFlyoutSeparator());
        _menu.Items.Add(new MenuFlyoutItem { Text = "Quit", Command = _quitCommand });

        _icon = new TaskbarIcon
        {
            IconSource = new BitmapImage(new Uri("ms-appx:///Assets/Tray.ico")),
            LeftClickCommand = _openCommand,
            NoLeftClickDelay = true,
            // PopupMenu reads MenuFlyout.Items after PreviewTrayContextMenuOpen fires.
            ContextMenuMode = ContextMenuMode.PopupMenu,
            ContextFlyout = _menu,
        };
        _icon.PreviewTrayContextMenuOpen += (_, _) => RefreshDriveInfo();
        RefreshDriveInfo();
        _icon.ForceCreate(enablesEfficiencyMode: false);
    }

    private void Disable()
    {
        _icon?.Dispose();
        _icon = null;
        _menu = null;
        _topSeparator = null;
    }

    private void RefreshDriveInfo()
    {
        if (_icon is null || _menu is null || _topSeparator is null) return;

        var drives = _services.Drives.Drives();
        _icon.ToolTipText = BuildToolTip(drives);

        while (_menu.Items.Count > 0 && !ReferenceEquals(_menu.Items[0], _topSeparator))
        {
            _menu.Items.RemoveAt(0);
        }

        var insertAt = 0;
        if (drives.Count == 0)
        {
            _menu.Items.Insert(insertAt, new MenuFlyoutItem { Text = "No drives available", IsEnabled = false });
            return;
        }

        foreach (var drive in drives)
        {
            _menu.Items.Insert(insertAt++, new MenuFlyoutItem
            {
                Text = FormatDriveFree(drive),
                IsEnabled = false,
            });
        }
    }

    private static string FormatDriveFree(LocalDrive drive) =>
        $"{drive.Root.TrimEnd('\\')} {ByteText.Format(drive.AvailableBytes)} free";

    private static string BuildToolTip(IReadOnlyList<LocalDrive> drives)
    {
        if (drives.Count == 0) return "DevDuster";
        var summary = $"DevDuster — {string.Join(", ", drives.Select(FormatDriveFree))}";
        return summary.Length <= MaxToolTipLength ? summary : string.Concat(summary.AsSpan(0, MaxToolTipLength - 3), "...");
    }
}
