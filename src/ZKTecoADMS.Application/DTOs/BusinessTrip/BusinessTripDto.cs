namespace ZKTecoADMS.Application.DTOs.BusinessTrip;

public class BusinessTripCaseDto
{
    public Guid Id { get; set; }
    public string CaseCode { get; set; } = string.Empty;
    public Guid? EmployeeId { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Destination { get; set; }
    public DateTime? TripFromDate { get; set; }
    public DateTime? TripToDate { get; set; }
    public string? Note { get; set; }
    /// <summary>Int enum value (avoid JSON string enum breaking Flutter).</summary>
    public int Status { get; set; }
    public decimal AdvanceAmount { get; set; }
    public decimal SettledAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public BusinessTripAdvanceClaimDto? Advance { get; set; }
    public BusinessTripSettlementClaimDto? Settlement { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class BusinessTripAdvanceClaimDto
{
    public Guid Id { get; set; }
    public Guid CaseId { get; set; }
    public decimal Amount { get; set; }
    public string Reason { get; set; } = string.Empty;
    public string? Note { get; set; }
    public DateTime RequestDate { get; set; }
    public int Status { get; set; }
    public bool IsPaid { get; set; }
    public string? PaymentMethod { get; set; }
    public DateTime? PaidDate { get; set; }
    public Guid? CashTransactionId { get; set; }
    public string? RejectionReason { get; set; }
    public int TotalApprovalLevels { get; set; }
    public int CurrentApprovalStep { get; set; }
    public List<BusinessTripApprovalRecordDto> ApprovalRecords { get; set; } = [];
}

public class BusinessTripSettlementClaimDto
{
    public Guid Id { get; set; }
    public Guid CaseId { get; set; }
    public decimal AdvanceAmount { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal TotalWithInvoice { get; set; }
    public decimal TotalWithoutInvoice { get; set; }
    public decimal BalanceAmount { get; set; }
    public int SettlementType { get; set; }
    public string? Note { get; set; }
    public int Status { get; set; }
    public bool IsExtraPaid { get; set; }
    public string? ExtraPaymentMethod { get; set; }
    public DateTime? ExtraPaidDate { get; set; }
    public Guid? ExtraCashTransactionId { get; set; }
    public Guid? SurplusPaymentTransactionId { get; set; }
    public Guid? SurplusAdvanceRequestId { get; set; }
    public string? RejectionReason { get; set; }
    public int TotalApprovalLevels { get; set; }
    public int CurrentApprovalStep { get; set; }
    public List<BusinessTripExpenseLineDto> Lines { get; set; } = [];
    public List<BusinessTripApprovalRecordDto> ApprovalRecords { get; set; } = [];
}

public class BusinessTripApprovalRecordDto
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

public class BusinessTripExpenseLineDto
{
    public Guid Id { get; set; }
    public Guid? CategoryId { get; set; }
    public string? CategoryName { get; set; }
    public DateTime ExpenseDate { get; set; }
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? Note { get; set; }
    public bool HasInvoice { get; set; }
    public string? InvoiceNumber { get; set; }
    public DateTime? InvoiceDate { get; set; }
    public int SortOrder { get; set; }
    public List<BusinessTripExpenseAttachmentDto> Attachments { get; set; } = [];
}

public class BusinessTripExpenseAttachmentDto
{
    public Guid Id { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public long? FileSize { get; set; }
    public int AttachmentType { get; set; }
}

public class BusinessTripExpenseCategoryDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public decimal? MaxAmountPerLine { get; set; }
    public decimal? MaxAmountPerMonth { get; set; }
    public bool RequiresInvoice { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
}

public class UpdateBusinessTripCaseDto
{
    public string Title { get; set; } = string.Empty;
    public string? Destination { get; set; }
    public DateTime? TripFromDate { get; set; }
    public DateTime? TripToDate { get; set; }
    public string? Note { get; set; }
}

public class CreateBusinessTripCaseDto
{
    public Guid? EmployeeId { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Destination { get; set; }
    public DateTime? TripFromDate { get; set; }
    public DateTime? TripToDate { get; set; }
    public string? Note { get; set; }
}

public class CreateBusinessTripAdvanceDto
{
    public decimal Amount { get; set; }
    public string? Reason { get; set; }
    public string? Note { get; set; }
}

public class UpsertBusinessTripExpenseLineDto
{
    public Guid? Id { get; set; }
    public Guid? CategoryId { get; set; }
    public DateTime ExpenseDate { get; set; }
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? Note { get; set; }
    public bool HasInvoice { get; set; }
    public string? InvoiceNumber { get; set; }
    public DateTime? InvoiceDate { get; set; }
    public int SortOrder { get; set; }
    public List<BusinessTripExpenseAttachmentDto>? Attachments { get; set; }
}

public class SaveBusinessTripSettlementDto
{
    public string? Note { get; set; }
    public List<UpsertBusinessTripExpenseLineDto> Lines { get; set; } = [];
}

public class ApproveBusinessTripDto
{
    public bool IsApproved { get; set; }
    public string? RejectionReason { get; set; }
    /// <summary>
    /// Khi HT dư tiền: true = thu hoàn tiền mặt (Income); false/null = ghi nợ ứng lương.
    /// </summary>
    public bool SurplusAsCashRefund { get; set; }
}

public class PayBusinessTripDto
{
    public string? PaymentMethod { get; set; }
}

public class ConfirmSurplusDto
{
    /// <summary>true = ghi nợ ứng lương; false = thu hoàn ứng tiền mặt.</summary>
    public bool AsAdvanceDebt { get; set; } = true;
    public string? PaymentMethod { get; set; }
}

public class UpsertBusinessTripExpenseCategoryDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public decimal? MaxAmountPerLine { get; set; }
    public decimal? MaxAmountPerMonth { get; set; }
    public bool RequiresInvoice { get; set; }
    public int SortOrder { get; set; }
}
