using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.WorkSchedules;

public class WorkScheduleDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public Guid? ShiftId { get; set; }
    public string ShiftName { get; set; } = string.Empty;
    public TimeSpan ShiftStartTime { get; set; }
    public TimeSpan ShiftEndTime { get; set; }
    public DateTime Date { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public bool IsDayOff { get; set; }
    public string? Note { get; set; }
    public Guid? AssignedById { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreateWorkScheduleDto
{
    public Guid EmployeeUserId { get; set; }
    public Guid? ShiftId { get; set; }
    public DateTime Date { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public bool IsDayOff { get; set; }
    public string? Note { get; set; }
}

public class BulkCreateWorkScheduleDto
{
    public List<Guid> EmployeeUserIds { get; set; } = new();
    public Guid? ShiftId { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public List<DayOfWeek> WorkDays { get; set; } = new();
}

public class UpdateWorkScheduleDto
{
    public Guid? ShiftId { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public bool IsDayOff { get; set; }
    public string? Note { get; set; }
}

public class WorkScheduleQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public Guid? EmployeeUserId { get; set; }
    public Guid? ShiftId { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public bool? IsDayOff { get; set; }
}

// Schedule Registration DTOs
public class ScheduleRegistrationDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public Guid? ShiftId { get; set; }
    public string ShiftName { get; set; } = string.Empty;
    public bool IsDayOff { get; set; }
    public string? Note { get; set; }
    public ScheduleRegistrationStatus Status { get; set; }
    public Guid? ApprovedById { get; set; }
    public string? ApprovedByName { get; set; }
    public DateTime? ApprovedDate { get; set; }
    public string? RejectionReason { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreateScheduleRegistrationDto
{
    public Guid EmployeeUserId { get; set; }
    public DateTime Date { get; set; }
    public Guid? ShiftId { get; set; }
    public bool IsDayOff { get; set; }
    public string? Note { get; set; }
}

public class ApproveScheduleRegistrationDto
{
    public Guid RequestId { get; set; }
    public bool IsApproved { get; set; }
    public string? RejectionReason { get; set; }
}

public class ScheduleRegistrationQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public Guid? EmployeeUserId { get; set; }
    public ScheduleRegistrationStatus? Status { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
}

// Shift Staffing Quota DTOs
public class ShiftStaffingQuotaDto
{
    public Guid Id { get; set; }
    public Guid ShiftTemplateId { get; set; }
    public string ShiftName { get; set; } = string.Empty;
    public string? Department { get; set; }
    public int MinEmployees { get; set; }
    public int MaxEmployees { get; set; }
    public int WarningThreshold { get; set; }
}

public class UpsertShiftStaffingQuotaDto
{
    public Guid ShiftTemplateId { get; set; }
    public string? Department { get; set; }
    public int MinEmployees { get; set; } = 1;
    public int MaxEmployees { get; set; } = 10;
    public int WarningThreshold { get; set; } = 2;
}

/// <summary>
/// Gửi nhắc nhở đăng ký lịch cho nhân viên chưa đăng ký
/// </summary>
public class SendScheduleReminderDto
{
    public DateTime FromDate { get; set; }
    public DateTime ToDate { get; set; }
    public string? Department { get; set; }
}

/// <summary>
/// Yêu cầu nhân viên bổ sung ca cụ thể
/// </summary>
public class RequestShiftCoverageDto
{
    public Guid ShiftTemplateId { get; set; }
    public DateTime Date { get; set; }
    public string? Department { get; set; }
    public string? Message { get; set; }
}
