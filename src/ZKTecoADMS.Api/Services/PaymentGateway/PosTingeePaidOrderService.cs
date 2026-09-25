using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public interface IPosTingeePaidOrderService
{
    Task<bool> IsTingeeEnabledAsync(Guid storeId, CancellationToken ct = default);
    Task<object?> BuildGuestPaymentAsync(
        Guid storeId,
        PosSaleOrder? order,
        decimal amount,
        string? tableLabel,
        bool paid,
        CancellationToken ct = default);
    Task UpsertWaitingIntentAsync(
        Guid storeId,
        PosSaleOrder order,
        decimal amount,
        string? tableName,
        CancellationToken ct = default);
    /// <summary>Hoàn tất đơn đã nhận CK. Trả câu cảnh báo để đọc loa (vd. chuyển thiếu), null nếu không có.</summary>
    Task<string?> TryFulfillConfirmedIntentAsync(
        PosTransferPaymentIntent intent,
        decimal? paidAmount,
        IHubContext<AttendanceHub>? hub,
        ISystemNotificationService notifications,
        CancellationToken ct = default);
}

public sealed class PosTingeePaidOrderService(
    ZKTecoDbContext db,
    IPosPrintDispatchService dispatch,
    ILogger<PosTingeePaidOrderService> logger) : IPosTingeePaidOrderService
{
    public async Task<bool> IsTingeeEnabledAsync(Guid storeId, CancellationToken ct = default)
    {
        var s = await db.PosPaymentGatewaySettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        return s is { TingeeEnabled: true };
    }

    public async Task<object?> BuildGuestPaymentAsync(
        Guid storeId,
        PosSaleOrder? order,
        decimal amount,
        string? tableLabel,
        bool paid,
        CancellationToken ct = default)
    {
        var (bank, tingee) = await ResolvePayBankAsync(storeId, ct);
        if (bank == null) return null;

        var addInfo = TransferMemo(order?.OrderNo, tableLabel, tingee);
        var qrUrl = VietQRBanks.GenerateVietQRUrl(
            bank.BankCode,
            bank.AccountNumber,
            amount > 0 && !paid ? amount : null,
            addInfo,
            string.IsNullOrWhiteSpace(bank.VietQRTemplate) ? "compact2" : bank.VietQRTemplate);
        return new
        {
            qrUrl,
            amount,
            addInfo,
            bankName = bank.BankShortName ?? bank.BankName,
            accountName = bank.AccountName,
            accountNumber = bank.AccountNumber,
            orderNo = order?.OrderNo,
            orderId = order?.Id,
            tingee,
            paid,
        };
    }

    public async Task UpsertWaitingIntentAsync(
        Guid storeId,
        PosSaleOrder order,
        decimal amount,
        string? tableName,
        CancellationToken ct = default)
    {
        if (!await IsTingeeEnabledAsync(storeId, ct)) return;
        if (amount <= 0) return;
        if (order.Status != PosSaleOrderStatus.Draft) return;

        var externalId = ExternalIdOf(order);
        var existing = await db.PosTransferPaymentIntents.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId
                && x.ExternalOrderId == externalId
                && x.Status == PosTransferPaymentIntentStatus.Waiting
                && x.Deleted == null, ct);
        if (existing != null)
        {
            existing.AmountExpected = amount;
            existing.OrderNo = order.OrderNo;
            existing.SaleOrderId = order.Id;
            existing.TableName = tableName?.Trim();
            existing.ExpiresAt = DateTime.UtcNow.AddMinutes(90);
            existing.UpdatedAt = DateTime.UtcNow;
            existing.UpdatedBy = "qr-guest";
            await db.SaveChangesAsync(ct);
            return;
        }

        db.PosTransferPaymentIntents.Add(new PosTransferPaymentIntent
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = order.Id,
            ExternalOrderId = externalId,
            OrderNo = order.OrderNo,
            AmountExpected = amount,
            Provider = PosPaymentNotifyProvider.Tingee,
            Status = PosTransferPaymentIntentStatus.Waiting,
            ExpiresAt = DateTime.UtcNow.AddMinutes(90),
            TableName = tableName?.Trim(),
            IsActive = true,
            CreatedBy = "qr-guest",
        });
        await db.SaveChangesAsync(ct);
    }

    public async Task<string?> TryFulfillConfirmedIntentAsync(
        PosTransferPaymentIntent intent,
        decimal? paidAmount,
        IHubContext<AttendanceHub>? hub,
        ISystemNotificationService notifications,
        CancellationToken ct = default)
    {
        try
        {
            return await FulfillCoreAsync(intent, paidAmount, hub, notifications, ct);
        }
        catch (Exception ex)
        {
            // Webhook đã xác nhận CK — không rollback tiền; thu ngân hoàn tất thủ công.
            logger.LogError(ex, "Tingee: không tự hoàn tất được đơn {OrderNo} (intent {IntentId})",
                intent.OrderNo ?? intent.ExternalOrderId, intent.Id);
            return null;
        }
    }

    async Task<string?> FulfillCoreAsync(
        PosTransferPaymentIntent intent,
        decimal? paidAmount,
        IHubContext<AttendanceHub>? hub,
        ISystemNotificationService notifications,
        CancellationToken ct)
    {
        var storeId = intent.StoreId;
        PosSaleOrder? order = null;
        if (intent.SaleOrderId is Guid oid)
        {
            order = await db.PosSaleOrders.AsTracking()
                .Include(o => o.Lines)
                .FirstOrDefaultAsync(o => o.Id == oid && o.StoreId == storeId && o.Deleted == null, ct);
        }
        if (order == null)
        {
            var tokens = new[] { intent.OrderNo, intent.ExternalOrderId }
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x!.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
            foreach (var token in tokens)
            {
                order = await db.PosSaleOrders.AsTracking()
                    .Include(o => o.Lines)
                    .Where(o => o.StoreId == storeId && o.Deleted == null
                        && (o.OrderNo == token))
                    .OrderByDescending(o => o.CreatedAt)
                    .FirstOrDefaultAsync(ct);
                if (order != null) break;
            }
        }
        if (order == null) return null;

        intent.SaleOrderId ??= order.Id;
        if (string.IsNullOrWhiteSpace(intent.OrderNo))
            intent.OrderNo = order.OrderNo;

        // So với tổng đơn HIỆN TẠI — thu ngân có thể thêm món sau khi khách mở QR;
        // intent chỉ là 1 phần (CK + tiền mặt) thì để máy thu ngân hoàn tất.
        var orderDue = order.PayableTotal > 0 ? order.PayableTotal : order.Total;
        var expected = Math.Max(intent.AmountExpected, orderDue);
        var paid = paidAmount is > 0 ? paidAmount.Value : expected;
        if (expected > 0 && paid + 1m < expected)
            return null;

        var online = PosOnlineOrderHelper.IsQrOnlineOrder(order);
        var closeTable = !online && (order.ServiceResourceId.HasValue || order.ResourceSessionId.HasValue);

        if (order.Status == PosSaleOrderStatus.Draft)
        {
            var (ok, err) = await PosOnlineOrderHelper.TryCompletePaidDraftAsync(
                db, storeId, order, "tingee-webhook", "Tingee", paid, closeTable, ct);
            if (!ok)
            {
                logger.LogWarning("Tingee: không hoàn tất được đơn {OrderNo}: {Error}", order.OrderNo, err);
                return $"Đã nhận chuyển khoản {paid:0} đồng nhưng chưa hoàn tất được đơn {order.OrderNo}. Thu ngân kiểm tra lại";
            }
        }
        else if (order.Status != PosSaleOrderStatus.Completed)
        {
            return null;
        }

        if (online)
        {
            var st = QrOnlineOrderStatuses.Normalize(order.DeliveryStatus);
            if (st is QrOnlineOrderStatuses.Pending or "")
            {
                order.DeliveryStatus = QrOnlineOrderStatuses.Preparing;
                order.UpdatedAt = DateTime.UtcNow;
                order.UpdatedBy = "tingee-webhook";
            }
            await TryEnqueueOnlineKitchenAsync(storeId, order, ct);
        }

        intent.Status = PosTransferPaymentIntentStatus.Completed;
        intent.CompletedAt ??= DateTime.UtcNow;
        intent.UpdatedAt = DateTime.UtcNow;
        intent.UpdatedBy = "tingee-webhook";
        await db.SaveChangesAsync(ct);

        var table = intent.TableName ?? (online ? "Online" : null);
        var spoken = paid > 0
            ? $"Đã thanh toán {paid:0} đồng, đơn {order.OrderNo}"
            : $"Đã thanh toán đơn {order.OrderNo}";

        PosFloorRealtimeHelper.Notify(
            hub, storeId, online ? "qrOnlineStatus" : "saleCompleted",
            orderId: order.Id,
            resourceId: order.ServiceResourceId,
            tableName: table,
            message: spoken,
            orderNo: order.OrderNo);

        await PosNotificationHelper.NotifySaleCompletedAsync(
            notifications, db, storeId, order.Id, order.OrderNo ?? "",
            paid > 0 ? paid : order.PayableTotal, "Tingee", null, ct);
        return null;
    }

    async Task<(BankAccount? Bank, bool Tingee)> ResolvePayBankAsync(Guid storeId, CancellationToken ct)
    {
        var banks = await db.BankAccounts.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.IsActive && x.Deleted == null)
            .ToListAsync(ct);
        var gw = await db.PosPaymentGatewaySettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        var va = (gw?.TingeeVaAccountNumber ?? "").Trim();
        if (gw is { TingeeEnabled: true } && va.Length > 0)
        {
            var hit = banks.FirstOrDefault(b =>
                b.AccountNumber.Equals(va, StringComparison.OrdinalIgnoreCase));
            if (hit != null) return (hit, true);
            var shop = banks.FirstOrDefault(b => !IsVirtual(b.AccountNumber) && b.IsDefault)
                       ?? banks.FirstOrDefault(b => !IsVirtual(b.AccountNumber));
            if (shop != null)
            {
                return (new BankAccount
                {
                    Id = shop.Id,
                    AccountName = shop.AccountName,
                    AccountNumber = va,
                    BankCode = shop.BankCode,
                    BankName = shop.BankName,
                    BankShortName = shop.BankShortName,
                    VietQRTemplate = shop.VietQRTemplate,
                }, true);
            }
        }

        var fallback = banks.FirstOrDefault(b => !IsVirtual(b.AccountNumber) && b.IsDefault)
                       ?? banks.FirstOrDefault(b => !IsVirtual(b.AccountNumber))
                       ?? banks.FirstOrDefault();
        return (fallback, false);
    }

    async Task TryEnqueueOnlineKitchenAsync(Guid storeId, PosSaleOrder order, CancellationToken ct)
    {
        var lines = order.Lines.Where(l => l.Deleted == null).ToList();
        if (lines.Count == 0) return;
        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id, ct);

        var now = DateTime.UtcNow;
        var added = new List<(PosSaleOrderLine Line, decimal Qty, PosProduct Product)>();
        foreach (var line in lines)
        {
            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            var pending = line.Qty - line.KitchenSentQty;
            if (pending <= 0) continue;
            line.KitchenSentQty = line.Qty;
            line.KitchenSentAt = now;
            PosKitchenKdsHelper.OnSent(line);
            added.Add((line, pending, p));
        }
        if (added.Count == 0) return;
        await db.SaveChangesAsync(ct);

        var fallback = await dispatch.ResolvePrinterAsync(storeId, PosPrintDocumentType.KitchenSlip, ct);
        var groups = new Dictionary<Guid, List<(string Name, decimal Qty, string? Unit, string? Note)>>();
        foreach (var row in added)
        {
            var printerId = row.Product.DefaultPrinterId
                ?? row.Product.Category?.DefaultPrinterId
                ?? fallback?.Id;
            if (printerId == null) continue;
            if (!groups.TryGetValue(printerId.Value, out var list))
            {
                list = [];
                groups[printerId.Value] = list;
            }
            list.Add((row.Line.ProductName, row.Qty, row.Line.UnitName,
                PosSaleStockHelper.FormatToppingKitchenNote(row.Line.ToppingsJson, row.Line.LineNote)));
        }
        if (groups.Count == 0 && fallback != null)
        {
            groups[fallback.Id] = added.Select(r =>
                (r.Line.ProductName, r.Qty, r.Line.UnitName,
                    PosSaleStockHelper.FormatToppingKitchenNote(r.Line.ToppingsJson, r.Line.LineNote))).ToList();
        }

        var tbl = string.IsNullOrWhiteSpace(order.CustomerName)
            ? "Đơn online"
            : $"Online · {order.CustomerName}";
        var stamp = now.ToString("HHmmss");
        foreach (var g in groups)
        {
            var payload = JsonSerializer.Serialize(new
            {
                tableName = tbl,
                isCancel = false,
                senderName = "Tingee",
                orderNo = order.OrderNo ?? "",
                sentAt = now.ToUniversalTime().ToString("o"),
                lines = g.Value.Select(l => new
                {
                    productName = l.Name,
                    qty = l.Qty,
                    unitName = l.Unit,
                    note = l.Note,
                }),
            });
            var refNo = $"QR|{order.OrderNo}|{stamp}|{g.Key.ToString("N")[..6]}";
            await dispatch.EnqueueJobAsync(new EnqueuePrintJobRequest(
                storeId,
                PosPrintDocumentType.KitchenSlip,
                PosPrintPayloadFormat.KitchenSlipJson,
                payload,
                1,
                refNo,
                order.Id,
                null,
                "Tingee",
                g.Key), ct);
        }
    }

    static bool IsVirtual(string? number)
    {
        var n = (number ?? "").Trim();
        return n.Length > 0 && n.Any(char.IsLetter);
    }

    static string ExternalIdOf(PosSaleOrder order)
    {
        var no = (order.OrderNo ?? "").Trim();
        return no.Length > 0 ? no : order.Id.ToString("N");
    }

    static string TransferMemo(string? orderNo, string? table, bool tingee)
    {
        var no = (orderNo ?? "").Trim();
        if (no.Length > 0)
            return no.Length > 25 ? no[..25] : no;
        if (tingee) return "QR ORDER";
        var raw = $"{table} {no}".Trim();
        var chars = raw.Where(c => char.IsLetterOrDigit(c) || c is ' ' or '-').ToArray();
        var s = new string(chars).Trim();
        if (s.Length > 25) s = s[..25];
        return string.IsNullOrWhiteSpace(s) ? "QR ORDER" : s;
    }
}
