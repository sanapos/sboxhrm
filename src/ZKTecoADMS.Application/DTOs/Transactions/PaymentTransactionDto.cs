namespace ZKTecoADMS.Application.DTOs.Transactions;

public class PaymentTransactionDto
{
    public Guid Id { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    public DateTime TransactionDate { get; set; }
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? PaymentMethod { get; set; }
    public string Status { get; set; } = "Pending";
    public Guid? PerformedById { get; set; }
    public string? Note { get; set; }
    public Guid? AdvanceRequestId { get; set; }
    public Guid? PayslipId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class CreatePaymentTransactionDto
{
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public string Type { get; set; } = string.Empty;
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    public DateTime TransactionDate { get; set; }
    public decimal Amount { get; set; }
    public string? Description { get; set; }
    public string? PaymentMethod { get; set; }
    public string? Note { get; set; }
    public Guid? AdvanceRequestId { get; set; }
    public Guid? PayslipId { get; set; }
}

public class PaymentTransactionQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public Guid? EmployeeUserId { get; set; }
    public string? Type { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public string? SearchTerm { get; set; }
}

public class PaymentSummaryDto
{
    public int Month { get; set; }
    public int Year { get; set; }
    public decimal TotalIncome { get; set; }
    public decimal TotalExpense { get; set; }
    public decimal Balance { get; set; }
    public int TotalTransactions { get; set; }
    public int EmployeesPaid { get; set; }
    public decimal TotalAdvancePaid { get; set; }
}

public class EmployeePaymentSummaryDto
{
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public decimal TotalSalaryPaid { get; set; }
    public decimal TotalAdvancePaid { get; set; }
    public decimal TotalDeductions { get; set; }
    public decimal NetPaid { get; set; }
    public List<PaymentTransactionDto> Transactions { get; set; } = new();
}

public class UpdateTransactionStatusDto
{
    public string Status { get; set; } = "Pending";
}

public class UpdatePaymentTransactionDto
{
    public string? Type { get; set; }
    public decimal? Amount { get; set; }
    public string? Description { get; set; }
    public string? Note { get; set; }
    public DateTime? TransactionDate { get; set; }
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
}

public class BulkTransactionApproveDto
{
    public List<Guid> Ids { get; set; } = [];
}

public class BulkTransactionPayDto
{
    public List<Guid> Ids { get; set; } = [];
    public string? PaymentMethod { get; set; }
}

public record BulkTransactionResultDto(int Success, int Failed);
