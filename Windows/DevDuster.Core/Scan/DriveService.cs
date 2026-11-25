namespace DevDuster.Core.Scan;

public sealed record LocalDrive(string Root, string Label, string Format, long TotalBytes, long AvailableBytes, bool IsSystem, bool IsRemovable)
{
    public bool CanHoldMovedTools => Format is "NTFS" or "ReFS";
    public long UsedBytes => TotalBytes - AvailableBytes;
}

public class DriveService
{
    public virtual IReadOnlyList<LocalDrive> Drives()
    {
        var systemRoot = Path.GetPathRoot(Environment.SystemDirectory);
        var drives = new List<LocalDrive>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (!drive.IsReady || drive.DriveType is not (DriveType.Fixed or DriveType.Removable)) continue;
                drives.Add(new LocalDrive(
                    drive.RootDirectory.FullName, drive.VolumeLabel, drive.DriveFormat, drive.TotalSize, drive.AvailableFreeSpace,
                    string.Equals(drive.RootDirectory.FullName, systemRoot, PathTools.Comparison), drive.DriveType == DriveType.Removable));
            }
            catch (Exception error) when (PathTools.IsFileError(error)) { continue; }
        }
        return drives;
    }

    public LocalDrive? DriveOf(string path) =>
        Drives().Where(drive => PathTools.IsSameOrInside(path, drive.Root)).MaxBy(drive => drive.Root.Length);
}
