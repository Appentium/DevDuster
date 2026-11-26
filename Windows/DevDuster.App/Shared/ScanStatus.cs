using CommunityToolkit.Mvvm.ComponentModel;

namespace DevDuster.App.Shared;

// What the progress strip shows while a page scans.
public sealed partial class ScanStatus : ObservableObject
{
    [ObservableProperty]
    public partial string Text { get; set; } = "";

    [ObservableProperty]
    public partial string FoundText { get; set; } = "";

    // 0 to 100; HasValue stays false until the scan knows how much work there is.
    [ObservableProperty]
    public partial double Value { get; set; }

    [ObservableProperty]
    public partial bool HasValue { get; set; }

    public void Reset(string text)
    {
        Text = text;
        FoundText = "";
        Value = 0;
        HasValue = false;
    }

    public void Update(string? text, double? fraction)
    {
        if (text is not null) Text = text;
        if (fraction is not { } value) return;
        // Parallel work can report slightly out of order; the bar never moves back.
        Value = Math.Max(Value, Math.Round(value * 100, 1));
        HasValue = true;
    }

    public void SetFound(int count, long bytes, string noun = "item(s)") =>
        FoundText = count == 0 ? "" : $"Found {count:N0} {noun}, {ByteText.Format(bytes)}";
}
