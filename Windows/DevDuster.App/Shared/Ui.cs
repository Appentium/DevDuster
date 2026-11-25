using System.Diagnostics;
using DevDuster.Core.Explore;
using DevDuster.Core.Rules;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace DevDuster.App.Shared;

public static class Ui
{
    public static Visibility Visible(bool value) => value ? Visibility.Visible : Visibility.Collapsed;

    public static Visibility Collapsed(bool value) => value ? Visibility.Collapsed : Visibility.Visible;

    public static Visibility VisibleWhenText(string? value) => string.IsNullOrWhiteSpace(value) ? Visibility.Collapsed : Visibility.Visible;

    public static bool HasText(string? value) => !string.IsNullOrWhiteSpace(value);

    public static Visibility VisibleWhenAny(int count) => count > 0 ? Visibility.Visible : Visibility.Collapsed;

    public static bool Not(bool value) => !value;

    public static string FormatBytes(long bytes) => ByteText.Format(bytes);

    public static string TierTitle(Tier tier) => tier switch
    {
        Tier.Safe => "Safe",
        Tier.Review => "Review",
        Tier.Caution => "Caution",
        _ => tier.ToString(),
    };

    public static Brush TierBrush(Tier tier) => ResourceBrush(tier switch
    {
        Tier.Safe => "SystemFillColorSuccessBrush",
        Tier.Review => "SystemFillColorCautionBrush",
        Tier.Caution => "SystemFillColorCriticalBrush",
        _ => "TextFillColorSecondaryBrush",
    });

    public static Brush TierBackgroundBrush(Tier tier) => ResourceBrush(tier switch
    {
        Tier.Safe => "SystemFillColorSuccessBackgroundBrush",
        Tier.Review => "SystemFillColorCautionBackgroundBrush",
        Tier.Caution => "SystemFillColorCriticalBackgroundBrush",
        _ => "SubtleFillColorSecondaryBrush",
    });

    public static Brush PartBrush(DevPartKind kind, Tier? tier) => kind switch
    {
        DevPartKind.Essential => ResourceBrush("AccentFillColorDefaultBrush"),
        DevPartKind.Cleanable when tier is { } t => TierBrush(t),
        _ => ResourceBrush("SystemFillColorNeutralBrush"),
    };

    public static Brush ResourceBrush(string key) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is Brush brush
            ? brush
            : (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];

    public static string PlatformLabel(RulePlatform platform) => platform switch
    {
        RulePlatform.DotNet => ".NET",
        RulePlatform.OtherLanguages => "Other Languages",
        RulePlatform.AiTools => "AI Tools",
        RulePlatform.AiModels => "AI Models",
        RulePlatform.GameEngines => "Game Engines",
        RulePlatform.DevTools => "Dev Tools",
        RulePlatform.Php => "PHP",
        RulePlatform.Jvm => "JVM",
        _ => platform.ToString(),
    };

    public static string RelativeTime(DateTime utc)
    {
        if (utc == DateTime.MinValue || utc == default) return "Unknown";
        var age = DateTime.UtcNow - utc;
        if (age.TotalMinutes < 1) return "Just now";
        if (age.TotalHours < 1) return $"{(int)age.TotalMinutes}m ago";
        if (age.TotalDays < 1) return $"{(int)age.TotalHours}h ago";
        if (age.TotalDays < 30) return $"{(int)age.TotalDays}d ago";
        if (age.TotalDays < 365) return $"{(int)(age.TotalDays / 30)}mo ago";
        return $"{(int)(age.TotalDays / 365)}y ago";
    }

    public static void RevealInExplorer(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        string argument;
        if (File.Exists(path) || Directory.Exists(path))
        {
            argument = $"/select,\"{path}\"";
        }
        else if (Path.GetDirectoryName(path) is { } parent && Directory.Exists(parent))
        {
            argument = $"\"{parent}\"";
        }
        else
        {
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", argument) { UseShellExecute = true })?.Dispose();
    }

    public static async Task<string?> PickFolderAsync(Window window)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.ComputerFolder,
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(window));
        var folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }
}
