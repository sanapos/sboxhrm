using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.AttendanceCorrections;

public class AttendanceCorrectionRequestDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public Guid? AttendanceId { get; set; }
    public CorrectionAction Action { get; set; }
    public DateTime? OldDate { get; set; }
    public TimeSpan? OldTime { get; set; }
    public string? OldDevice { get; set; }
    public string? OldType { get; set; }
    public DateTime? NewDate { get; set; }
    public TimeSpan? NewTime { get; set; }
    public string? Reason { get; set; }
    public CorrectionStatus Status { get; set; }
    public Guid? ApprovedById { get; set; }
    public string? ApprovedByName { get; set; }
    public DateTime? ApprovedDate { get; set; }
    public string? ApproverNote { get; set; }
    public int TotalApprovalLevels { get; set; } = 1;
    public int CurrentApprovalStep { get; set; } = 0;
    public List<ApprovalRecordDto> ApprovalRecords { get; set; } = new();
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class ApprovalRecordDto
{
    public Guid Id { get; set; }
    public int StepOrder { get; set; }
    public string? StepName { get; set; }
    public Guid? AssignedUserId { get; set; }
    public string? AssignedUserName { get; set; }
    public Guid? ActualUserId { get; set; }
    public string? ActualUserName { get; set; }
    public ApprovalStatus Status { get; set; }
    public string? Note { get; set; }
    public DateTime? ActionDate { get; set; }
}

public class CreateAttendanceCorrectionDto
{
    public Guid? EmployeeUserId { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeCode { get; set; }
    public Guid? AttendanceId { get; set; }
    public CorrectionAction Action { get; set; }
    public DateTime? OldDate { get; set; }
    public TimeSpan? OldTime { get; set; }
    public DateTime? NewDate { get; set; }
    public TimeSpan? NewTime { get; set; }
    public string? Reason { get; set; }
}

public class ApproveAttendanceCorrectionDto
{
    public Guid RequestId { get; set; }
    public bool IsApproved { get; set; }
    public string? ApproverNote { get; set; }
}

public class AttendanceCorrectionQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public Guid? EmployeeUserId { get; set; }
    public CorrectionStatus? Status { get; set; }
    public CorrectionAction? Action { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
}
