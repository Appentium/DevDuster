using CommunityToolkit.Mvvm.ComponentModel;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;

namespace DevDuster.App.Shared;

public sealed partial class SelectableItem : ObservableObject
{
    public SelectableItem(ScanItem item, bool isSelected = false)
    {
        Item = item;
        IsSelected = isSelected;
    }

    public ScanItem Item { get; }
    public string Name => Item.Name;
    public string Path => Item.Path;
    public long Bytes => Item.Bytes;
    public string SizeText => ByteText.Format(Item.Bytes);
    public string RuleTitle => Item.Rule.Title;
    public Tier Tier => Item.Rule.Tier;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsChecked))]
    public partial bool IsSelected { get; set; }

    public bool? IsChecked
    {
        get => IsSelected;
        set
        {
            if (value is { } selected && selected != IsSelected) IsSelected = selected;
        }
    }
}
