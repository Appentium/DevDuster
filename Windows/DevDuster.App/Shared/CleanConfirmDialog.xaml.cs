using DevDuster.Core.Scan;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public sealed partial class CleanConfirmDialog : ContentDialog
{
    public CleanConfirmDialog(IReadOnlyList<ScanItem> items, bool moveToRecycleBin = true, string? note = null, bool recycleOnly = false)
    {
        Items = items;
        Note = note;
        TotalBytes = items.Sum(item => item.Bytes);
        InitializeComponent();
        RecycleCheckBox.IsChecked = moveToRecycleBin;
        RecycleCheckBox.IsEnabled = !recycleOnly;
        UpdateMode();
    }

    public IReadOnlyList<ScanItem> Items { get; }
    public long TotalBytes { get; }
    public string? Note { get; }
    public bool MoveToRecycleBin => RecycleCheckBox.IsChecked == true;
    public string SummaryLine => $"{Items.Count} item(s) · {ByteText.Format(TotalBytes)}";

    private void OnRecycleChanged(object sender, RoutedEventArgs e) => UpdateMode();

    private void UpdateMode()
    {
        var recycle = MoveToRecycleBin;
        Title = recycle ? $"Move {Items.Count} item(s) to Recycle Bin?" : $"Permanently delete {Items.Count} item(s)?";
        PrimaryButtonText = recycle ? "Move to Recycle Bin" : "Delete Permanently";
        PermanentWarning.Visibility = recycle ? Visibility.Collapsed : Visibility.Visible;
    }
}
