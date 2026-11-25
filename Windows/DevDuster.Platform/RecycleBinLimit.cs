using System.Text;
using DevDuster.Core.Scan;
using Microsoft.Win32;

namespace DevDuster.Platform;

// Windows deletes an item for good when it does not fit the bin, and tells no progress sink beforehand.
internal static class RecycleBinLimit
{
    private const string BitBucket = @"Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket";
    private const string Policies = @"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer";
    private const int MaxPath = 260;

    public static bool CanHold(string path)
    {
        if (IsTurnedOffByPolicy() || CapacityFor(path) is not { } capacity) return false;
        return Fits(path, capacity);
    }

    private static bool IsTurnedOffByPolicy() =>
        IsOn(Registry.CurrentUser, Policies, "NoRecycleFiles") || IsOn(Registry.LocalMachine, Policies, "NoRecycleFiles");

    private static bool IsOn(RegistryKey hive, string key, string value)
    {
        using var opened = hive.OpenSubKey(key);
        return opened?.GetValue(value) is int number && number != 0;
    }

    // A drive whose bin Windows has not set up, or one set to delete at once, counts as having none.
    private static long? CapacityFor(string path)
    {
        var mount = new StringBuilder(MaxPath);
        if (!NativeMethods.GetVolumePathName(path, mount, mount.Capacity)) return null;
        var name = new StringBuilder(MaxPath);
        if (!NativeMethods.GetVolumeName(mount.ToString(), name, name.Capacity)) return null;
        var start = name.ToString().IndexOf('{');
        var end = name.ToString().IndexOf('}');
        if (start < 0 || end < start) return null;
        using var key = Registry.CurrentUser.OpenSubKey($@"{BitBucket}\Volume\{name.ToString(start, end - start + 1)}");
        if (key?.GetValue("MaxCapacity") is not int megabytes) return null;
        if (key.GetValue("NukeOnDelete") is int nuke && nuke != 0) return null;
        return (long)(uint)megabytes << 20;
    }

    // Windows compares file lengths, not allocated size, so sparse and compressed files count in full.
    private static bool Fits(string path, long capacity)
    {
        var info = new FileInfo(path);
        if (!info.Attributes.HasFlag(FileAttributes.Directory) || info.Attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            return info.Attributes.HasFlag(FileAttributes.ReparsePoint) || info.Length < capacity;
        }
        long total = 0;
        var pending = new Stack<string>([path]);
        while (pending.TryPop(out var folder))
        {
            if (PathTools.TryChildren(folder) is not { } children) return false;
            foreach (var child in children)
            {
                if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (child is FileInfo file) total += file.Length;
                else pending.Push(child.FullName);
                if (total >= capacity) return false;
            }
        }
        return true;
    }
}
