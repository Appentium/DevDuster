using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.Shared;

public sealed partial class LocationPicker : UserControl
{
    public static readonly DependencyProperty LocationProperty =
        DependencyProperty.Register(nameof(Location), typeof(ScanLocation), typeof(LocationPicker), new PropertyMetadata(null));

    public LocationPicker()
    {
        InitializeComponent();
    }

    public ScanLocation Location
    {
        get => (ScanLocation)GetValue(LocationProperty);
        set => SetValue(LocationProperty, value);
    }

    private async void OnChooseFolderClicked(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is not { } window || Location is null) return;
        if (await Ui.PickFolderAsync(window) is { } folder) Location.SetCustomFolder(folder);
    }
}
