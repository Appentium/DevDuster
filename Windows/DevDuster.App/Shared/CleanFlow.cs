using DevDuster.Core.Clean;
using DevDuster.Core.Scan;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public static class CleanFlow
{
    public static async Task<IReadOnlyList<CleanResult>?> ExecuteAsync(
        AppServices services, XamlRoot? xamlRoot, IReadOnlyList<ScanItem> items, bool moveToRecycleBin = true, string? note = null)
    {
        if (items.Count == 0 || xamlRoot is null) return null;
        var confirm = new CleanConfirmDialog(items, moveToRecycleBin, note) { XamlRoot = xamlRoot };
        if (await confirm.ShowAsync() != ContentDialogResult.Primary) return null;
        var mode = confirm.MoveToRecycleBin ? CleanMode.Recycle : CleanMode.Delete;
        var results = await services.Cleaner.CleanAsync(items, mode, null, CancellationToken.None);
        services.NotifyHistoryChanged();
        var summary = new CleanSummaryDialog(results, mode) { XamlRoot = xamlRoot };
        await summary.ShowAsync();
        return results;
    }
}
