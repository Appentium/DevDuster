namespace DevDuster.Core.Scan;

public readonly record struct FileMeasure(long AllocatedBytes, string? HardLinkId);

public interface IFileMeasure
{
    FileMeasure Measure(FileInfo file);
}
