using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
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
    string? TingeeShopId,
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
    IPosNotificationCreditService creditService,
    IPosPlatformNotificationCreditService platformCreditService,
    IPosPlatformTingeeSettingService platformTingeeService,
    ITingeeMerchantProvisioningService tingeeProvision,
    IPosTingeePaidOrderService tingeePaidOrders,
    ISystemNotificationService notifications) : IPosPaymentGatewayService
{
    public async Task<PaymentGatewaySettingDto?> GetSettingsAsync(Guid storeId, CancellationToken ct = default)
    {
        var s = await db.PosPaymentGatewaySettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        if (s != null && s.TingeeEnabled && !string.IsNullOrWhiteSpace(s.TingeeMerchantId))
        {
            var va = (s.TingeeVaAccountNumber ?? "").Trim();
            if (va.Length == 0 || va.All(char.IsDigit))
            {
                await tingeeProvision.SyncVaQrDestinationAsync(storeId, ct);
                s = await db.PosPaymentGatewaySettings.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
            }
        }
        var platform = await platformTingeeService.GetSettingsAsync(ct);
        return s == null ? null : MapSetting(s, platform);
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
        if (req.TingeeVaAccountNumber != null)
        {
            var incoming = req.TingeeVaAccountNumber.Trim();
            var current = (row.TingeeVaAccountNumber ?? "").Trim();
            var keepVa = current.Any(char.IsLetter)
                && incoming.All(char.IsDigit)
                && !string.Equals(current, incoming, StringComparison.OrdinalIgnoreCase);
            if (!keepVa)
                row.TingeeVaAccountNumber = incoming;
        }
        if (req.TingeeMerchantId != null) row.TingeeMerchantId = req.TingeeMerchantId.Trim();
        if (req.TingeeShopId != null) row.TingeeShopId = req.TingeeShopId.Trim();
        if (string.IsNullOrWhiteSpace(row.TingeeVaAccountNumber))
        {
            var defaultBank = await db.BankAccounts.AsNoTracking()
                .Where(x => x.StoreId == storeId && x.IsDefault && x.IsActive && x.Deleted == null)
                .Select(x => x.AccountNumber)
                .FirstOrDefaultAsync(ct);
            if (!string.IsNullOrWhiteSpace(defaultBank))
                row.TingeeVaAccountNumber = defaultBank.Trim();
        }
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        if (row.TingeeEnabled)
            await tingeeProvision.SyncVaQrDestinationAsync(storeId, ct);
        var platform = await platformTingeeService.GetSettingsAsync(ct);
        return MapSetting(row, platform);
    }

    public async Task<NotificationCreditPurchaseDto> CreateCreditPurchaseAsync(
        Guid storeId, CreateCreditPurchaseRequest req, string? actor, CancellationToken ct = default)
    {
        var pkg = await db.PosNotificationCreditPackages.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == req.PackageId && x.IsActive && x.IsPublic && x.Deleted == null, ct);
        if (pkg == null)
            throw new InvalidOperationException("Không tìm thấy gói credit đang mở bán");

        var pool = await platformCreditService.GetBalanceAsync(ct);
        if (pool.RemainingCount < pkg.CreditCount)
            throw new InvalidOperationException(
                $"Kho Sbox không đủ lượt để bán gói này (còn {pool.RemainingCount}, cần {pkg.CreditCount})");

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

        // Tiền ra khỏi tài khoản: chỉ lưu vết, không khớp đơn/gói. Trả 00 để Tingee không gửi lại.
        if (payload.IsDebit)
        {
            audit.EventType = "debit_ignored";
            audit.ResultCode = "00";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("00", "Debit transaction ignored", false, null, null, null, null);
        }

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

        // Resolve store by purchase match first, then VA (ưu tiên), rồi legacy clientId
        PosPaymentGatewaySetting? settings = null;
        if (purchase != null)
        {
            settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.StoreId == purchase.StoreId && x.Deleted == null, ct);
        }
        if (settings == null)
        {
            settings = await FindTingeeSettingsByAccountAsync(payload.VaAccountNumber, payload, ct);
        }
        if (settings == null && !string.IsNullOrWhiteSpace(payload.ClientId))
        {
            settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.TingeeClientId == payload.ClientId && x.Deleted == null, ct);
        }
        if (settings == null)
            settings = await FindTingeeSettingsByIntentAsync(payload, ct);

        if (settings == null || !settings.TingeeEnabled)
        {
            audit.ResultCode = "09";
            db.PosPaymentWebhookEvents.Add(audit);
            await db.SaveChangesAsync(ct);
            return new WebhookProcessResult("09", "Store not configured for Tingee", false, null, null, null, null);
        }

        var platformSecret = await platformTingeeService.ResolveWebhookSecretAsync(ct);
        var secrets = new List<string>();
        if (!string.IsNullOrWhiteSpace(platformSecret)) secrets.Add(platformSecret);
        var legacyStoreSecret = settings.TingeeWebhookSecret ?? settings.TingeeSecretKey ?? "";
        if (!string.IsNullOrWhiteSpace(legacyStoreSecret)) secrets.Add(legacyStoreSecret);

        audit.SignatureValid = secrets.Any(s =>
            webhookProvider.VerifySignature(signature, timestamp, rawBody, s));
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

            var (allocated, allocErr) = await platformCreditService.TryAllocateToStoreAsync(
                purchase.StoreId,
                purchase.CreditCount,
                PosNotificationCreditLedgerSource.Purchase,
                purchase.Id,
                $"Credit package paid via {provider} - {purchase.ExternalPaymentRef}",
                "webhook",
                ct);
            if (!allocated)
            {
                audit.ResultCode = "xx";
                db.PosPaymentWebhookEvents.Add(audit);
                await db.SaveChangesAsync(ct);
                return new WebhookProcessResult("xx", allocErr ?? "Platform pool insufficient", false,
                    purchase.StoreId, null, purchase.ExternalPaymentRef, purchase.AmountPaid);
            }

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
            already.Status is PosTransferPaymentIntentStatus.Confirmed or PosTransferPaymentIntentStatus.Completed
                or PosTransferPaymentIntentStatus.Underpaid)
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
            // Mã đơn nháp TMP{ô} dùng lại cho mọi đơn của cùng ô hóa đơn → nhiều lệnh cùng mã.
            // Ưu tiên lệnh đang chờ, mới nhất; trước đây FirstOrDefault hay rơi vào lệnh cũ đã xong
            // → báo «thiếu tiền» / «đã xử lý», đơn đang chờ không tự hoàn tất.
            intent = await db.PosTransferPaymentIntents.AsTracking()
                .Where(x => x.StoreId == settings.StoreId
                    && x.ExternalOrderId == payload.ExternalOrderId && x.Deleted == null)
                .OrderByDescending(x => x.Status == PosTransferPaymentIntentStatus.Waiting)
                .ThenByDescending(x => x.CreatedAt)
                .FirstOrDefaultAsync(ct);
        }
        if (intent == null && !string.IsNullOrWhiteSpace(payload.TransferContent))
        {
            // Tìm mã đối soát của lệnh đang chờ trong nội dung chuyển khoản. Ngân hàng hay chèn tiền tố / dấu chấm
            // («MBVCB.123.TMP05A3F9.CT tu…») nên tách theo mọi ký tự không phải chữ-số, không chỉ dấu cách.
            var waiting = await db.PosTransferPaymentIntents.AsNoTracking()
                .Where(x => x.StoreId == settings.StoreId
                    && x.Status == PosTransferPaymentIntentStatus.Waiting
                    && x.Deleted == null)
                .OrderByDescending(x => x.CreatedAt)
                .Take(300)
                .Select(x => new WaitingCode(x.Id, x.ExternalOrderId, x.OrderNo))
                .ToListAsync(ct);
            // Số đơn nháp «TMP{ô}» dùng lại giữa các đơn: lệnh đã có mã riêng thì không khớp theo số đơn nháp nữa.
            var hit = PosTransferCode.PickByContent(payload.TransferContent, waiting, w =>
                Controllers.PosDraftInvoiceSlots.IsTempOrderNo(w.OrderNo)
                && !string.Equals(w.OrderNo, w.ExternalOrderId, StringComparison.OrdinalIgnoreCase)
                    ? [w.ExternalOrderId]
                    : [w.ExternalOrderId, w.OrderNo]);
            if (hit != null)
                intent = await db.PosTransferPaymentIntents.AsTracking()
                    .FirstOrDefaultAsync(x => x.Id == hit.Id && x.Status == PosTransferPaymentIntentStatus.Waiting, ct);
        }
        // Tiền về KHÔNG có mã: không tự gắn vào đơn nào. Trước đây gắn vào lệnh chờ duy nhất cùng số tiền rồi tự hoàn
        // tất đơn đó — khách khác chuyển đúng số tiền ấy là bàn đang chờ thành «đã thanh toán». Nay chỉ gợi ý cho
        // thu ngân (đọc loa / thông báo) để kiểm tra rồi tự bấm thanh toán.
        string? sameAmountHint = null;
        if (intent == null && payload.Amount is decimal paid && paid > 0)
        {
            var since = DateTime.UtcNow.AddHours(-2);
            var sameAmount = await db.PosTransferPaymentIntents.AsNoTracking()
                .Where(x => x.StoreId == settings.StoreId
                    && x.Status == PosTransferPaymentIntentStatus.Waiting
                    && x.Deleted == null
                    && x.CreatedAt >= since
                    && x.AmountExpected == paid)
                .OrderByDescending(x => x.CreatedAt)
                .Select(x => new { x.TableName, x.OrderNo })
                .Take(2)
                .ToListAsync(ct);
            if (sameAmount.Count == 1)
            {
                var guess = !string.IsNullOrWhiteSpace(sameAmount[0].TableName)
                    ? sameAmount[0].TableName!.Trim()
                    : (string.IsNullOrWhiteSpace(sameAmount[0].OrderNo) ? null : $"đơn {sameAmount[0].OrderNo!.Trim()}");
                if (guess != null) sameAmountHint = guess;
            }
        }
        var unmatched = intent == null;

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
            // Khách chuyển ít hơn QR → không đánh dấu Confirmed (máy thu ngân sẽ tự hoàn tất nếu Confirmed).
            var underpaid = payload.Amount is decimal got && intent.AmountExpected > 0
                && got + 1m < intent.AmountExpected;
            intent.Status = underpaid
                ? PosTransferPaymentIntentStatus.Underpaid
                : PosTransferPaymentIntentStatus.Confirmed;
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

        var warning = intent.Status == PosTransferPaymentIntentStatus.Underpaid
            ? $"Chuyển khoản thiếu. Nhận {payload.Amount:0} đồng, cần {intent.AmountExpected:0} đồng" +
              (string.IsNullOrWhiteSpace(intent.OrderNo) ? "" : $", đơn {intent.OrderNo}")
            : await tingeePaidOrders.TryFulfillConfirmedIntentAsync(
                intent, payload.Amount, hub, notifications, ct);

        // Câu đọc loa trên máy thu ngân: "đồng" (TTS đọc "đ" thành chữ cái),
        // không đọc mã nội bộ "POS{tab}-{ms}" của giỏ chưa lưu.
        var orderNo = (intent.OrderNo ?? "").Trim();
        var suffix = orderNo.Length > 0
            ? $", đơn {orderNo}"
            : (string.IsNullOrWhiteSpace(intent.TableName) ? "" : $", {intent.TableName}");
        var amountText = payload.Amount.HasValue ? $" {payload.Amount.Value:0} đồng" : "";
        var spoken = warning ?? (intent.Status == PosTransferPaymentIntentStatus.Completed
            ? $"Đã thanh toán{amountText}{suffix}"
            : $"Đã nhận chuyển khoản{amountText}{suffix}");
        // Tiền về không có mã và không tự hoàn tất đơn nào → nói rõ cho thu ngân.
        if (warning == null && unmatched && intent.SaleOrderId == null
            && intent.Status == PosTransferPaymentIntentStatus.Confirmed)
        {
            spoken = $"Đã nhận chuyển khoản{amountText} không ghi mã đơn, chưa khớp đơn nào"
                + (sameAmountHint == null ? "" : $". Có thể là {sameAmountHint}, cùng số tiền")
                + ". Thu ngân kiểm tra rồi bấm thanh toán";
        }

        PosFloorRealtimeHelper.Notify(
            hub,
            settings.StoreId,
            "tingeePaymentConfirmed",
            orderId: intent.SaleOrderId,
            tableName: intent.TableName,
            message: spoken,
            orderNo: intent.OrderNo ?? intent.ExternalOrderId,
            externalOrderId: intent.ExternalOrderId,
            amount: payload.Amount ?? intent.AmountExpected);

        return new WebhookProcessResult("00", "Success", false, settings.StoreId, intent.Id,
            intent.OrderNo, intent.AmountExpected);
    }

    async Task<PosPaymentGatewaySetting?> FindTingeeSettingsByAccountAsync(
        string? account, PaymentWebhookPayload payload, CancellationToken ct)
    {
        var needle = (account ?? "").Trim();
        if (needle.Length == 0) return null;
        var lower = needle.ToLower();
        var byVa = await db.PosPaymentGatewaySettings.AsNoTracking()
            .Where(x => x.TingeeEnabled && x.Deleted == null
                && x.TingeeVaAccountNumber != null
                && x.TingeeVaAccountNumber.ToLower() == lower)
            .OrderBy(x => x.CreatedAt)
            .Take(20)
            .ToListAsync(ct);
        if (byVa.Count > 0) return await PickAmongSharedAccountAsync(byVa, payload, ct);

        var storeIds = await db.BankAccounts.AsNoTracking()
            .Where(b => b.IsActive && b.Deleted == null && b.AccountNumber.ToLower() == lower && b.StoreId != null)
            .Select(b => b.StoreId!.Value)
            .Distinct()
            .Take(20)
            .ToListAsync(ct);
        if (storeIds.Count == 0) return null;
        var byBank = await db.PosPaymentGatewaySettings.AsNoTracking()
            .Where(x => storeIds.Contains(x.StoreId) && x.TingeeEnabled && x.Deleted == null)
            .OrderBy(x => x.CreatedAt)
            .ToListAsync(ct);
        return byBank.Count == 0 ? null : await PickAmongSharedAccountAsync(byBank, payload, ct);
    }

    /// <summary>
    /// Số tài khoản không có ràng buộc duy nhất giữa các cửa hàng. Nhiều cửa hàng cùng khai một số tài khoản →
    /// chọn cửa hàng đang có lệnh chờ khớp mã đơn trong nội dung chuyển khoản (hoặc, không có mã, là cửa hàng DUY
    /// NHẤT có lệnh chờ đúng số tiền). Trước đây lấy đại cửa hàng đầu tiên → tiền của cửa hàng A ghi cho cửa hàng B.
    /// Không phân định được → giữ cách cũ (cửa hàng khai trước).
    /// </summary>
    async Task<PosPaymentGatewaySetting> PickAmongSharedAccountAsync(
        List<PosPaymentGatewaySetting> candidates, PaymentWebhookPayload payload, CancellationToken ct)
    {
        if (candidates.Count == 1) return candidates[0];
        var ids = candidates.Select(c => c.StoreId).Distinct().ToList();
        var tokens = WebhookTokens(payload);
        if (tokens.Count > 0)
        {
            var byToken = await db.PosTransferPaymentIntents.AsNoTracking()
                .Where(x => x.Deleted == null && ids.Contains(x.StoreId)
                    && x.Status == PosTransferPaymentIntentStatus.Waiting
                    && (tokens.Contains(x.ExternalOrderId!) || tokens.Contains(x.OrderNo!)))
                .Select(x => x.StoreId).Distinct().Take(2).ToListAsync(ct);
            if (byToken.Count == 1) return candidates.First(c => c.StoreId == byToken[0]);
        }
        if (payload.Amount is decimal amount && amount > 0)
        {
            var since = DateTime.UtcNow.AddHours(-2);
            var byAmount = await db.PosTransferPaymentIntents.AsNoTracking()
                .Where(x => x.Deleted == null && ids.Contains(x.StoreId)
                    && x.Status == PosTransferPaymentIntentStatus.Waiting
                    && x.AmountExpected == amount && x.CreatedAt >= since)
                .Select(x => x.StoreId).Distinct().Take(2).ToListAsync(ct);
            if (byAmount.Count == 1) return candidates.First(c => c.StoreId == byAmount[0]);
        }
        return candidates[0];
    }

    static List<string> WebhookTokens(PaymentWebhookPayload payload)
    {
        var tokens = new List<string>();
        if (!string.IsNullOrWhiteSpace(payload.ExternalOrderId))
            tokens.Add(payload.ExternalOrderId.Trim());
        if (!string.IsNullOrWhiteSpace(payload.TransferContent))
        {
            tokens.AddRange(payload.TransferContent.Split(
                ' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        }
        return tokens.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    async Task<PosPaymentGatewaySetting?> FindTingeeSettingsByIntentAsync(
        PaymentWebhookPayload payload, CancellationToken ct)
    {
        foreach (var token in WebhookTokens(payload))
        {
            // Mã «TMP{ô}» và số hóa đơn trùng nhau giữa các cửa hàng: lệnh chờ khớp mã ở nhiều cửa hàng thì
            // không đoán (trước đây lấy lệnh mới nhất → đơn của cửa hàng khác tự hoàn tất).
            var stores = await db.PosTransferPaymentIntents.AsNoTracking()
                .Where(x => x.Deleted == null
                    && x.Status == PosTransferPaymentIntentStatus.Waiting
                    && (x.ExternalOrderId == token || x.OrderNo == token))
                .Select(x => x.StoreId).Distinct().Take(2).ToListAsync(ct);
            if (stores.Count != 1) continue;
            var storeId = stores[0];
            var settings = await db.PosPaymentGatewaySettings.AsNoTracking()
                .FirstOrDefaultAsync(x => x.StoreId == storeId && x.TingeeEnabled && x.Deleted == null, ct);
            if (settings != null) return settings;
        }
        return null;
    }

    sealed record WaitingCode(Guid Id, string? ExternalOrderId, string? OrderNo);

    private static PaymentGatewaySettingDto MapSetting(
        PosPaymentGatewaySetting s,
        PlatformTingeeSettingDto platform) => new(
        s.DefaultTransferProvider.ToString(),
        s.TingeeEnabled,
        platform.TingeeClientId,
        platform.HasTingeeSecretKey,
        s.TingeeVaAccountNumber,
        s.TingeeMerchantId,
        s.TingeeShopId,
        platform.HasTingeeWebhookSecret,
        platform.TingeeEnabled && platform.HasTingeeWebhookSecret);

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
