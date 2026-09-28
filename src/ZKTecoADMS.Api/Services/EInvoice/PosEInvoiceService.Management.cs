using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.EInvoice;

/// <summary>Kind: pdf (Base64) | url (mở trình duyệt) | html.</summary>
public record EInvoiceView(
    string Kind, string? Url, string? Base64, string? Html, string? FileName, string? LookupUrl,
    bool IsDraft = false);

/// <summary>Quản lý: xem hóa đơn, trang quản lý của hãng, tải danh sách từ hãng, đồng bộ hàng loạt, báo cáo.</summary>
public partial class PosEInvoiceService
{
    public object PortalInfo(PosEInvoiceSetting s)
    {
        var provider = NormalizeProvider(s.Provider);
        var (portal, lookup) = DefaultPortal(s, provider);
        if (!string.IsNullOrWhiteSpace(s.PortalUrl)) portal = s.PortalUrl.Trim();
        return new
        {
            provider,
            providerName = ProviderLabel(provider),
            enabled = s.Enabled,
            portalUrl = portal,
            lookupUrl = lookup,
            supportsDraft = provider is "Viettel" or "Easy",
            supportsProviderList = provider is "Viettel" or "Easy",
            supportsEmailTo = provider is not "Vnpt",
        };
    }

    static (string Portal, string? Lookup) DefaultPortal(PosEInvoiceSetting s, string provider)
    {
        switch (provider)
        {
            case "Easy":
            {
                var host = EasyInvoiceClient.NormalizeBaseUrl(s.ApiBaseUrl);
                // api.easyinvoice.vn / api.softdreams.vn = cổng API chung → trang chủ; domain riêng = portal DN.
                var portal = host.Contains("://api.", StringComparison.OrdinalIgnoreCase)
                    ? "https://easyinvoice.vn"
                    : host;
                return (portal, null);
            }
            case "Misa":
            {
                var test = (s.ApiBaseUrl ?? "").Contains("testapi", StringComparison.OrdinalIgnoreCase);
                return (test ? "https://testapp.meinvoice.vn" : "https://app.meinvoice.vn",
                    test ? "https://www.test.meinvoice.vn/tra-cuu" : "https://www.meinvoice.vn/tra-cuu");
            }
            case "Vnpt":
            {
                var admin = VnptInvoiceClient.NormalizeBaseUrl(s.ApiBaseUrl);
                return (string.IsNullOrWhiteSpace(admin) ? "https://vnpt-invoice.com.vn" : admin,
                    string.IsNullOrWhiteSpace(admin) ? null : VnptInvoiceClient.PortalLookupUrl(admin));
            }
            default:
                return ("https://vinvoice.viettel.vn", "https://vinvoice.viettel.vn/utilities/invoice-search");
        }
    }

    /// <summary>Cổng tra cứu HĐĐT quốc gia — hợp lệ cho mọi HĐ đã gửi CQT.</summary>
    public const string GdtLookupUrl = "https://hoadondientu.gdt.gov.vn";

    /// <summary>Thông tin in trên bill: link tra cứu (QR) + MST người bán.</summary>
    /// <remarks>PrintOnReceipt = false khi cửa hàng tắt «In mã QR HĐĐT trên hóa đơn».</remarks>
    public async Task<(string? LookupUrl, string? SellerTaxCode, bool PrintOnReceipt)> PrintInfoAsync(
        PosSaleOrder order, CancellationToken ct = default)
    {
        var st = (order.EInvoiceStatus ?? "").Trim();
        if (st is "" or "None" or "Skipped") return (null, null, false);
        var s = await db.PosEInvoiceSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == order.StoreId && x.Deleted == null, ct);
        if (s == null) return (null, null, false);
        var tax = string.IsNullOrWhiteSpace(s.SupplierTaxCode) ? null : s.SupplierTaxCode.Trim();
        return (OrderLookupUrl(order, s) ?? GdtLookupUrl, tax, s.PrintQrOnReceipt);
    }

    string? OrderLookupUrl(PosSaleOrder order, PosEInvoiceSetting s)
    {
        var provider = NormalizeProvider(order.EInvoiceProvider ?? s.Provider);
        var (_, lookup) = DefaultPortal(s, provider);
        if (provider == "Misa" && !string.IsNullOrWhiteSpace(order.EInvoiceReservationCode) && lookup != null)
            return $"{lookup}/?sc={Uri.EscapeDataString(order.EInvoiceReservationCode)}";
        return lookup;
    }

    /// <summary>Xem lại hóa đơn đã phát hành: PDF từ hãng (hoặc link xem).</summary>
    public async Task<EInvoiceView> GetViewAsync(PosSaleOrder order, CancellationToken ct = default)
    {
        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        var issuedOrCancelled =
            string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(order.EInvoiceStatus, "Cancelled", StringComparison.OrdinalIgnoreCase);
        // Nháp / chờ ký chưa có số / chưa xuất → bản xem trước (nháp) từ hãng.
        if (!issuedOrCancelled && string.IsNullOrWhiteSpace(order.EInvoiceNo))
            return await GetDraftPreviewAsync(order, settings, ct);

        var provider = NormalizeProvider(order.EInvoiceProvider ?? settings.Provider);
        var lookup = OrderLookupUrl(order, settings);
        var fileName = $"HDDT_{FirstNonEmpty(order.EInvoiceNo, order.OrderNo)}.pdf";

        switch (provider)
        {
            case "Viettel":
            {
                if (string.IsNullOrWhiteSpace(order.EInvoiceNo))
                    throw new InvalidOperationException("Hóa đơn Viettel chưa có số — Đồng bộ trước khi xem");
                var token = await viettel.GetAccessTokenAsync(
                    order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
                var f = await viettel.GetInvoiceFileAsync(
                    settings.ApiBaseUrl, token, settings.SupplierTaxCode, order.EInvoiceNo,
                    settings.TemplateCode, order.EInvoiceTransactionUuid, ct);
                if (!f.Ok)
                    throw new InvalidOperationException(f.Error ?? "Viettel không trả file hóa đơn");
                return new("pdf", null, Convert.ToBase64String(f.File!), null, f.FileName ?? fileName, lookup);
            }
            case "Easy":
            {
                var ikey = order.EInvoiceTransactionUuid
                    ?? throw new InvalidOperationException("Thiếu ikey Easy Invoice");
                var (pattern, _) = ResolveEasyPatternSerial(settings);
                var f = await easy.GetPdfAsync(
                    settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                    ikey, FirstNonEmpty(order.EInvoiceSeries, pattern), ct);
                if (!f.Ok)
                    throw new InvalidOperationException(f.Error ?? "Easy Invoice không trả file hóa đơn");
                return new("pdf", null, Convert.ToBase64String(f.Pdf!), null, fileName, lookup);
            }
            case "Misa":
            {
                var tid = order.EInvoiceReservationCode
                    ?? throw new InvalidOperationException("Thiếu mã tra cứu MISA — Đồng bộ trước khi xem");
                var token = await MisaTokenAsync(order.StoreId, settings, ct);
                var dl = await misa.DownloadPdfAsync(
                    settings.ApiBaseUrl, token, settings.SupplierTaxCode, tid,
                    MisaWithCode(settings), settings.SignType == 5, ct);
                if (dl.Ok && dl.Pdf != null)
                    return new("pdf", null, Convert.ToBase64String(dl.Pdf), null, fileName, lookup);
                if (dl.Ok && dl.Url != null)
                {
                    var linked = await misa.TryDownloadAsync(dl.Url, ct);
                    return linked != null
                        ? new("pdf", null, Convert.ToBase64String(linked), null, fileName, lookup)
                        : new("url", dl.Url, null, null, fileName, lookup);
                }
                var v = await misa.GetViewUrlAsync(settings.ApiBaseUrl, token, settings.SupplierTaxCode, tid, ct);
                if (!v.Ok)
                    throw new InvalidOperationException(v.Error ?? dl.Error ?? "MISA không trả hóa đơn");
                var fetched = await misa.TryDownloadAsync(v.Url!, ct);
                return fetched != null
                    ? new("pdf", null, Convert.ToBase64String(fetched), null, fileName, lookup)
                    : new("url", v.Url, null, null, fileName, lookup);
            }
            case "Vnpt":
            {
                var fkey = order.EInvoiceTransactionUuid
                    ?? throw new InvalidOperationException("Thiếu fkey VNPT");
                var pdf = await vnpt.DownloadPdfAsync(settings.ApiBaseUrl, settings.Username, settings.Password, fkey, ct);
                if (pdf.Ok)
                    return new("pdf", null, Convert.ToBase64String(pdf.Pdf!), null, fileName, lookup);
                var html = await vnpt.ViewHtmlAsync(settings.ApiBaseUrl, settings.Username, settings.Password, fkey, ct);
                if (!html.Ok)
                    throw new InvalidOperationException(pdf.Error ?? html.Error ?? "VNPT không trả hóa đơn");
                return new("html", null, null, html.Html, fileName, lookup);
            }
            default:
                throw new InvalidOperationException($"Nhà cung cấp {provider} chưa hỗ trợ xem hóa đơn");
        }
    }

    /// <summary>
    /// Bản NHÁP (chưa ký, chưa có giá trị pháp lý) để gửi khách xác nhận thông tin trước khi phát hành.
    /// Không lưu gì trên hãng (trừ Easy: đã có nháp thì lấy PDF nháp).
    /// </summary>
    async Task<EInvoiceView> GetDraftPreviewAsync(PosSaleOrder order, PosEInvoiceSetting settings, CancellationToken ct)
    {
        if (!settings.Enabled)
            throw new InvalidOperationException("Chưa bật hóa đơn điện tử cho cửa hàng");
        var provider = NormalizeProvider(settings.Provider);
        var missing = MissingConfig(settings, provider);
        if (missing != null) throw new InvalidOperationException(missing);

        if (string.IsNullOrWhiteSpace(order.EInvoiceBuyerName) &&
            string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode))
            ApplyBuyerSnapshot(order, await BuyerFromCustomerAsync(order, ct));

        var lines = await LoadLinesAsync(order, ct);
        if (lines.Count == 0) throw new InvalidOperationException("Đơn không có hàng hóa");
        var fileName = $"HDDT_NHAP_{order.OrderNo}.pdf";
        var lookup = OrderLookupUrl(order, settings);

        // Mã giao dịch tạm cho bản xem trước — không ghi vào đơn.
        var savedUuid = order.EInvoiceTransactionUuid;
        var hasDraftOnProvider = !string.IsNullOrWhiteSpace(savedUuid) &&
            string.Equals(order.EInvoiceStatus, "Draft", StringComparison.OrdinalIgnoreCase);
        order.EInvoiceTransactionUuid = savedUuid ?? Guid.NewGuid().ToString();
        try
        {
            switch (provider)
            {
                case "Viettel":
                {
                    var token = await viettel.GetAccessTokenAsync(
                        order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
                    var pdf = await viettel.PreviewDraftAsync(
                        settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                        BuildViettelPayload(order, lines, settings), ct);
                    if (!pdf.Ok) throw new InvalidOperationException(pdf.Error ?? "Viettel không trả bản nháp");
                    return new("pdf", null, Convert.ToBase64String(pdf.File!), null, fileName, lookup, IsDraft: true);
                }
                case "Easy":
                {
                    var (pattern, serial) = ResolveEasyPatternSerial(settings);
                    if (hasDraftOnProvider)
                    {
                        var existing = await easy.GetPdfAsync(
                            settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                            savedUuid!, pattern, ct);
                        if (existing.Ok)
                            return new("pdf", null, Convert.ToBase64String(existing.Pdf!), null, fileName, lookup, IsDraft: true);
                    }
                    var pdf = await easy.PreviewAsync(
                        settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                        BuildEasyXml(order, lines, settings), pattern, serial, ct);
                    if (!pdf.Ok) throw new InvalidOperationException(pdf.Error ?? "Easy Invoice không trả bản nháp");
                    return new("pdf", null, Convert.ToBase64String(pdf.Pdf!), null, fileName, lookup, IsDraft: true);
                }
                case "Misa":
                {
                    var token = await MisaTokenAsync(order.StoreId, settings, ct);
                    var v = await misa.GetPreviewUrlAsync(
                        settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                        BuildMisaInvoiceData(order, lines, settings, replace: null), ct);
                    if (!v.Ok) throw new InvalidOperationException(v.Error ?? "MISA không trả bản nháp");
                    // Link MISA chỉ sống ~30 giây → tải PDF về luôn để còn gửi qua ứng dụng khác.
                    var bytes = await misa.TryDownloadAsync(v.Url!, ct);
                    return bytes != null
                        ? new("pdf", null, Convert.ToBase64String(bytes), null, fileName, lookup, IsDraft: true)
                        : new("url", v.Url, null, null, fileName, lookup, IsDraft: true);
                }
                default:
                    throw new InvalidOperationException(
                        $"{ProviderLabel(provider)} không có API xem trước hóa đơn nháp — phát hành rồi xem lại PDF");
            }
        }
        finally
        {
            order.EInvoiceTransactionUuid = savedUuid;
        }
    }

    /// <summary>
    /// Tải danh sách hóa đơn trực tiếp từ hãng trong khoảng ngày và đối chiếu với đơn POS
    /// (phát hiện HĐ lập ngoài POS / HĐ POS chưa có trên hãng).
    /// </summary>
    public async Task<object> ProviderListAsync(
        Guid storeId, DateTime fromUtc, DateTime toUtc, int page, int pageSize, CancellationToken ct = default)
    {
        var settings = await GetOrCreateSettingsAsync(storeId, ct);
        var provider = NormalizeProvider(settings.Provider);
        var fromLocal = fromUtc.AddHours(7).Date;
        var toLocal = toUtc.AddHours(7).AddSeconds(-1).Date;
        if (toLocal < fromLocal) toLocal = fromLocal;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 100);

        var rows = new List<ProviderRow>();
        int total;
        switch (provider)
        {
            case "Viettel":
            {
                if ((toLocal - fromLocal).TotalDays > 92)
                    throw new InvalidOperationException("Viettel chỉ cho tra cứu tối đa 3 tháng / lần — thu hẹp khoảng ngày");
                var token = await viettel.GetAccessTokenAsync(
                    storeId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
                var r = await viettel.GetInvoicesAsync(
                    settings.ApiBaseUrl, token, settings.SupplierTaxCode, fromLocal, toLocal, page, pageSize, ct);
                if (!r.Ok) throw new InvalidOperationException(r.Error ?? "Viettel không trả danh sách hóa đơn");
                total = r.Total;
                rows.AddRange(r.Items.Select(i => new ProviderRow(
                    i.InvoiceNo, FirstNonEmpty(i.InvoiceSeri, i.TemplateCode), i.IssueDate, i.BuyerName,
                    i.Total, i.TaxAmount, ViettelAdjustmentLabel(i.AdjustmentType), null, null,
                    i.AdjustmentType == "7")));
                break;
            }
            case "Easy":
            {
                var r = await easy.ListByArisingDateAsync(
                    settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                    fromLocal, toLocal, page, pageSize, ct);
                if (!r.Ok) throw new InvalidOperationException(r.Error ?? "Easy Invoice không trả danh sách hóa đơn");
                total = r.Total;
                rows.AddRange(r.Items.Select(i => new ProviderRow(
                    i.No, FirstNonEmpty(i.Pattern, i.Serial),
                    DateTime.TryParseExact(i.ArisingDate, "dd/MM/yyyy", null,
                        System.Globalization.DateTimeStyles.None, out var d) ? d.AddHours(-7) : null,
                    i.CustomerName, i.Amount, 0, EasyStatusLabel(i.InvoiceStatus), i.Ikey, i.LinkView,
                    i.InvoiceStatus is 3 or 5)));
                break;
            }
            default:
                return new
                {
                    supported = false,
                    provider,
                    message = $"{ProviderLabel(provider)} chưa có API lấy danh sách hóa đơn theo ngày. " +
                              "Dùng «Đồng bộ hàng loạt» để cập nhật trạng thái các hóa đơn POS, " +
                              "hoặc mở trang quản lý của hãng để xem toàn bộ.",
                    total = 0,
                    page,
                    pageSize,
                    items = Array.Empty<object>(),
                };
        }

        // Đối chiếu với đơn POS theo số HĐ / ikey.
        var nos = rows.Select(r => r.InvoiceNo).Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToList();
        var keys = rows.Select(r => r.Key).Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToList();
        var matches = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null &&
                        ((o.EInvoiceNo != null && nos.Contains(o.EInvoiceNo)) ||
                         (o.EInvoiceTransactionUuid != null && keys.Contains(o.EInvoiceTransactionUuid))))
            .Select(o => new { o.Id, o.OrderNo, o.EInvoiceNo, o.EInvoiceTransactionUuid, o.EInvoiceStatus })
            .ToListAsync(ct);

        var items = rows.Select(r =>
        {
            var m = matches.FirstOrDefault(o =>
                (!string.IsNullOrWhiteSpace(r.Key) && o.EInvoiceTransactionUuid == r.Key) ||
                (!string.IsNullOrWhiteSpace(r.InvoiceNo) && o.EInvoiceNo == r.InvoiceNo));
            var mismatch = m != null && r.Cancelled &&
                           !string.Equals(m.EInvoiceStatus, "Cancelled", StringComparison.OrdinalIgnoreCase);
            return new
            {
                invoiceNo = r.InvoiceNo,
                series = r.Series,
                issuedAt = r.IssuedAt,
                buyerName = r.BuyerName,
                amount = r.Amount,
                taxAmount = r.TaxAmount,
                providerStatus = r.StatusLabel,
                cancelled = r.Cancelled,
                key = r.Key,
                viewUrl = r.ViewUrl,
                orderId = m?.Id,
                orderNo = m?.OrderNo,
                localStatus = m?.EInvoiceStatus,
                statusMismatch = mismatch,
            };
        }).ToList();

        return new
        {
            supported = true,
            provider,
            message = (string?)null,
            total,
            page,
            pageSize,
            matchedCount = items.Count(i => i.orderId != null),
            outsidePosCount = items.Count(i => i.orderId == null),
            mismatchCount = items.Count(i => i.statusMismatch),
            items,
        };
    }

    sealed record ProviderRow(
        string? InvoiceNo, string? Series, DateTime? IssuedAt, string? BuyerName,
        decimal Amount, decimal TaxAmount, string StatusLabel, string? Key, string? ViewUrl, bool Cancelled);

    static string ViettelAdjustmentLabel(string? t) => t switch
    {
        "1" => "Hóa đơn gốc",
        "3" => "Hóa đơn thay thế",
        "5" => "Điều chỉnh thông tin",
        "7" => "Đã xóa bỏ",
        "9" => "Điều chỉnh tiền",
        _ => "Hóa đơn",
    };

    static string EasyStatusLabel(int st) => st switch
    {
        -1 => "Chờ ký",
        0 => "Chưa ký số",
        1 => "Đã ký số",
        2 => "Đã khai báo thuế",
        3 => "Bị thay thế",
        4 => "Bị điều chỉnh",
        5 => "Đã hủy",
        6 => "Đã duyệt",
        _ => $"Trạng thái {st}",
    };

    /// <summary>Đồng bộ hàng loạt trạng thái HĐ POS với hãng trong khoảng ngày (tối đa 100 đơn / lần).</summary>
    public async Task<object> SyncRangeAsync(
        Guid storeId, DateTime fromUtc, DateTime toUtc, CancellationToken ct = default)
    {
        var settings = await GetOrCreateSettingsAsync(storeId, ct);
        var provider = NormalizeProvider(settings.Provider);
        var orders = await db.PosSaleOrders
            .Where(o => o.StoreId == storeId && o.Deleted == null &&
                        o.Status == Domain.Enums.PosSaleOrderStatus.Completed &&
                        o.SaleDate >= fromUtc && o.SaleDate < toUtc &&
                        o.EInvoiceTransactionUuid != null &&
                        (o.EInvoiceProvider == null || o.EInvoiceProvider == provider) &&
                        (o.EInvoiceStatus == "Issued" || o.EInvoiceStatus == "Pending" ||
                         o.EInvoiceStatus == "Draft" || o.EInvoiceStatus == "Failed"))
            .OrderByDescending(o => o.SaleDate)
            .Take(100)
            .ToListAsync(ct);

        int ok = 0, failed = 0, changed = 0;
        var errors = new List<string>();
        foreach (var order in orders)
        {
            var before = $"{order.EInvoiceStatus}|{order.EInvoiceNo}";
            try
            {
                await SyncAsync(order, ct);
                ok++;
                if (before != $"{order.EInvoiceStatus}|{order.EInvoiceNo}") changed++;
            }
            catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
            {
                failed++;
                if (errors.Count < 5) errors.Add($"{order.OrderNo}: {ex.Message}");
            }
        }
        return new { total = orders.Count, synced = ok, changed, failed, errors, limited = orders.Count == 100 };
    }

    /// <summary>Báo cáo HĐĐT theo ngày + theo loại + theo hãng (giờ VN).</summary>
    public async Task<object> ReportAsync(Guid storeId, DateTime fromUtc, DateTime toUtc, CancellationToken ct = default)
    {
        var rows = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null &&
                        o.Status == Domain.Enums.PosSaleOrderStatus.Completed &&
                        o.SaleDate >= fromUtc && o.SaleDate < toUtc)
            .Select(o => new
            {
                o.SaleDate,
                o.Total,
                o.VatAmount,
                o.EInvoiceStatus,
                o.EInvoiceProvider,
                o.EInvoiceKind,
            })
            .ToListAsync(ct);

        static bool Is(string? a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

        var daily = rows
            .GroupBy(r => (r.SaleDate ?? DateTime.UtcNow).AddHours(7).Date)
            .OrderBy(g => g.Key)
            .Select(g => new
            {
                date = g.Key.ToString("yyyy-MM-dd"),
                orders = g.Count(),
                revenue = g.Sum(r => r.Total + r.VatAmount),
                issuedCount = g.Count(r => Is(r.EInvoiceStatus, "Issued")),
                issuedAmount = g.Where(r => Is(r.EInvoiceStatus, "Issued")).Sum(r => r.Total + r.VatAmount),
                vatAmount = g.Where(r => Is(r.EInvoiceStatus, "Issued")).Sum(r => r.VatAmount),
                failedCount = g.Count(r => Is(r.EInvoiceStatus, "Failed")),
                cancelledCount = g.Count(r => Is(r.EInvoiceStatus, "Cancelled")),
            })
            .ToList();

        var byProvider = rows
            .Where(r => Is(r.EInvoiceStatus, "Issued"))
            .GroupBy(r => NormalizeProvider(r.EInvoiceProvider))
            .Select(g => new
            {
                provider = g.Key,
                providerName = ProviderLabel(g.Key),
                count = g.Count(),
                amount = g.Sum(r => r.Total + r.VatAmount),
            })
            .ToList();

        var revenue = rows.Sum(r => r.Total + r.VatAmount);
        var issuedAmount = rows.Where(r => Is(r.EInvoiceStatus, "Issued")).Sum(r => r.Total + r.VatAmount);
        return new
        {
            from = fromUtc,
            to = toUtc,
            revenue,
            issuedAmount,
            coveragePct = revenue > 0 ? Math.Round(issuedAmount / revenue * 100, 1) : 0,
            originalCount = rows.Count(r => Is(r.EInvoiceStatus, "Issued") && !Is(r.EInvoiceKind, "Replacement")),
            replacementCount = rows.Count(r => Is(r.EInvoiceKind, "Replacement")),
            daily,
            byProvider,
        };
    }
}
