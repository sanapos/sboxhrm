namespace ZKTecoADMS.Application.DTOs.Biometrics;

public class CopyBiometricsRequest
{
    public Guid SourceDeviceId { get; set; }
    public Guid TargetDeviceId { get; set; }

    /// <summary>Empty or null = every source user who has templates.</summary>
    public List<Guid>? SourceUserIds { get; set; }

    public bool IncludeFingerprints { get; set; } = true;
    public bool IncludeFaces { get; set; } = true;
}
