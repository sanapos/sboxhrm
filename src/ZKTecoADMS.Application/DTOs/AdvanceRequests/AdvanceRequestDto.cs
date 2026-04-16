using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.AdvanceRequests;

public class AdvanceRequestDto
{
    public Guid Id { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string? Reason { get; set; }
    public DateTime RequestDate { get; set; }
    public AdvanceRequestStatus Status { get; set; }
    public Guid? ApprovedById { get; set; }
    public string? ApprovedByName { get; set; }
    public DateTime? ApprovedDate { get; set; }
    public string? RejectionReason { get; set; }
    public string? Note { get; set; }
    public bool IsPaid { get; set; }
    public string? PaymentMethod { get; set; }
    public DateTime? PaidDate { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    public int TotalApprovalLevels { get; set; }
    public int CurrentApprovalStep { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<AdvanceApprovalRecordDto> ApprovalRecords { get; set; } = [];
}

public class AdvanceApprovalRecordDto
{
    public Guid Id { get; set; }
    public int StepOrder { get; set; }
    public string? StepName { get; set; }
    public Guid? AssignedUserId { get; set; }
    public string? AssignedUserName { get; set; }
    public Guid? ActualUserId { get; set; }
    public string? ActualUserName { get; set; }
    public int Status { get; set; }
    public string? Note { get; set; }
    public DateTime? ActionDate { get; set; }
}

public class CreateAdvanceRequestDto
{
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public decimal Amount { get; set; }
    public string? Reason { get; set; }
    public string? Note { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
}

public class PayAdvanceRequestDto
{
    public string? PaymentMethod { get; set; }
}

public class ApproveAdvanceRequestDto
{
    public Guid RequestId { get; set; }
    public bool IsApproved { get; set; }
    public string? RejectionReason { get; set; }
}

public record BulkResultDto(int Success, int Failed);

public class BulkApproveDto
{
    public List<Guid> Ids { get; set; } = [];
}

public class BulkRejectDto
{
    public List<Guid> Ids { get; set; } = [];
    public string? Reason { get; set; }
}

public class BulkPayDto
{
    public List<Guid> Ids { get; set; } = [];
    public string? PaymentMethod { get; set; }
}

public class AdvanceRequestQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public Guid? EmployeeUserId { get; set; }
    public AdvanceRequestStatus? Status { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
}
