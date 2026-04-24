namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

public class MaintenanceWindowDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime StartAt { get; set; }
    public DateTime EndAt { get; set; }
    public List<string>? AffectedModules { get; set; }
    public bool IsActive { get; set; }
    public bool BlockAccess { get; set; }
    public List<int>? NotifyBeforeMinutes { get; set; }
    public bool StartNotified { get; set; }
    public bool EndNotified { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateMaintenanceWindowDto
{
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime StartAt { get; set; }
    public DateTime EndAt { get; set; }
    public List<string>? AffectedModules { get; set; }
    public bool IsActive { get; set; } = true;
    public bool BlockAccess { get; set; } = true;
    /// <summary>Phát thông báo nhắc nhở trước N phút (mặc định: 60, 15, 5).</summary>
    public List<int>? NotifyBeforeMinutes { get; set; }
}

/// <summary>Trạng thái bảo trì hiện tại – endpoint public dùng cho client banner.</summary>
public class ActiveMaintenanceDto
{
    public bool InMaintenance { get; set; }
    public Guid? Id { get; set; }
    public string? Title { get; set; }
    public string? Message { get; set; }
    public DateTime? StartAt { get; set; }
    public DateTime? EndAt { get; set; }
    public bool BlockAccess { get; set; }
    public List<string>? AffectedModules { get; set; }
}
