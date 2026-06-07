using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Leaves;

// LeavePaymentSource, SickLeaveMode in Domain.Enums

public class LeaveDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public LeaveType Type { get; set; }
    public Guid ShiftId { get; set; }
    public string? ShiftName { get; set; }
    public List<Guid> ShiftIds { get; set; } = [];
    public List<string> ShiftNames { get; set; } = [];
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsHalfShift { get; set; }
    public string Reason { get; set; } = string.Empty;
    public LeaveStatus Status { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? RejectionReason { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? ReplacementEmployeeName { get; set; }
    public Guid? ReplacementEmployeeId { get; set; }
    public int TotalApprovalLevels { get; set; } = 1;
    public int CurrentApprovalStep { get; set; } = 0;
    public bool CountAsWork { get; set; }
    public LeavePaymentSource PaymentSource { get; set; }
    public SickLeaveMode SickLeaveMode { get; set; }
    public string? BhxhDocumentNote { get; set; }
    public string? PaymentSourceLabel { get; set; }
    public decimal AnnualLeaveDaysDeducted { get; set; }
    public bool AnnualBalanceApplied { get; set; }
    public decimal? RemainingAnnualLeaveDays { get; set; }
    public List<LeaveApprovalRecordDto> ApprovalRecords { get; set; } = new();
}

public class LeaveApprovalRecordDto
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
