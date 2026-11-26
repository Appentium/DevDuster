using DevDuster.Core.Clean;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public sealed partial class CleanSummaryDialog : ContentDialog
{
    public CleanSummaryDialog(IReadOnlyList<CleanResult> results, CleanMode mode)
    {
        var freed = results.Sum(result => result.FreedBytes);
        var succeeded = results.Count(result => result.Succeeded);
        Failures = [.. results.Where(result => !result.Succeeded)];
        var verb = mode == CleanMode.Recycle ? "Moved to Recycle Bin" : "Deleted";
        Headline = $"{verb}: {ByteText.Format(freed)} ({succeeded} item(s))";
        ShowRecycleNote = mode == CleanMode.Recycle && succeeded > 0;
        FailuresHeader = $"Failures ({Failures.Count})";
        var services = App.Current.Services;
        ShowSharePrompt = succeeded > 0 && services.Settings.ShareStats && !services.Settings.ShareStatsAsked;
        InitializeComponent();
        if (!ShowSharePrompt) return;
        services.Settings.ShareStatsAsked = true;
        services.SettingsStore.Save(services.Settings);
        services.SyncStats();
    }

    public string Headline { get; }
    public bool ShowRecycleNote { get; }
    public string FailuresHeader { get; }
    public IReadOnlyList<CleanResult> Failures { get; }
    public bool ShowSharePrompt { get; }

    private void OnTurnOffShareClicked(object sender, RoutedEventArgs e)
    {
        var services = App.Current.Services;
        services.Stats.Disable();
        services.SyncStats();
        SharePrompt.Visibility = Visibility.Collapsed;
    }

    private void OnDismissShareNoticeClicked(object sender, RoutedEventArgs e)
    {
        SharePrompt.Visibility = Visibility.Collapsed;
    }
}
