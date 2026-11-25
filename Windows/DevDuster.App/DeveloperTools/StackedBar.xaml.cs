using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DevDuster.App.DeveloperTools;

public sealed partial class StackedBar : UserControl
{
    public static readonly DependencyProperty PartsProperty =
        DependencyProperty.Register(nameof(Parts), typeof(IReadOnlyList<DevPartViewModel>), typeof(StackedBar), new PropertyMetadata(null, OnPartsChanged));

    public StackedBar()
    {
        InitializeComponent();
    }

    public IReadOnlyList<DevPartViewModel>? Parts
    {
        get => (IReadOnlyList<DevPartViewModel>?)GetValue(PartsProperty);
        set => SetValue(PartsProperty, value);
    }

    private static void OnPartsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is StackedBar bar) bar.Rebuild();
    }

    private void Rebuild()
    {
        BarGrid.Children.Clear();
        BarGrid.ColumnDefinitions.Clear();
        if (Parts is not { Count: > 0 } parts) return;
        for (var i = 0; i < parts.Count; i++)
        {
            var part = parts[i];
            if (part.Bytes <= 0) continue;
            BarGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(1, part.Bytes), GridUnitType.Star) });
            var segment = new Border
            {
                Background = part.Brush,
                CornerRadius = new CornerRadius(2),
            };
            ToolTipService.SetToolTip(segment, $"{part.Title}: {part.SizeText} ({part.KindLabel})");
            Grid.SetColumn(segment, BarGrid.ColumnDefinitions.Count - 1);
            BarGrid.Children.Add(segment);
        }
    }
}
