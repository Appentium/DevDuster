using DevDuster.Core.Clean;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public static class CleanFlow
{
    public static async Task<IReadOnlyList<CleanResult>?> ExecuteAsync(
        AppServices services, XamlRoot? xamlRoot, IReadOnlyList<ScanItem> items, bool moveToRecycleBin = true, string? note = null,
        CleanProgress? progress = null)
    {
        if (items.Count == 0 || xamlRoot is null) return null;
        if (await GradeAsync(services, xamlRoot, items) is not { } graded) return null;
        var (allowed, hasCritical, riskNote) = graded;
        // A leftover is an app's own data, so it is never deleted permanently.
        var recycleOnly = hasCritical || allowed.Any(item => item.Rule.Target is LeftoverTarget);
        var notes = string.Join('\n', new[] { note, riskNote }.Where(Ui.HasText));
        var confirm = new CleanConfirmDialog(allowed, moveToRecycleBin || recycleOnly, notes, recycleOnly) { XamlRoot = xamlRoot };
        if (await confirm.ShowAsync() != ContentDialogResult.Primary) return null;
        var mode = confirm.MoveToRecycleBin ? CleanMode.Recycle : CleanMode.Delete;
        IReadOnlyList<CleanResult> results;
        progress?.Begin(allowed);
        try
        {
            // Progress<T> posts back to the UI thread, so the page sees each item as it finishes.
            var reporter = progress is null ? null : new Progress<CleanResult>(progress.Report);
            results = await services.Cleaner.CleanAsync(allowed, mode, reporter, CancellationToken.None);
            // Let the last posted report land before the run is closed.
            await Task.Yield();
        }
        finally
        {
            progress?.End();
        }
        services.NotifyHistoryChanged();
        var summary = new CleanSummaryDialog(results, mode) { XamlRoot = xamlRoot };
        await summary.ShowAsync();
        return results;
    }

    // Only hand-picked items are graded; rule matches are already limited to their own patterns.
    private static async Task<(IReadOnlyList<ScanItem> Allowed, bool HasCritical, string Note)?> GradeAsync(
        AppServices services, XamlRoot xamlRoot, IReadOnlyList<ScanItem> items)
    {
        var risk = new DeleteRisk(services.Catalog, services.Processes);
        var graded = await Task.Run(() => items
            .Select(item => (Item: item, Assessment: item.Rule.Target is UserSelectedTarget ? risk.Assess(item.Path) : null))
            .ToList());
        var blocked = graded.Where(entry => entry.Assessment?.Level == RiskLevel.Blocked).ToList();
        if (blocked.Count > 0)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = xamlRoot,
                Title = "Some items can't be deleted",
                Content = new ScrollViewer
                {
                    Content = new TextBlock
                    {
                        Text = string.Join("\n\n", blocked.Select(entry => $"{entry.Item.Path}\n{string.Join(' ', entry.Assessment!.Reasons)}")),
                        TextWrapping = TextWrapping.Wrap,
                    },
                },
                CloseButtonText = "OK",
            };
            await dialog.ShowAsync();
            graded = [.. graded.Except(blocked)];
        }
        if (graded.Count == 0) return null;
        var critical = graded.Where(entry => entry.Assessment?.Level == RiskLevel.Critical).ToList();
        foreach (var entry in critical)
        {
            if (!await ConfirmCriticalAsync(xamlRoot, entry.Assessment!)) return null;
        }
        var review = graded.Where(entry => entry.Assessment?.Level == RiskLevel.Review)
            .SelectMany(entry => entry.Assessment!.Reasons).Distinct();
        return ([.. graded.Select(entry => entry.Item)], critical.Count > 0, string.Join('\n', review));
    }

    private static async Task<bool> ConfirmCriticalAsync(XamlRoot xamlRoot, DeleteAssessment assessment)
    {
        var typed = new TextBox { PlaceholderText = assessment.Name };
        var panel = new StackPanel { Spacing = 10, MinWidth = 460 };
        panel.Children.Add(new TextBlock { Text = assessment.Path, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        panel.Children.Add(new TextBlock { Text = string.Join('\n', assessment.Reasons), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = $"Type “{assessment.Name}” to continue. It will go to the Recycle Bin.", TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(typed);
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = "This holds important data",
            Content = panel,
            PrimaryButtonText = "Continue",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            IsPrimaryButtonEnabled = false,
        };
        typed.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = assessment.Confirms(typed.Text);
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
}
