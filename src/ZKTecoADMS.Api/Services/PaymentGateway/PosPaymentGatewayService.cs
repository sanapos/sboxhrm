using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public interface IPosPaymentGatewayService
{
    Task<PaymentGatewaySettingDto?> GetSettingsAsync(Guid storeId, CancellationToken ct = default);
    Task<PaymentGatewaySettingDto> UpsertSettingsAsync(
        Guid storeId, PaymentGatewaySettingUpsertRequest req, string? actor, CancellationToken ct = default);
    Task<NotificationCreditPurchaseDto> CreateCreditPurchaseAsync(
        Guid storeId, CreateCreditPurchaseRequest req, string? actor, CancellationToken ct = default);
    Task<List<NotificationCreditPurchaseDto>> ListCreditPurchasesAsync(
        Guid storeId, string? status, int limit, CancellationToken ct = default);
    Task<NotificationCreditPurchaseDto?> GetCreditPurchaseAsync(
        Guid storeId, Guid id, CancellationToken ct = default);
    Task<TransferPaymentIntentDto> CreateTransferIntentAsync(
        Guid storeId, CreateTransferIntentRequest req, string? actor, CancellationToken ct = default);
    Task<List<TransferPaymentIntentDto>> ListTransferIntentsAsync(
        Guid storeId, string? status, int limit, CancellationToken ct = default);
    Task<TransferPaymentIntentDto?> GetTransferIntentAsync(
        Guid storeId, Guid id, CancellationToken ct = default);
    Task<WebhookProcessResult> ProcessWebhookAsync(
        PosPaymentNotifyProvider provider,
        string? signature,
        string? timestamp,
        string rawBody,
        IHubContext<AttendanceHub>? hub,
        CancellationToken ct = default);
}

public sealed record PaymentGatewaySettingUpsertRequest(
    string? DefaultTransferProvider,
    bool? TingeeEnabled,
    string? TingeeClientId,
    string? TingeeSecretKey,
    string? TingeeVaAccountNumber,
    string? TingeeMerchantId,
    string? TingeeWebhookSecret);

public sealed record CreateTransferIntentRequest(
    Guid? SaleOrderId,
    string ExternalOrderId,
    string? OrderNo,
    decimal AmountExpected,
    string? Provider,
    string? TableName,
    int ExpireMinutes = 30);

public sealed record CreateCreditPurchaseRequest(
    Guid PackageId,
    string? Note,
    string? ExternalPaymentRef = null);

public sealed class PosPaymentGatewayService(
    ZKTecoDbContext db,
    IPaymentWebhookProviderRegistry providerRegistry,
    IPosNotificationCreditService creditService) : IPosPaymentGatewayService
{
    public async Task<PaymentGatewaySettingDto?> GetSettingsAsync(Guid storeId, CancellationToken ct = default)
    {
        var s = await db.PosPaymentGatewaySettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        return s == null ? null : MapSetting(s);
    }

    public async Task<PaymentGatewaySettingDto> UpsertSettingsAsync(
        Guid storeId, PaymentGatewaySettingUpsertRequest req, string? actor, CancellationToken ct = default)
    {
        var row = await db.PosPaymentGatewaySettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        if (row == null)
        {
            row = new PosPaymentGatewaySetting
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                IsActive = true,
                CreatedBy = actor,
            };
            db.PosPaymentGatewaySettings.Add(row);
        }

        if (!string.IsNullOrWhiteSpace(req.DefaultTransferProvider) &&
            Enum.TryParse<PosPaymentNotifyProvider>(req.DefaultTransferProvider, true, out var prov))
            row.DefaultTransferProvider = prov;
        if (req.TingeeEnabled.HasValue) row.TingeeEnabled = req.TingeeEnabled.Value;
        if (req.TingeeClientId != null) row.TingeeClientId = req.TingeeClientId.Trim();
        if (!string.IsNullOrWhiteSpace(req.TingeeSecretKey)) row.TingeeSecretKey = req.TingeeSecretKey.Trim();
        if (req.TingeeVaAccountNumber != null) row.TingeeVaAccountNumber = req.TingeeVaAccountNumber.Trim();
        if (req.TingeeMerchantId != null) row.TingeeMerchantId = req.TingeeMerchantId.Trim();
        if (!string.IsNullOrWhiteSpace(req.TingeeWebhookSecret))
            row.TingeeWebhookSecret = req.TingeeWebhookSecret.Trim();
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        return MapSetting(row);
    }

    public async Task<NotificationCreditPurchaseDto> CreateCreditPurchaseAsync(
        Guid storeId, CreateCreditPurchaseRequest req, string? actor, CancellationToken ct = default)
    {
        var pkg = await db.PosNotificationCreditPackages.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == req.PackageId && x.IsActive && x.IsPublic && x.Deleted == null, ct);
        if (pkg == null)
            throw new InvalidOperationException("Không tìm thấy gói credit đang mở bán");

        var paymentRef = (req.ExternalPaymentRef ?? "").Trim();
        if (paymentRef.Length == 0)
            paymentRef = $"CRD{DateTime.UtcNow:yyyyMMddHHmmss}{Random.Shared.Next(100, 999)}";

        var existing = await db.PosNotificationCreditPurchases.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId
                && x.ExternalPaymentRef == paymentRef
                && x.Deleted == null, ct);
        if (existing != null)
            return MapPurchase(existing, pkg.Name);

        var row = new PosNotificationCreditPurchase
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            PackageId = pkg.Id,
            CreditCount = pkg.CreditCount,
            AmountPaid = pkg.Price,
            Status = PosNotificationCreditPurchaseStatus.Pending,
            ExternalPaymentRef = paymentRef,
            Note = req.Note?.Trim(),
            IsActive = true,
            CreatedBy = actor,
        };
        db.PosNotificationCreditPurchases.Add(row);
        await db.SaveChangesAsync(ct);
        return MapPurchase(row, pkg.Name);
    }

    public async Task<List<NotificationCreditPurchaseDto>> ListCreditPurchasesAsync(
        Guid storeId, string? status, int limit, CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 100);
        var q = db.PosNotificationCreditPurchases.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .Include(x => x.Package)
            .AsQueryable();
        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosNotificationCreditPurchaseStatus>(status, true, out var st))
            q = q.Where(x => x.Status == st);
        var rows = await q.OrderByDescending(x => x.CreatedAt).Take(limit).ToListAsync(ct);
        return rows.Select(x => MapPurchase(x, x.Package?.Name)).ToList();
    }

    public async Task<NotificationCreditPurchaseDto?> GetCreditPurchaseAsync(
        Guid storeId, Guid id, CancellationToken ct = default)
    {
        var row = await db.PosNotificationCreditPurchases.AsNoTracking()
            .Include(x => x.Package)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null, ct);
        return row == null ? null : MapPurchase(row, row.Package?.Name);
    }

    public async Task<TransferPaymentIntentDto> CreateTransferIntentAsync(
        Guid storeId, CreateTransferIntentRequest req, string? actor, CancellationToken ct = default)
    {
        var externalId = req.ExternalOrderId.Trim();
        if (externalId.Length == 0)
            throw new InvalidOperationException("Thiếu mã đơn (ExternalOrderId)");

        var provider = PosPaymentNotifyProvider.Tingee;
        if (!string.IsNullOrWhiteSpace(req.Provider) &&
            Enum.TryParse<PosPaymentNotifyProvider>(req.Provider, true, out var p))
            provider = p;

        var existing = await db.PosTransferPaymentIntents.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.ExternalOrderId == externalId
                && x.Status == PosTransferPaymentIntentStatus.Waiting && x.Deleted == null, ct);
        if (existing != null)
        {
            existing.AmountExpected = req.AmountExpected;
            existing.OrderNo = req.OrderNo?.Trim();
            existing.TableName = req.TableName?.Trim();
            existing.ExpiresAt = DateTime.UtcNow.AddMinutes(Math.Clamp(req.ExpireMinutes, 5, 120));
            existing.UpdatedAt = DateTime.UtcNow;
            existing.UpdatedBy = actor;
            if (req.SaleOrderId.HasValue) existing.SaleOrderId = req.SaleOrderId;
            await db.SaveChangesAsync(ct);
            return MapIntent(existing);
        }

        var intent = new PosTransferPaymentIntent
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = req.SaleOrderId,
            ExternalOrderId = externalId,
            OrderNo = req.OrderNo?.Trim(),
            AmountExpected = req.AmountExpected,
            Provider = provider,
            Status = PosTransferPaymentIntentStatus.Waiting,
            ExpiresAt = DateTime.UtcNow.AddMinutes(Math.Clamp(req.ExpireMinutes, 5, 120)),
            TableName = req.TableName?.Trim(),
            IsActive = true,
            CreatedBy = actor,
        };
        db.PosTransferPaymentIntents.Add(intent);
        await db.SaveChangesAsync(ct);
        return MapIntent(intent);
    }

    public async Task<List<TransferPaymentIntentDto>> ListTransferIntentsAsync(
        Guid storeId, string? status, int limit, CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 200);
        var q = db.PosTransferPaymentIntents.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosTransferPaymentIntentStatus>(status, true, out var st))
            q = q.Where(x => x.Status == st);
        var rows = await q.OrderByDescending(x => x.CreatedAt).Take(limit).ToListAsync(ct);
        return rows.Select(MapIntent).ToList();
    }

    public async Task<TransferPaymentIntentDto?> GetTransferIntentAsync(
        Guid storeId, Guid id, CancellationToken ct = default)
    {
        var row = await db.PosTransferPaymentIntents.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null, ct);
        return row == null ? null : MapIntent(row);
    }

    public async Task<WebhookProcessResult> ProcessWebhookAsync(
        PosPaymentNotifyProvider provider,
        string? signature,
        string? timestamp,
        string rawBody,
        IHubContext<AttendanceHub>? hub,
        CancellationToken ct = default)
    {
        var webhookProvider = providerRegistry.Get(provider);
        var payload = webhookProvider.Parse(rawBody);

        var audit = new PosPaymentWebhookEvent
        {
            Id = Guid.NewGuid(),
            Provider = provider,
            ProviderTransactionCode = payload.TransactionCode,
            EventType = payload.IsSuccess ? "payment_success" : "payment_invalid",
            PayloadJson = rawBody.Length > 8000 ? rawBody[..8000] : rawBody,
            ReceivedAt = DateTime.UtcNow,
            IsActive = true,
            CreatedBy = "webhook",
        };

        if (!payload.IsSuccess || string.IsNullOrWhiteSpace(payload.TransactionCode))
        {
            audit.SignatureValid = false;
            audit.ResultCode = "09";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("09", payload.ErrorMessage ?? "Invalid payload", false, null, null, null, null);
        }

        // Match purchase-credit first so store can tự mua gói và auto cộng credit.
        var purchase = await FindPendingCreditPurchaseAsync(payload, ct);

        // Resolve store by purchase match first, then Tingee clientId or VA
        PosPaymentGatewaySetting? settings = null;
        if (purchase != null)
        {
            settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.StoreId == purchase.StoreId && x.Deleted == null, ct);
        }
        if (settings == null && !string.IsNullOrWhiteSpace(payload.ClientId))
        {
            settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.TingeeClientId == payload.ClientId && x.Deleted == null, ct);
        }
        if (settings == null && !string.IsNullOrWhiteSpace(payload.VaAccountNumber))
        {
            settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.TingeeVaAccountNumber == payload.VaAccountNumber && x.Deleted == null, ct);
        }

        if (settings == null || !settings.TingeeEnabled)
        {
            audit.ResultCode = "09";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("09", "Store not configured for Tingee", false, null, null, null, null);
        }

        var secret = settings.TingeeWebhookSecret ?? settings.TingeeSecretKey ?? "";
        audit.SignatureValid = webhookProvider.VerifySignature(signature, timestamp, rawBody, secret);
        audit.StoreId = settings.StoreId;

        if (!audit.SignatureValid)
        {
            audit.ResultCode = "09";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("09", "Invalid signature", false, settings.StoreId, null, null, null);
        }

        if (purchase != null)
        {
            if (purchase.Status == PosNotificationCreditPurchaseStatus.Paid)
            {
                audit.ResultCode = "02";
                db.PosPaymentWebhookEvents.Add(audit);
                await db.SaveChangesAsync(ct);
                return new WebhookProcessResult("02", "Purchase already processed", true, purchase.StoreId, null, null, purchase.AmountPaid);
            }

            purchase.Status = PosNotificationCreditPurchaseStatus.Paid;
            purchase.PaidAt = payload.TransactionAt ?? DateTime.UtcNow;
            purchase.UpdatedAt = DateTime.UtcNow;
            purchase.UpdatedBy = "webhook";
            purchase.Note = JoinNote(purchase.Note,
                $"TXN:{payload.TransactionCode}; amount:{payload.Amount?.ToString("0.##") ?? "0"}");

            await creditService.GrantAsync(
                purchase.StoreId,
                purchase.CreditCount,
                PosNotificationCreditLedgerSource.Purchase,
                purchase.Id,
                $"Credit package paid via {provider} - {purchase.ExternalPaymentRef}",
                "webhook",
                ct);

            audit.ResultCode = "00";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("00", "Credit purchase paid", false, purchase.StoreId, null,
                purchase.ExternalPaymentRef, purchase.AmountPaid);
        }

        // Idempotent: already processed intent?
        var already = await db.PosTransferPaymentIntents.AsNoTracking()
            .FirstOrDefaultAsync(x => x.ProviderTransactionCode == payload.TransactionCode && x.Deleted == null, ct);
        if (already != null &&
            already.Status is PosTransferPaymentIntentStatus.Confirmed or PosTransferPaymentIntentStatus.Completed)
        {
            audit.TransferIntentId = already.Id;
            audit.ResultCode = "02";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("02", "Already processed", true, already.StoreId, already.Id,
                already.OrderNo, already.AmountExpected);
        }

        var (consumed, balanceAfter, consumeErr) = await creditService.TryConsumeOneAsync(
            settings.StoreId, provider, payload.TransactionCode!, null,
            $"Webhook {provider}", ct);
        if (!consumed)
        {
            audit.ResultCode = "xx";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("xx", consumeErr ?? "Out of credits", false, settings.StoreId, null, null, null);
        }

        PosTransferPaymentIntent? intent = null;
        if (!string.IsNullOrWhiteSpace(payload.ExternalOrderId))
        {
            intent = await db.PosTransferPaymentIntents.AsTracking()
                .FirstOrDefaultAsync(x => x.StoreId == settings.StoreId
                    && x.ExternalOrderId == payload.ExternalOrderId && x.Deleted == null, ct);
        }
        if (intent == null && !string.IsNullOrWhiteSpace(payload.TransferContent))
        {
            var guess = payload.TransferContent.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            foreach (var token in guess)
            {
                intent = await db.PosTransferPaymentIntents.AsTracking()
                    .FirstOrDefaultAsync(x => x.StoreId == settings.StoreId
                        && x.ExternalOrderId == token
                        && x.Status == PosTransferPaymentIntentStatus.Waiting
                        && x.Deleted == null, ct);
                if (intent != null) break;
            }
        }

        if (intent == null)
        {
            intent = new PosTransferPaymentIntent
            {
                Id = Guid.NewGuid(),
                StoreId = settings.StoreId,
                ExternalOrderId = payload.ExternalOrderId ?? payload.TransactionCode!,
                OrderNo = payload.ExternalOrderId,
                AmountExpected = payload.Amount ?? 0,
                Provider = provider,
                Status = PosTransferPaymentIntentStatus.Confirmed,
                ProviderTransactionCode = payload.TransactionCode,
                TransferContent = payload.TransferContent,
                ConfirmedAt = payload.TransactionAt ?? DateTime.UtcNow,
                ExpiresAt = DateTime.UtcNow,
                RawWebhookJson = rawBody.Length > 2000 ? rawBody[..2000] : rawBody,
                IsActive = true,
                CreatedBy = "webhook",
            };
            db.PosTransferPaymentIntents.Add(intent);
        }
        else
        {
            intent.Status = PosTransferPaymentIntentStatus.Confirmed;
            intent.ProviderTransactionCode = payload.TransactionCode;
            intent.TransferContent = payload.TransferContent ?? intent.TransferContent;
            intent.ConfirmedAt = payload.TransactionAt ?? DateTime.UtcNow;
            intent.RawWebhookJson = rawBody.Length > 2000 ? rawBody[..2000] : rawBody;
            intent.UpdatedAt = DateTime.UtcNow;
            intent.UpdatedBy = "webhook";
        }

        audit.TransferIntentId = intent.Id;
        audit.ResultCode = "00";
        db.PosPaymentWebhookEvents.Add(audit);
        await db.SaveChangesAsync(ct);

        var orderLabel = intent.OrderNo ?? intent.ExternalOrderId;
        var amountText = payload.Amount.HasValue ? $"{payload.Amount.Value:0}đ" : "";
        var spoken = string.IsNullOrEmpty(amountText)
            ? $"Đã nhận chuyển khoản đơn {orderLabel}"
            : $"Đã nhận chuyển khoản {amountText}, đơn {orderLabel}";

        PosFloorRealtimeHelper.Notify(
            hub,
            settings.StoreId,
            "tingeePaymentConfirmed",
            orderId: intent.SaleOrderId,
            tableName: intent.TableName,
            message: spoken);

        return new WebhookProcessResult("00", "Success", false, settings.StoreId, intent.Id,
            intent.OrderNo, intent.AmountExpected);
    }

    private static PaymentGatewaySettingDto MapSetting(PosPaymentGatewaySetting s) => new(
        s.DefaultTransferProvider.ToString(),
        s.TingeeEnabled,
        s.TingeeClientId,
        !string.IsNullOrWhiteSpace(s.TingeeSecretKey),
        s.TingeeVaAccountNumber,
        s.TingeeMerchantId,
        !string.IsNullOrWhiteSpace(s.TingeeWebhookSecret));

    private async Task<PosNotificationCreditPurchase?> FindPendingCreditPurchaseAsync(
        PaymentWebhookPayload payload,
        CancellationToken ct)
    {
        var q = db.PosNotificationCreditPurchases.AsTracking()
            .Where(x => x.Deleted == null && x.Status == PosNotificationCreditPurchaseStatus.Pending);

        if (!string.IsNullOrWhiteSpace(payload.ExternalOrderId))
        {
            var hit = await q.FirstOrDefaultAsync(x => x.ExternalPaymentRef == payload.ExternalOrderId, ct);
            if (hit != null) return hit;
        }

        if (!string.IsNullOrWhiteSpace(payload.TransferContent))
        {
            var guess = payload.TransferContent.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            foreach (var token in guess)
            {
                var hit = await q.FirstOrDefaultAsync(x => x.ExternalPaymentRef == token, ct);
                if (hit != null) return hit;
            }
        }

        return null;
    }

    private static string? JoinNote(string? oldNote, string append)
    {
        var prev = (oldNote ?? "").Trim();
        if (prev.Length == 0) return append;
        if (prev.Contains(append, StringComparison.OrdinalIgnoreCase)) return prev;
        return $"{prev} | {append}";
    }

    private static TransferPaymentIntentDto MapIntent(PosTransferPaymentIntent x) => new(
        x.Id,
        x.SaleOrderId,
        x.ExternalOrderId,
        x.OrderNo,
        x.AmountExpected,
        x.Provider.ToString(),
        x.Status.ToString(),
        x.ProviderTransactionCode,
        x.TransferContent,
        x.ConfirmedAt,
        x.CompletedAt,
        x.ExpiresAt,
        x.TableName,
        x.CreatedAt);

    private static NotificationCreditPurchaseDto MapPurchase(PosNotificationCreditPurchase x, string? packageName) => new(
        x.Id,
        x.PackageId,
        packageName ?? "Gói credit",
        x.CreditCount,
        x.AmountPaid,
        x.Status.ToString(),
        x.ExternalPaymentRef,
        x.PaidAt,
        x.Note,
        x.CreatedAt);
}
