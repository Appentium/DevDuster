namespace DevDuster.Core.Scan;

public interface IProcessProbe
{
    IReadOnlySet<string> RunningNames();
}
