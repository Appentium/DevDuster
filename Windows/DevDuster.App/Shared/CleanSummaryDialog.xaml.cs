using DevDuster.Core.Clean;
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
        InitializeComponent();
    }

    public string Headline { get; }
    public bool ShowRecycleNote { get; }
    public string FailuresHeader { get; }
    public IReadOnlyList<CleanResult> Failures { get; }
}
