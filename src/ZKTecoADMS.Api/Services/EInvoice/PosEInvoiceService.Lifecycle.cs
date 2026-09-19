using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.EInvoice;

public partial class PosEInvoiceService
{
    public static object Snapshot(PosSaleOrder order) => new
    {
        order.Id,
        order.OrderNo,
        order.EInvoiceStatus,
        order.EInvoiceProvider,
        order.EInvoiceNo,
        order.EInvoiceSeries,
        order.EInvoiceCode,
        order.EInvoiceReservationCode,
        order.EInvoiceIssuedAt,
        order.EInvoiceError,
        order.EInvoiceKind,
        order.EInvoiceOriginalNo,
        order.EInvoiceCancelledAt,
        order.EInvoiceCancelReason,
        order.EInvoiceEmailSentAt,
        order.EInvoiceEmailTo,
        order.EInvoiceBuyerName,
        order.EInvoiceBuyerEmail,
        order.EInvoiceBuyerTaxCode,
    };

    public async Task<object> ListAsync(
        Guid storeId,
        DateTime fromUtc,
        DateTime toUtc,
        string? status,
        string? q,
        int page,
        int pageSize,
        CancellationToken ct = default)
    {
        if (page < 1) page = 1;
        if (pageSize is < 1 or > 200) pageSize = 50;

        var query = db.PosSaleOrders.AsNoTracking().Where(o =>
            o.StoreId == storeId && o.Deleted == null &&
            o.Status == Domain.Enums.PosSaleOrderStatus.Completed &&
            o.SaleDate >= fromUtc && o.SaleDate < toUtc);

        if (!string.IsNullOrWhiteSpace(status) &&
            !status.Equals("all", StringComparison.OrdinalIgnoreCase))
        {
            var st = status.Trim();
            if (st.Equals("email", StringComparison.OrdinalIgnoreCase))
                query = query.Where(o => o.EInvoiceEmailSentAt != null);
            else if (st.Equals("replacement", StringComparison.OrdinalIgnoreCase))
                query = query.Where(o => o.EInvoiceKind == "Replacement");
            else
                query = query.Where(o => o.EInvoiceStatus == st);
        }

        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = q.Trim();
            query = query.Where(o =>
                o.OrderNo.Contains(s) ||
                (o.CustomerName != null && o.CustomerName.Contains(s)) ||
                (o.EInvoiceNo != null && o.EInvoiceNo.Contains(s)) ||
                (o.EInvoiceBuyerName != null && o.EInvoiceBuyerName.Contains(s)) ||
                (o.EInvoiceBuyerEmail != null && o.EInvoiceBuyerEmail.Contains(s)));
        }

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(o => o.SaleDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                o.SaleDate,
                o.Total,
                o.VatAmount,
                o.CustomerName,
                o.EInvoiceStatus,
                o.EInvoiceProvider,
                o.EInvoiceNo,
                o.EInvoiceSeries,
                o.EInvoiceCode,
                o.EInvoiceReservationCode,
                o.EInvoiceIssuedAt,
                o.EInvoiceError,
                o.EInvoiceKind,
                o.EInvoiceOriginalNo,
                o.EInvoiceCancelledAt,
                o.EInvoiceCancelReason,
                o.EInvoiceEmailSentAt,
                o.EInvoiceEmailTo,
                o.EInvoiceBuyerName,
                o.EInvoiceBuyerEmail,
                o.EInvoiceBuyerTaxCode,
            })
            .ToListAsync(ct);

        return new { items, total, page, pageSize };
    }

    public Task SaveDraftAsync(
        PosSaleOrder order, EInvoiceBuyerInput? buyer, CancellationToken ct = default) =>
        IssueNowAsync(order, buyer, draftOnly: true, ct);

    public async Task CancelAsync(
        PosSaleOrder order, string? reason, string? agreementDesc, CancellationToken ct = default)
    {
        if (!string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(order.EInvoiceStatus, "Pending", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(order.EInvoiceStatus, "Draft", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Chỉ hủy được hóa đơn đã xuất, nháp hoặc chờ ký");
        if (string.IsNullOrWhiteSpace(order.EInvoiceNo) &&
            string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
            throw new InvalidOperationException("Đơn chưa có số hóa đơn / mã giao dịch để hủy");

        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        var provider = NormalizeProvider(settings.Provider);
        var why = string.IsNullOrWhiteSpace(reason) ? "Hủy hóa đơn theo yêu cầu cửa hàng" : reason.Trim();
        var agree = string.IsNullOrWhiteSpace(agreementDesc) ? why : agreementDesc.Trim();

        if (provider == "Viettel")
        {
            if (string.IsNullOrWhiteSpace(order.EInvoiceNo))
                throw new InvalidOperationException("Viettel cần số hóa đơn để hủy");
            var token = await viettel.GetAccessTokenAsync(
                order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
            var issued = order.EInvoiceIssuedAt ?? order.SaleDate ?? DateTime.UtcNow;
            var cancelled = await viettel.CancelInvoiceAsync(
                settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                order.EInvoiceNo, issued, agree, DateTime.UtcNow, why,
                settings.TemplateCode, ct);
            if (!cancelled.Ok)
                throw new InvalidOperationException(cancelled.Error ?? cancelled.ErrorCode ?? "Viettel từ chối hủy hóa đơn");
        }
        else if (provider == "Easy")
        {
            var (pattern, serial) = ResolveEasyPatternSerial(settings);
            var ikey = order.EInvoiceTransactionUuid
                ?? throw new InvalidOperationException("Easy Invoice cần ikey để hủy");
            var cancelled = await easy.CancelAsync(
                settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                ikey, pattern, serial, ct);
            if (!cancelled.Ok)
                throw new InvalidOperationException(cancelled.Error ?? cancelled.ErrorCode ?? "Easy Invoice từ chối hủy hóa đơn");
        }
        else
            throw new InvalidOperationException($"Nhà cung cấp {provider} chưa hỗ trợ hủy hóa đơn");

        order.EInvoiceStatus = "Cancelled";
        order.EInvoiceCancelledAt = DateTime.UtcNow;
        order.EInvoiceCancelReason = Trim(why, 400);
        order.EInvoiceError = null;
        await db.SaveChangesAsync(ct);
    }

    public async Task ReplaceAsync(
        PosSaleOrder order, string? reason, EInvoiceBuyerInput? buyer, CancellationToken ct = default)
    {
        if (!string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(order.EInvoiceNo))
            throw new InvalidOperationException("Chỉ thay thế được hóa đơn đã phát hành có số");

        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        if (!settings.Enabled)
            throw new InvalidOperationException("Chưa bật hóa đơn điện tử cho cửa hàng");

        var provider = NormalizeProvider(settings.Provider);
        var originalNo = order.EInvoiceNo!;
        var originalIssued = order.EInvoiceIssuedAt ?? order.SaleDate ?? DateTime.UtcNow;
        var why = string.IsNullOrWhiteSpace(reason)
            ? $"Thay thế hóa đơn {originalNo}"
            : reason.Trim();

        ApplyBuyerSnapshot(order, buyer ?? await BuyerFromCustomerAsync(order, ct));
        if (string.IsNullOrWhiteSpace(order.EInvoiceBuyerName))
            order.EInvoiceBuyerName = order.CustomerName;

        order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        order.EInvoiceProvider = provider;
        order.EInvoiceKind = "Replacement";
        order.EInvoiceOriginalNo = originalNo;
        order.EInvoiceStatus = "Pending";
        order.EInvoiceError = null;
        order.EInvoiceNo = null;
        order.EInvoiceCode = null;
        order.EInvoiceReservationCode = null;
        await db.SaveChangesAsync(ct);

        var lines = await LoadLinesAsync(order, ct);
        var origMs = new DateTimeOffset(DateTime.SpecifyKind(originalIssued, DateTimeKind.Utc))
            .ToUnixTimeMilliseconds();
        var agreeDate = DateTime.UtcNow.AddHours(7).ToString("yyyyMMddHHmmss");

        try
        {
            if (provider == "Easy")
            {
                await IssueEasyAsync(
                    order, lines, settings,
                    draftOnly: false, signExistingDraft: false,
                    easyType: 2, originalNo: originalNo, ct: ct);
            }
            else
            {
                await IssueViettelAsync(
                    order, lines, settings, draftOnly: false,
                    opts: new ViettelIssueOpts(
                        AdjustmentType: "3",
                        OriginalInvoiceId: originalNo,
                        OriginalInvoiceIssueDate: origMs,
                        AdditionalReferenceDesc: why,
                        AdditionalReferenceDate: agreeDate,
                        InvoiceNote: why),
                    ct: ct);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Replace e-invoice failed for order {OrderNo}", order.OrderNo);
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = Trim(ex.Message, 1000);
            order.EInvoiceNo = originalNo;
            await db.SaveChangesAsync(ct);
            throw;
        }

        if (string.Equals(order.EInvoiceStatus, "Failed", StringComparison.OrdinalIgnoreCase))
        {
            order.EInvoiceNo = originalNo;
            await db.SaveChangesAsync(ct);
            throw new InvalidOperationException(order.EInvoiceError ?? "Nhà cung cấp từ chối hóa đơn thay thế");
        }

        order.EInvoiceKind = "Replacement";
        order.EInvoiceOriginalNo = originalNo;
        await db.SaveChangesAsync(ct);
    }

    public async Task SendEmailAsync(PosSaleOrder order, string? email, CancellationToken ct = default)
    {
        if (!string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Chỉ gửi email cho hóa đơn đã phát hành");

        var to = FirstNonEmpty(email, order.EInvoiceBuyerEmail);
        if (string.IsNullOrWhiteSpace(to))
            throw new InvalidOperationException("Chưa có email khách hàng để gửi hóa đơn");

        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        if (!string.IsNullOrWhiteSpace(email))
            order.EInvoiceBuyerEmail = email.Trim();

        await SendBuyerEmailCoreAsync(order, settings, to.Trim(), ct);
        await db.SaveChangesAsync(ct);
    }

    public async Task SyncAsync(PosSaleOrder order, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
            throw new InvalidOperationException("Đơn chưa có mã giao dịch HĐĐT để đồng bộ");

        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        var provider = NormalizeProvider(settings.Provider);

        if (provider == "Viettel")
        {
            var token = await viettel.GetAccessTokenAsync(
                order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
            var found = await viettel.SearchByTransactionUuidAsync(
                settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                order.EInvoiceTransactionUuid, ct);
            if (!found.Ok)
                throw new InvalidOperationException(found.Error ?? "Không tìm thấy hóa đơn trên Viettel");
            ApplyViettelResult(
                order, settings, found,
                string.IsNullOrWhiteSpace(found.InvoiceNo) ? "Pending" : "Issued");
            order.EInvoiceError = string.IsNullOrWhiteSpace(found.InvoiceNo)
                ? "Đã đồng bộ — hóa đơn chưa có số (có thể còn nháp)"
                : null;
        }
        else if (provider == "Easy")
        {
            var found = await easy.LookupByIkeyAsync(
                settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                order.EInvoiceTransactionUuid, ct);
            if (!found.Ok)
                throw new InvalidOperationException(found.Error ?? "Không tìm thấy hóa đơn trên Easy Invoice");
            ApplyEasyResult(
                order, settings, found,
                string.IsNullOrWhiteSpace(found.InvoiceNo) ? "Draft" : "Issued");
            order.EInvoiceError = null;
        }
        else
            throw new InvalidOperationException($"Nhà cung cấp {provider} chưa hỗ trợ đồng bộ");

        await db.SaveChangesAsync(ct);
    }

    static void ResetInvoiceIdentity(PosSaleOrder order)
    {
        order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        order.EInvoiceNo = null;
        order.EInvoiceCode = null;
        order.EInvoiceReservationCode = null;
        order.EInvoiceIssuedAt = null;
        order.EInvoiceKind = null;
        order.EInvoiceOriginalNo = null;
        order.EInvoiceCancelledAt = null;
        order.EInvoiceCancelReason = null;
        order.EInvoiceEmailSentAt = null;
        order.EInvoiceEmailTo = null;
        order.EInvoiceError = null;
    }

    async Task<List<PosSaleOrderLine>> LoadLinesAsync(PosSaleOrder order, CancellationToken ct)
    {
        var lines = order.Lines?.Where(l => l.Deleted == null).ToList();
        if (lines != null && lines.Count > 0) return lines;
        return await db.PosSaleOrderLines
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .ToListAsync(ct);
    }

    async Task TrySendBuyerEmailAsync(PosSaleOrder order, PosEInvoiceSetting settings, CancellationToken ct)
    {
        if (!string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase))
            return;
        var to = Trim(order.EInvoiceBuyerEmail, 200);
        if (to == null) return;
        try
        {
            await SendBuyerEmailCoreAsync(order, settings, to, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Auto-send e-invoice email failed for {OrderNo}", order.OrderNo);
            if (string.IsNullOrWhiteSpace(order.EInvoiceError))
                order.EInvoiceError = "Đã xuất — gửi email thất bại, thử gửi lại từ quản lý HĐĐT";
            await db.SaveChangesAsync(ct);
        }
    }

    async Task SendBuyerEmailCoreAsync(
        PosSaleOrder order, PosEInvoiceSetting settings, string email, CancellationToken ct)
    {
        var provider = NormalizeProvider(settings.Provider);
        if (provider == "Viettel")
        {
            if (string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
                throw new InvalidOperationException("Thiếu transactionUuid để gửi email Viettel");
            var token = await viettel.GetAccessTokenAsync(
                order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
            var sent = await viettel.SendHtmlMailAsync(
                settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                order.EInvoiceTransactionUuid, ct);
            if (!sent.Ok)
                throw new InvalidOperationException(sent.Error ?? sent.ErrorCode ?? "Viettel từ chối gửi email");
        }
        else if (provider == "Easy")
        {
            var ikey = order.EInvoiceTransactionUuid
                ?? throw new InvalidOperationException("Thiếu ikey để gửi email Easy Invoice");
            var sent = await easy.SendMailAsync(
                settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                ikey, email, ct);
            if (!sent.Ok)
                throw new InvalidOperationException(sent.Error ?? sent.ErrorCode ?? "Easy Invoice từ chối gửi email");
        }
        else
            throw new InvalidOperationException($"Nhà cung cấp {provider} chưa hỗ trợ gửi email");

        order.EInvoiceEmailSentAt = DateTime.UtcNow;
        order.EInvoiceEmailTo = Trim(email, 200);
    }
}
