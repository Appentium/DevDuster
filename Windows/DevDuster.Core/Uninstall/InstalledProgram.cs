namespace DevDuster.Core.Uninstall;

public sealed record InstalledProgram(string Id, string Name, string Publisher, string Version, long Bytes, string? InstallLocation, string UninstallCommand);
