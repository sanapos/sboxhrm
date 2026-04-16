using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Transactions;

/// <summary>
/// DTO cho giao dịch thu chi
/// </summary>
public record CashTransactionDto
{
    public Guid Id { get; init; }
    public string TransactionCode { get; init; } = string.Empty;
    public CashTransactionType Type { get; init; }
    public string TypeName => Type == CashTransactionType.Income ? "Thu" : "Chi";
    public Guid CategoryId { get; init; }
    public string CategoryName { get; init; } = string.Empty;
    public string? CategoryIcon { get; init; }
    public string? CategoryColor { get; init; }
    public decimal Amount { get; init; }
    public DateTime TransactionDate { get; init; }
    public string Description { get; init; } = string.Empty;
    public PaymentMethodType PaymentMethod { get; init; }
    public string PaymentMethodName => PaymentMethod switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Khác"
    };
    public Guid? BankAccountId { get; init; }
    public string? BankAccountName { get; init; }
    public CashTransactionStatus Status { get; init; }
    public string StatusName => Status switch
    {
        CashTransactionStatus.Pending => "Chờ xử lý",
        CashTransactionStatus.Completed => "Hoàn thành",
        CashTransactionStatus.Cancelled => "Đã hủy",
        CashTransactionStatus.WaitingPayment => "Chờ thanh toán",
        _ => "Không xác định"
    };
    public string? ContactName { get; init; }
    public string? ContactPhone { get; init; }
    public string? PaymentReference { get; init; }
    public string? ReceiptImageUrl { get; init; }
    public string? VietQRUrl { get; init; }
    public bool IsPaid { get; init; }
    public DateTime? PaidDate { get; init; }
    public Guid CreatedByUserId { get; init; }
    public string CreatedByUserName { get; init; } = string.Empty;
    public string? InternalNote { get; init; }
    public string? Tags { get; init; }
    public DateTime? CreatedAt { get; init; }
    public DateTime? LastModified { get; init; }
}

/// <summary>
/// DTO để tạo giao dịch thu chi
/// </summary>
public record CreateCashTransactionDto
{
    public CashTransactionType Type { get; init; }
    public Guid CategoryId { get; init; }
    public decimal Amount { get; init; }
    public DateTime TransactionDate { get; init; } = DateTime.UtcNow;
    public string Description { get; init; } = string.Empty;
    public PaymentMethodType PaymentMethod { get; init; } = PaymentMethodType.Cash;
    public Guid? BankAccountId { get; init; }
    public string? ContactName { get; init; }
    public string? ContactPhone { get; init; }
    public string? PaymentReference { get; init; }
    public string? ReceiptImageUrl { get; init; }
    public bool IsPaid { get; init; } = true;
    public string? InternalNote { get; init; }
    public string? Tags { get; init; }
}

/// <summary>
/// DTO để cập nhật giao dịch thu chi
/// </summary>
public record UpdateCashTransactionDto
{
    public CashTransactionType Type { get; init; }
    public Guid CategoryId { get; init; }
    public decimal Amount { get; init; }
    public DateTime TransactionDate { get; init; }
    public string Description { get; init; } = string.Empty;
    public PaymentMethodType PaymentMethod { get; init; }
    public Guid? BankAccountId { get; init; }
    public string? ContactName { get; init; }
    public string? ContactPhone { get; init; }
    public string? PaymentReference { get; init; }
    public string? ReceiptImageUrl { get; init; }
    public bool IsPaid { get; init; }
    public string? InternalNote { get; init; }
    public string? Tags { get; init; }
}

/// <summary>
/// DTO để cập nhật trạng thái giao dịch
/// </summary>
public record UpdateCashTransactionStatusDto
{
    public CashTransactionStatus Status { get; init; }
    public bool? IsPaid { get; init; }
}

/// <summary>
/// DTO tổng hợp thu chi
/// </summary>
public record CashTransactionSummaryDto
{
    public decimal TotalIncome { get; init; }
    public decimal TotalExpense { get; init; }
    public decimal Balance => TotalIncome - TotalExpense;
    public int TotalTransactions { get; init; }
    public int IncomeTransactions { get; init; }
    public int ExpenseTransactions { get; init; }
    public int PendingTransactions { get; init; }
    public DateTime? FromDate { get; init; }
    public DateTime? ToDate { get; init; }
    public List<CategorySummaryDto> IncomeByCategory { get; init; } = new();
    public List<CategorySummaryDto> ExpenseByCategory { get; init; } = new();
    public List<DailySummaryDto> DailySummary { get; init; } = new();
}

public record CategorySummaryDto
{
    public Guid CategoryId { get; init; }
    public string CategoryName { get; init; } = string.Empty;
    public string? Icon { get; init; }
    public string? Color { get; init; }
    public decimal Amount { get; init; }
    public int Count { get; init; }
    public decimal Percentage { get; init; }
}

public record DailySummaryDto
{
    public DateTime Date { get; init; }
    public decimal Income { get; init; }
    public decimal Expense { get; init; }
    public decimal Balance => Income - Expense;
}
