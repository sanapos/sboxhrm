namespace ZKTecoADMS.Application.DTOs.Transactions;

public record FundTransferDto
{
    public Guid Id { get; init; }
    public string TransferCode { get; init; } = string.Empty;
    public Guid? FromBankAccountId { get; init; }
    public string FromFundLabel { get; init; } = string.Empty;
    public Guid? ToBankAccountId { get; init; }
    public string ToFundLabel { get; init; } = string.Empty;
    public decimal Amount { get; init; }
    public DateTime TransferDate { get; init; }
    public string Description { get; init; } = string.Empty;
    public string? InternalNote { get; init; }
    public Guid CreatedByUserId { get; init; }
    public string CreatedByUserName { get; init; } = string.Empty;
    public DateTime? CreatedAt { get; init; }
}

public record CreateFundTransferDto
{
    public Guid? FromBankAccountId { get; init; }
    public Guid? ToBankAccountId { get; init; }
    public decimal Amount { get; init; }
    public DateTime TransferDate { get; init; } = DateTime.UtcNow;
    public string Description { get; init; } = string.Empty;
    public string? InternalNote { get; init; }
}

public record FundBalanceDto
{
    public Guid? BankAccountId { get; init; }
    public string Label { get; init; } = string.Empty;
    public string? BankShortName { get; init; }
    public decimal Balance { get; init; }
    public bool IsCash { get; init; }
}
