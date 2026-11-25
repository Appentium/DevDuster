using DevDuster.App.Shared;
using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using DevDuster.Core.Scan;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace DevDuster.App.DiskMap;

public sealed partial class DiskMapPage : Page
{
    private static readonly string[] PaletteKeys =
    [
        "AccentFillColorDefaultBrush",
        "SystemFillColorSuccessBrush",
        "SystemFillColorCautionBrush",
        "SystemFillColorAttentionBrush",
        "SystemAccentColorLight1",
        "SystemAccentColorDark1",
    ];

    public DiskMapPage()
    {
        ViewModel = new DiskMapViewModel(App.Current.Services);
        InitializeComponent();
        ViewModel.TreemapChanged += RenderTreemap;
    }

    public DiskMapViewModel ViewModel { get; }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel.ReloadLocations();
        await ViewModel.ScanIfNeededAsync();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.CancelScan();
    }

    private async void OnChooseFolderClicked(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is not { } window) return;
        var folder = await Ui.PickFolderAsync(window);
        if (folder is not null) ViewModel.SetCustomFolder(folder);
    }

    private void OnBreadcrumbClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: int index }) ViewModel.NavigateTo(index);
    }

    private void OnIncludeAgainClicked(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path }) ViewModel.IncludeAgain(path);
    }

    private void OnRevealSelectedClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedNode is { FoldedCount: 0 } node) Ui.RevealInExplorer(node.Path);
    }

    private async void OnDeleteSelectedClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedNode is { FoldedCount: 0 } node) await DeleteNodeAsync(node);
    }

    private void OnTreemapSizeChanged(object sender, SizeChangedEventArgs e) => RenderTreemap();

    private void RenderTreemap()
    {
        TreemapCanvas.Children.Clear();
        var width = TreemapCanvas.ActualWidth;
        var height = TreemapCanvas.ActualHeight;
        if (width < 2 || height < 2 || ViewModel.VisibleChildren.Count == 0) return;

        var tiles = TreemapLayout.Squarify(ViewModel.VisibleChildren, width, height);
        foreach (var tile in tiles)
        {
            var rect = tile.Rect;
            if (rect.Width < 1 || rect.Height < 1) continue;
            var node = tile.Node;
            var margin = rect.Width > 4 && rect.Height > 4 ? 1.0 : 0.0;
            var border = new Border
            {
                Width = Math.Max(1, rect.Width - margin * 2),
                Height = Math.Max(1, rect.Height - margin * 2),
                Background = TileBrush(node),
                BorderBrush = Ui.ResourceBrush("CardStrokeColorDefaultBrush"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(4),
                Opacity = 0.85,
            };

            var tip = node.FoldedCount > 0
                ? $"{node.Name}\n{ByteText.Format(node.Bytes)}"
                : $"{node.Name}\n{ByteText.Format(node.Bytes)}\n{node.Path}";
            ToolTipService.SetToolTip(border, tip);

            if (rect.Width > 54 && rect.Height > 24)
            {
                var stack = new StackPanel { Margin = new Thickness(6, 4, 6, 4), Spacing = 1 };
                stack.Children.Add(new TextBlock
                {
                    Text = node.Name,
                    FontSize = 12,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    Foreground = Ui.ResourceBrush("TextOnAccentFillColorPrimaryBrush"),
                });
                if (rect.Height > 42)
                {
                    stack.Children.Add(new TextBlock
                    {
                        Text = ByteText.Format(node.Bytes),
                        FontSize = 11,
                        Opacity = 0.9,
                        Foreground = Ui.ResourceBrush("TextOnAccentFillColorPrimaryBrush"),
                    });
                }
                border.Child = stack;
            }

            border.PointerEntered += (_, _) =>
            {
                border.Opacity = 1.0;
                ViewModel.SetHovered(node);
            };
            border.PointerExited += (_, _) =>
            {
                border.Opacity = 0.85;
                ViewModel.SetHovered(null);
            };
            border.Tapped += (_, _) =>
            {
                ViewModel.SelectedNode = node;
                if (node.IsDirectory && node.FoldedCount == 0) ViewModel.DrillInto(node);
            };

            if (node.FoldedCount == 0)
            {
                border.ContextFlyout = BuildTileMenu(node);
            }

            Canvas.SetLeft(border, rect.X + margin);
            Canvas.SetTop(border, rect.Y + margin);
            TreemapCanvas.Children.Add(border);
        }
    }

    private MenuFlyout BuildTileMenu(DiskNode node)
    {
        var menu = new MenuFlyout();
        if (node.IsDirectory)
        {
            var open = new MenuFlyoutItem { Text = "Open" };
            open.Click += (_, _) => ViewModel.DrillInto(node);
            menu.Items.Add(open);
        }
        var reveal = new MenuFlyoutItem { Text = "Reveal in Explorer" };
        reveal.Click += (_, _) => Ui.RevealInExplorer(node.Path);
        menu.Items.Add(reveal);
        if (node.IsDirectory)
        {
            var exclude = new MenuFlyoutItem { Text = "Exclude from Scans" };
            exclude.Click += (_, _) => ViewModel.Exclude(node);
            menu.Items.Add(exclude);
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        var delete = new MenuFlyoutItem { Text = "Delete..." };
        delete.Click += async (_, _) => await DeleteNodeAsync(node);
        menu.Items.Add(delete);
        return menu;
    }

    private async Task DeleteNodeAsync(DiskNode node)
    {
        if (node.FoldedCount > 0 || string.IsNullOrEmpty(node.Path)) return;
        var item = new ScanItem(RuleCatalog.UserSelected, node.Path, node.Bytes);
        var results = await CleanFlow.ExecuteAsync(App.Current.Services, XamlRoot, [item]);
        if (results is not null && results.Any(r => r.Succeeded))
        {
            ViewModel.RemoveNode(node);
        }
    }

    private static Brush TileBrush(DiskNode node)
    {
        if (node.FoldedCount > 0) return Ui.ResourceBrush("SystemFillColorNeutralBrush");
        var hash = node.Name.Aggregate(0, (acc, ch) => unchecked(acc * 31 + ch));
        var key = PaletteKeys[(hash & int.MaxValue) % PaletteKeys.Length];
        if (Application.Current.Resources.TryGetValue(key, out var value))
        {
            if (value is Brush brush) return brush;
            if (value is Color color) return new SolidColorBrush(color);
        }
        return Ui.ResourceBrush("AccentFillColorDefaultBrush");
    }
}
