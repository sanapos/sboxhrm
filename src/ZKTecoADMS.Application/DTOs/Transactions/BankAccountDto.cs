namespace ZKTecoADMS.Application.DTOs.Transactions;

/// <summary>
/// DTO cho tài khoản ngân hàng
/// </summary>
public record BankAccountDto
{
    public Guid Id { get; init; }
    public string AccountName { get; init; } = string.Empty;
    public string AccountNumber { get; init; } = string.Empty;
    public string BankCode { get; init; } = string.Empty;
    public string BankName { get; init; } = string.Empty;
    public string? BankShortName { get; init; }
    public string? BranchName { get; init; }
    public string? BankLogoUrl { get; init; }
    public bool IsDefault { get; init; }
    public string? Note { get; init; }
    public string VietQRTemplate { get; init; } = "compact2";
    public bool IsActive { get; init; }
    public int TransactionCount { get; init; }
}

/// <summary>
/// DTO để tạo tài khoản ngân hàng
/// </summary>
public record CreateBankAccountDto
{
    public string AccountName { get; init; } = string.Empty;
    public string AccountNumber { get; init; } = string.Empty;
    public string BankCode { get; init; } = string.Empty;
    public string BankName { get; init; } = string.Empty;
    public string? BankShortName { get; init; }
    public string? BranchName { get; init; }
    public string? BankLogoUrl { get; init; }
    public bool IsDefault { get; init; } = false;
    public string? Note { get; init; }
    public string VietQRTemplate { get; init; } = "compact2";
}

/// <summary>
/// DTO để cập nhật tài khoản ngân hàng
/// </summary>
public record UpdateBankAccountDto
{
    public string AccountName { get; init; } = string.Empty;
    public string? BranchName { get; init; }
    public bool IsDefault { get; init; }
    public string? Note { get; init; }
    public string VietQRTemplate { get; init; } = "compact2";
    public bool IsActive { get; init; } = true;
}

/// <summary>
/// DTO cho VietQR URL response
/// </summary>
public record VietQRResponseDto
{
    public string QRUrl { get; init; } = string.Empty;
    public string QRDataUrl { get; init; } = string.Empty;
    public string BankName { get; init; } = string.Empty;
    public string BankLogo { get; init; } = string.Empty;
    public string AccountNumber { get; init; } = string.Empty;
    public string AccountName { get; init; } = string.Empty;
    public decimal? Amount { get; init; }
    public string? Description { get; init; }
}

/// <summary>
/// Danh sách ngân hàng hỗ trợ VietQR
/// </summary>
public record VietQRBankDto
{
    public string Code { get; init; } = string.Empty;
    public string BIN { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string ShortName { get; init; } = string.Empty;
    public string LogoUrl { get; init; } = string.Empty;
}

/// <summary>
/// Request để tạo VietQR URL
/// </summary>
public record GenerateVietQRRequest
{
    public Guid? BankAccountId { get; init; }
    public string? BankCode { get; init; }
    public string? AccountNumber { get; init; }
    public decimal? Amount { get; init; }
    public string? Description { get; init; }
    public string Template { get; init; } = "compact2";
}
