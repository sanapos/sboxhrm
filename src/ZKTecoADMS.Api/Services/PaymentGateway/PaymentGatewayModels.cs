using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

/// <summary>Kết quả parse webhook từ cổng thanh toán.</summary>
public sealed record PaymentWebhookPayload(
    bool IsSuccess,
    string? TransactionCode,
    string? ExternalOrderId,
    string? ClientId,
    string? VaAccountNumber,
    string? TransferContent,
    decimal? Amount,
    DateTime? TransactionAt,
    string? RawJson,
    string? ErrorMessage);

public sealed record WebhookProcessResult(
    string ResponseCode,
    string Message,
    bool AlreadyProcessed,
    Guid? StoreId,
    Guid? TransferIntentId,
    string? OrderNo,
    decimal? Amount);

public sealed record NotificationCreditBalanceDto(
    int RemainingCount,
    int TotalGranted,
    int TotalConsumed);

public sealed record TransferPaymentIntentDto(
    Guid Id,
    Guid? SaleOrderId,
    string ExternalOrderId,
    string? OrderNo,
    decimal AmountExpected,
    string Provider,
    string Status,
    string? ProviderTransactionCode,
    string? TransferContent,
    DateTime? ConfirmedAt,
    DateTime? CompletedAt,
    DateTime ExpiresAt,
    string? TableName,
    DateTime CreatedAt);

public sealed record PaymentGatewaySettingDto(
    string DefaultTransferProvider,
    bool TingeeEnabled,
    string? TingeeClientId,
    bool HasTingeeSecretKey,
    string? TingeeVaAccountNumber,
    string? TingeeMerchantId,
    bool HasTingeeWebhookSecret,
    bool PlatformTingeeConfigured);

public sealed record PlatformCreditBalanceDto(
    int RemainingCount,
    int TotalPurchased,
    int TotalAllocated,
    decimal LastCostPerCredit);

public sealed record PlatformCreditLedgerDto(
    Guid Id,
    int Delta,
    int BalanceAfter,
    string Source,
    Guid? StoreId,
    string? StoreName,
    string? Note,
    DateTime CreatedAt);

public sealed record PlatformTingeeSettingDto(
    bool TingeeEnabled,
    string? TingeeClientId,
    bool HasTingeeSecretKey,
    bool HasTingeeWebhookSecret,
    string ApiEnvironment,
    string? ApiBaseUrlOverride,
    string? DefaultVaAccountNumber,
    string WebhookUrl);

public sealed record NotificationCreditPackageDto(
    Guid Id,
    string Name,
    int CreditCount,
    decimal Price,
    string? Description,
    bool IsActive,
    bool IsPublic,
    int SortOrder);

public sealed record NotificationCreditPurchaseDto(
    Guid Id,
    Guid? PackageId,
    string PackageName,
    int CreditCount,
    decimal AmountPaid,
    string Status,
    string? ExternalPaymentRef,
    DateTime? PaidAt,
    string? Note,
    DateTime CreatedAt);

public sealed record NotificationCreditPurchaseAdminDto(
    Guid Id,
    Guid StoreId,
    string? StoreName,
    Guid? PackageId,
    string PackageName,
    int CreditCount,
    decimal AmountPaid,
    string Status,
    string? ExternalPaymentRef,
    DateTime? PaidAt,
    string? Note,
    DateTime CreatedAt);

public sealed record NotificationCreditLedgerDto(
    Guid Id,
    int Delta,
    int BalanceAfter,
    string Source,
    string? ProviderTransactionCode,
    string? Note,
    DateTime CreatedAt);

public sealed record NotificationCreditLedgerAdminDto(
    Guid Id,
    Guid StoreId,
    string? StoreName,
    int Delta,
    int BalanceAfter,
    string Source,
    string? ProviderTransactionCode,
    string? Note,
    DateTime CreatedAt);

public sealed record CreditPurchasesAdminReportDto(
    decimal TotalAmountPaid,
    decimal TotalAmountPending,
    int TotalCreditsPaid,
    int TotalCreditsPending,
    List<NotificationCreditPurchaseAdminDto> Items);
