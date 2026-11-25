namespace DevDuster.Cli;

public static class FileSize
{
    private static readonly string[] Units = ["B", "KB", "MB", "GB", "TB", "PB"];

    public static string Size(this long bytes)
    {
        double value = bytes;
        var unit = 0;
        while (Math.Abs(value) >= 1000 && unit < Units.Length - 1)
        {
            value /= 1000;
            unit++;
        }
        return unit == 0 ? $"{bytes} B" : $"{value:0.##} {Units[unit]}";
    }
}