using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.EInvoice;

public record EInvoiceBuyerInput(
    string? Name,
    string? TaxCode,
    string? CompanyName,
    string? Address,
    string? Email,
    string? Phone);

public class PosEInvoiceService(
    ZKTecoDbContext db,
    ViettelSInvoiceClient viettel,
    EasyInvoiceClient easy,
    ILogger<PosEInvoiceService> logger)
{
    public async Task<PosEInvoiceSetting> GetOrCreateSettingsAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await db.PosEInvoiceSettings
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null, ct);
        if (row != null) return row;
        row = new PosEInvoiceSetting
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Enabled = false,
            Provider = "Viettel",
            ApiBaseUrl = "https://api-vinvoice.viettel.vn",
            TemplateCode = "1/001",
            InvoiceType = "1",
            AskAtCheckout = true,
            DefaultIssueAtCheckout = false,
            TaxMode = "included",
            DefaultTaxPercent = 10,
            IsActive = true,
        };
        db.PosEInvoiceSettings.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    public async Task SaveSettingsAsync(Guid storeId, PosEInvoiceSetting incoming, string? newPassword, CancellationToken ct = default)
    {
        var row = await GetOrCreateSettingsAsync(storeId, ct);
        row.Enabled = incoming.Enabled;
        row.Provider = NormalizeProvider(incoming.Provider);
        row.ApiBaseUrl = NormalizeBaseUrl(row.Provider, incoming.ApiBaseUrl);
        row.Username = (incoming.Username ?? "").Trim();
        if (!string.IsNullOrWhiteSpace(newPassword))
            row.Password = newPassword;
        row.SupplierTaxCode = (incoming.SupplierTaxCode ?? "").Trim();
        row.TemplateCode = string.IsNullOrWhiteSpace(incoming.TemplateCode) ? "1/001" : incoming.TemplateCode.Trim();
        row.InvoiceSeries = (incoming.InvoiceSeries ?? "").Trim();
        row.InvoiceType = string.IsNullOrWhiteSpace(incoming.InvoiceType) ? "1" : incoming.InvoiceType.Trim();
        row.AskAtCheckout = incoming.AskAtCheckout;
        row.DefaultIssueAtCheckout = incoming.DefaultIssueAtCheckout;
        row.TaxMode = string.IsNullOrWhiteSpace(incoming.TaxMode) ? "included" : incoming.TaxMode.Trim().ToLowerInvariant();
        row.DefaultTaxPercent = incoming.DefaultTaxPercent;
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        viettel.InvalidateToken(storeId);
    }

    public async Task<(bool Ok, string Message)> TestConnectionAsync(Guid storeId, CancellationToken ct = default)
    {
        var s = await GetOrCreateSettingsAsync(storeId, ct);
        var provider = NormalizeProvider(s.Provider);
        if (string.IsNullOrWhiteSpace(s.Username) || string.IsNullOrWhiteSpace(s.Password))
            return (false, "Chưa nhập tài khoản / mật khẩu nhà cung cấp HĐĐT");

        if (provider == "Easy")
        {
            if (string.IsNullOrWhiteSpace(s.SupplierTaxCode))
                return (false, "Easy Invoice cần MST người bán (taxCode trong token từ 01/01/2026)");
            return await easy.TestConnectionAsync(s.ApiBaseUrl, s.Username, s.Password, s.SupplierTaxCode, ct);
        }

        if (provider != "Viettel")
            return (false, $"Nhà cung cấp {s.Provider} chưa hỗ trợ kiểm tra kết nối");

        viettel.InvalidateToken(storeId);
        var login = await viettel.LoginAsync(s.ApiBaseUrl, s.Username, s.Password, ct);
        return login.Ok
            ? (true, "Đăng nhập Viettel SInvoice thành công")
            : (false, login.Error ?? "Đăng nhập thất bại");
    }

    /// <summary>Sau thanh toán: xuất nếu cashier chọn / cấu hình mặc định; không rollback đơn.</summary>
    public async Task HandleAfterCompleteAsync(
        PosSaleOrder order,
        bool? issueFlag,
        EInvoiceBuyerInput? buyer,
        CancellationToken ct = default)
    {
        var settings = await db.PosEInvoiceSettings.AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == order.StoreId && s.Deleted == null, ct);
        if (settings == null || !settings.Enabled)
            return;

        if (string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase))
            return;

        buyer ??= await BuyerFromCustomerAsync(order, ct);

        var want = issueFlag ?? settings.DefaultIssueAtCheckout;
        if (!want)
        {
            ApplyBuyerSnapshot(order, buyer);
            order.EInvoiceStatus = "Skipped";
            order.EInvoiceProvider = NormalizeProvider(settings.Provider);
            order.EInvoiceError = null;
            await db.SaveChangesAsync(ct);
            return;
        }

        await IssueNowAsync(order, buyer, ct);
    }

    public async Task IssueNowAsync(
        PosSaleOrder order,
        EInvoiceBuyerInput? buyer,
        CancellationToken ct = default)
    {
        var settings = await GetOrCreateSettingsAsync(order.StoreId, ct);
        if (!settings.Enabled)
            throw new InvalidOperationException("Chưa bật hóa đơn điện tử cho cửa hàng");
        if (string.Equals(order.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(order.EInvoiceNo))
            throw new InvalidOperationException($"Đơn đã xuất HĐĐT {order.EInvoiceNo}");

        var provider = NormalizeProvider(settings.Provider);
        if (provider == "Misa")
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceProvider = provider;
            order.EInvoiceError = "Nhà cung cấp MISA chưa hỗ trợ — hiện tại Viettel SInvoice và Easy Invoice";
            await db.SaveChangesAsync(ct);
            return;
        }

        if (string.IsNullOrWhiteSpace(settings.Username) ||
            string.IsNullOrWhiteSpace(settings.Password) ||
            string.IsNullOrWhiteSpace(settings.SupplierTaxCode) ||
            string.IsNullOrWhiteSpace(settings.InvoiceSeries) ||
            string.IsNullOrWhiteSpace(settings.TemplateCode))
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceProvider = provider;
            order.EInvoiceError = provider == "Easy"
                ? "Thiếu cấu hình Easy Invoice (tài khoản, MST, mẫu số Serial, ký hiệu Pattern)"
                : "Thiếu cấu hình Viettel (tài khoản, MST, mẫu, ký hiệu hóa đơn)";
            await db.SaveChangesAsync(ct);
            return;
        }

        ApplyBuyerSnapshot(order, buyer ?? await BuyerFromCustomerAsync(order, ct));
        if (string.IsNullOrWhiteSpace(order.EInvoiceBuyerName))
            order.EInvoiceBuyerName = order.CustomerName;

        if (string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
            order.EInvoiceTransactionUuid = Guid.NewGuid().ToString();
        order.EInvoiceProvider = provider;
        order.EInvoiceStatus = "Pending";
        order.EInvoiceError = null;
        await db.SaveChangesAsync(ct);

        var lines = order.Lines?.Where(l => l.Deleted == null).ToList();
        if (lines == null || lines.Count == 0)
        {
            lines = await db.PosSaleOrderLines
                .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
                .ToListAsync(ct);
        }

        try
        {
            if (provider == "Easy")
                await IssueEasyAsync(order, lines, settings, ct);
            else
                await IssueViettelAsync(order, lines, settings, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Issue e-invoice failed for order {OrderNo}", order.OrderNo);
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = Trim(ex.Message, 1000);
            await db.SaveChangesAsync(ct);
        }
    }

    async Task IssueViettelAsync(
        PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting settings, CancellationToken ct)
    {
        var payload = BuildViettelPayload(order, lines, settings);
        var token = await viettel.GetAccessTokenAsync(
            order.StoreId, settings.ApiBaseUrl, settings.Username, settings.Password, ct);
        var created = await viettel.CreateInvoiceAsync(
            settings.ApiBaseUrl, token, settings.SupplierTaxCode, payload, ct);

        if (!created.Ok && created.ErrorCode == "TIMEOUT" &&
            !string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
        {
            created = await viettel.SearchByTransactionUuidAsync(
                settings.ApiBaseUrl, token, settings.SupplierTaxCode,
                order.EInvoiceTransactionUuid, ct);
        }

        if (!created.Ok)
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = created.Error ?? created.ErrorCode ?? "Viettel từ chối hóa đơn";
            await db.SaveChangesAsync(ct);
            return;
        }

        order.EInvoiceStatus = "Issued";
        order.EInvoiceNo = created.InvoiceNo;
        order.EInvoiceSeries = settings.InvoiceSeries;
        order.EInvoiceReservationCode = created.ReservationCode;
        order.EInvoiceCode = created.CodeOfTax;
        order.EInvoiceIssuedAt = DateTime.UtcNow;
        order.EInvoiceError = string.IsNullOrWhiteSpace(created.InvoiceNo)
            ? "Đã gửi Viettel — chờ số hóa đơn (có thể tra cứu lại)"
            : null;
        await db.SaveChangesAsync(ct);
    }

    async Task IssueEasyAsync(
        PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting settings, CancellationToken ct)
    {
        var xml = BuildEasyXml(order, lines, settings);
        // Easy: Pattern = ký hiệu HĐ (InvoiceSeries), Serial = mẫu số (TemplateCode)
        var created = await easy.ImportAndIssueAsync(
            settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
            xml, settings.InvoiceSeries, settings.TemplateCode, ct);

        if (!created.Ok && created.ErrorCode == "TIMEOUT" &&
            !string.IsNullOrWhiteSpace(order.EInvoiceTransactionUuid))
        {
            created = await easy.LookupByIkeyAsync(
                settings.ApiBaseUrl, settings.Username, settings.Password, settings.SupplierTaxCode,
                order.EInvoiceTransactionUuid, ct);
        }

        if (!created.Ok)
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = created.Error ?? created.ErrorCode ?? "Easy Invoice từ chối hóa đơn";
            await db.SaveChangesAsync(ct);
            return;
        }

        order.EInvoiceStatus = "Issued";
        order.EInvoiceNo = created.InvoiceNo;
        order.EInvoiceSeries = created.Pattern ?? settings.InvoiceSeries;
        order.EInvoiceReservationCode = created.LookupCode;
        order.EInvoiceCode = created.TaxAuthorityCode;
        order.EInvoiceIssuedAt = DateTime.UtcNow;
        order.EInvoiceError = string.IsNullOrWhiteSpace(created.InvoiceNo)
            ? created.Error ?? "Đã gửi Easy Invoice — chờ số hóa đơn (có thể tra cứu lại)"
            : null;
        await db.SaveChangesAsync(ct);
    }

    public async Task<object> SummaryAsync(Guid storeId, DateTime fromUtc, DateTime toUtc, CancellationToken ct = default)
    {
        var q = db.PosSaleOrders.AsNoTracking().Where(o =>
            o.StoreId == storeId && o.Deleted == null &&
            o.Status == Domain.Enums.PosSaleOrderStatus.Completed &&
            o.SaleDate >= fromUtc && o.SaleDate < toUtc);

        var issued = q.Where(o => o.EInvoiceStatus == "Issued");
        var skipped = q.Where(o => o.EInvoiceStatus == "Skipped");
        var failed = q.Where(o => o.EInvoiceStatus == "Failed");
        var pending = q.Where(o => o.EInvoiceStatus == "Pending");
        var none = q.Where(o => o.EInvoiceStatus == "None" || o.EInvoiceStatus == null);

        return new
        {
            from = fromUtc,
            to = toUtc,
            issuedCount = await issued.CountAsync(ct),
            issuedAmount = await issued.SumAsync(o => (decimal?)(o.Total + o.VatAmount), ct) ?? 0,
            skippedCount = await skipped.CountAsync(ct),
            skippedAmount = await skipped.SumAsync(o => (decimal?)(o.Total + o.VatAmount), ct) ?? 0,
            failedCount = await failed.CountAsync(ct),
            failedAmount = await failed.SumAsync(o => (decimal?)(o.Total + o.VatAmount), ct) ?? 0,
            pendingCount = await pending.CountAsync(ct),
            noneCount = await none.CountAsync(ct),
            totalCompleted = await q.CountAsync(ct),
        };
    }

    async Task<EInvoiceBuyerInput?> BuyerFromCustomerAsync(PosSaleOrder order, CancellationToken ct)
    {
        if (!order.CustomerId.HasValue) return null;
        var c = await db.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == order.CustomerId && x.StoreId == order.StoreId && x.Deleted == null, ct);
        if (c == null) return null;
        return new EInvoiceBuyerInput(c.Name, c.TaxCode, c.CompanyName, c.Address, c.Email, c.Phone);
    }

    static void ApplyBuyerSnapshot(PosSaleOrder order, EInvoiceBuyerInput? buyer)
    {
        if (buyer == null) return;
        if (!string.IsNullOrWhiteSpace(buyer.Name))
            order.EInvoiceBuyerName = buyer.Name.Trim();
        else if (!string.IsNullOrWhiteSpace(buyer.CompanyName))
            order.EInvoiceBuyerName = buyer.CompanyName.Trim();
        if (!string.IsNullOrWhiteSpace(buyer.TaxCode))
            order.EInvoiceBuyerTaxCode = buyer.TaxCode.Trim();
        if (!string.IsNullOrWhiteSpace(buyer.Address))
            order.EInvoiceBuyerAddress = buyer.Address.Trim();
        if (!string.IsNullOrWhiteSpace(buyer.Email))
            order.EInvoiceBuyerEmail = buyer.Email.Trim();
        if (!string.IsNullOrWhiteSpace(buyer.Phone))
            order.EInvoiceBuyerPhone = buyer.Phone.Trim();
    }

    object BuildViettelPayload(PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting s)
    {
        var calc = ComputeInvoice(order, lines, s);
        var items = calc.Lines.Select(l => (object)new Dictionary<string, object?>
        {
            ["lineNumber"] = l.No,
            ["itemName"] = Trim(l.Name, 500),
            ["unitName"] = l.Unit,
            ["unitPrice"] = l.UnitPrice,
            ["quantity"] = l.Qty,
            ["itemTotalAmountWithoutVat"] = l.Without,
            ["taxPercentage"] = calc.VatRate,
            ["taxAmount"] = l.Vat,
            ["itemTotalAmountWithVat"] = l.With,
            ["discount"] = 0,
            ["itemDiscount"] = l.LineDiscount,
            ["itemNote"] = l.Note,
        }).ToList();

        var buyerName = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName, "Khách lẻ");
        var buyerLegal = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName);
        var paymentName = MapPaymentMethod(order.PaymentMethod);
        var issuedMs = new DateTimeOffset(DateTime.SpecifyKind(
            order.SaleDate ?? DateTime.UtcNow, DateTimeKind.Utc)).ToUnixTimeMilliseconds();

        return new
        {
            generalInvoiceInfo = new Dictionary<string, object?>
            {
                ["transactionUuid"] = order.EInvoiceTransactionUuid,
                ["invoiceType"] = s.InvoiceType,
                ["templateCode"] = s.TemplateCode,
                ["invoiceSeries"] = s.InvoiceSeries,
                ["currencyCode"] = "VND",
                ["exchangeRate"] = 1,
                ["adjustmentType"] = "1",
                ["paymentStatus"] = true,
                ["cusGetInvoiceRight"] = true,
                ["invoiceIssuedDate"] = issuedMs,
            },
            buyerInfo = new Dictionary<string, object?>
            {
                ["buyerName"] = Trim(buyerName, 100),
                ["buyerLegalName"] = string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode)
                    ? null
                    : Trim(buyerLegal, 200),
                ["buyerTaxCode"] = string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode)
                    ? null
                    : order.EInvoiceBuyerTaxCode,
                ["buyerAddressLine"] = Trim(order.EInvoiceBuyerAddress, 400),
                ["buyerPhoneNumber"] = Trim(order.EInvoiceBuyerPhone, 20),
                ["buyerEmail"] = Trim(order.EInvoiceBuyerEmail, 50),
                ["buyerNotGetInvoice"] = false,
            },
            payments = new object[]
            {
                new Dictionary<string, object?>
                {
                    ["paymentMethodName"] = paymentName,
                    ["paymentMethod"] = paymentName,
                },
            },
            itemInfo = items,
            summarizeInfo = new Dictionary<string, object?>
            {
                ["sumOfTotalLineAmountWithoutVat"] = calc.SumWithout,
                ["totalAmountWithoutVat"] = calc.SumWithout,
                ["totalVatAmount"] = calc.SumVat,
                ["totalAmountWithVat"] = calc.SumWith,
                ["discountAmount"] = calc.ExtraDiscount,
            },
            taxBreakdowns = new object[]
            {
                new Dictionary<string, object?>
                {
                    ["taxPercentage"] = calc.VatRate,
                    ["taxableAmount"] = calc.SumWithout,
                    ["taxAmount"] = calc.SumVat,
                },
            },
        };
    }

    string BuildEasyXml(PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting s)
    {
        var calc = ComputeInvoice(order, lines, s);
        var buyer = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName, "Khách lẻ");
        var company = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName);
        var hasTax = !string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode);
        var cusCode = hasTax
            ? order.EInvoiceBuyerTaxCode!.Trim()
            : SanitizeCode(FirstNonEmpty(order.CustomerName, order.OrderNo, "KL"));
        var arising = DateTime.SpecifyKind(order.SaleDate ?? DateTime.UtcNow, DateTimeKind.Utc)
            .AddHours(7)
            .ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
        var vatRateStr = Num(calc.VatRate, 0);

        var products = new XElement("Products");
        foreach (var l in calc.Lines)
        {
            products.Add(new XElement("Product",
                new XElement("No", l.No),
                new XElement("Feature", "1"),
                new XElement("ProdName", l.Name),
                new XElement("ProdUnit", l.Unit),
                new XElement("ProdQuantity", Num(l.Qty, 4)),
                new XElement("ProdPrice", Num(l.UnitPrice, 4)),
                new XElement("DiscountAmount", Num(l.LineDiscount, 0)),
                new XElement("Total", Num(l.Without, 0)),
                new XElement("VATRate", vatRateStr),
                new XElement("VATAmount", Num(l.Vat, 0)),
                new XElement("Amount", Num(l.With, 0))));
        }

        var invoice = new XElement("Invoice",
            new XElement("Ikey", order.EInvoiceTransactionUuid),
            new XElement("CusCode", Trim(cusCode, 50) ?? "KL"),
            new XElement("Buyer", Trim(buyer, 100) ?? "Khách lẻ"),
            new XElement("CusName", Trim(hasTax ? company : buyer, 200) ?? "Khách lẻ"));
        var addr = Trim(order.EInvoiceBuyerAddress, 400);
        if (addr != null) invoice.Add(new XElement("CusAddress", addr));
        var phone = Trim(order.EInvoiceBuyerPhone, 20);
        if (phone != null) invoice.Add(new XElement("CusPhone", phone));
        if (hasTax) invoice.Add(new XElement("CusTaxCode", order.EInvoiceBuyerTaxCode!.Trim()));
        var email = Trim(order.EInvoiceBuyerEmail, 50);
        if (email != null) invoice.Add(new XElement("Email", email));
        invoice.Add(
            new XElement("PaymentMethod", MapEasyPayment(order.PaymentMethod)),
            new XElement("ArisingDate", arising),
            new XElement("CurrencyUnit", "VND"),
            products,
            new XElement("Total", Num(calc.SumWithout, 0)),
            new XElement("VATRate", vatRateStr),
            new XElement("VATAmount", Num(calc.SumVat, 0)),
            new XElement("Amount", Num(calc.SumWith, 0)),
            new XElement("DiscountAmount", Num(calc.ExtraDiscount, 0)),
            new XElement("AmountInWords", VndInWords(calc.SumWith)));

        AppendEasyTaxBuckets(invoice, calc);

        var xml = new XElement("Invoices", new XElement("Inv", invoice));
        return xml.ToString(SaveOptions.DisableFormatting);
    }

    static void AppendEasyTaxBuckets(XElement invoice, InvoiceCalc calc)
    {
        var without = Num(calc.SumWithout, 0);
        var vat = Num(calc.SumVat, 0);
        var with = Num(calc.SumWith, 0);
        switch (calc.VatRate)
        {
            case 10:
                invoice.Add(new XElement("GrossValue10", without), new XElement("VatAmount10", vat), new XElement("Amount10", with));
                break;
            case 8:
                invoice.Add(new XElement("GrossValue8", without), new XElement("VatAmount8", vat), new XElement("Amount8", with));
                break;
            case 5:
                invoice.Add(new XElement("GrossValue5", without), new XElement("VatAmount5", vat), new XElement("Amount5", with));
                break;
            case 0:
                invoice.Add(new XElement("GrossValue0", without), new XElement("VatAmount0", vat), new XElement("Amount0", with));
                break;
            case -1:
                invoice.Add(new XElement("GrossValue", without));
                break;
            default:
                invoice.Add(new XElement("GrossValueNDeclared", without), new XElement("VatAmountNDeclared", vat), new XElement("AmountNDeclared", with));
                break;
        }
    }

    InvoiceCalc ComputeInvoice(PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting s)
    {
        var taxMode = (s.TaxMode ?? "included").ToLowerInvariant();
        var taxPct = s.DefaultTaxPercent;
        if (order.VatAmount > 0)
        {
            taxMode = "added";
            var net = order.Total > 0 ? order.Total : lines.Sum(l => l.LineTotal);
            if (net > 0)
                taxPct = Math.Round(order.VatAmount / net * 100m, 0, MidpointRounding.AwayFromZero);
            if (taxPct is not (0 or 5 or 8 or 10))
                taxPct = 10;
        }
        else if (taxMode == "none" || taxPct <= 0)
        {
            taxMode = "none";
            taxPct = -2;
        }

        var extraDiscount = Math.Max(0, lines.Sum(l => l.LineTotal) - order.Total);
        var lineNets = Allocate(lines.Select(l => l.LineTotal).ToList(), extraDiscount);
        decimal sumWithout = 0, sumVat = 0, sumWith = 0;
        var calcLines = new List<LineCalc>(lines.Count);
        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            var net = lineNets[i];
            decimal without, vat, with;
            if (taxMode == "none")
            {
                without = net;
                vat = 0;
                with = net;
            }
            else if (taxMode == "added")
            {
                without = net;
                vat = RoundVnd(net * taxPct / 100m);
                with = without + vat;
            }
            else
            {
                with = net;
                without = taxPct > 0 ? RoundVnd(net / (1 + taxPct / 100m)) : net;
                vat = with - without;
            }

            sumWithout += without;
            sumVat += vat;
            sumWith += with;
            var qty = line.Qty <= 0 ? 1 : line.Qty;
            calcLines.Add(new LineCalc(
                i + 1,
                LineName(line),
                string.IsNullOrWhiteSpace(line.UnitName) ? "Lần" : line.UnitName!,
                qty,
                RoundMoney(without / qty, 4),
                without,
                vat,
                with,
                line.DiscountAmount,
                line.LineNote));
        }

        return new InvoiceCalc(calcLines, sumWithout, sumVat, sumWith, extraDiscount, taxMode == "none" ? -2 : taxPct);
    }

    static string LineName(PosSaleOrderLine line)
    {
        var name = line.ProductName;
        if (string.IsNullOrWhiteSpace(line.ToppingsJson)) return name;
        try
        {
            using var doc = JsonDocument.Parse(line.ToppingsJson);
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                var extras = new List<string>();
                foreach (var e in doc.RootElement.EnumerateArray())
                {
                    if (!e.TryGetProperty("name", out var n)) continue;
                    var label = n.GetString()?.Trim();
                    if (string.IsNullOrWhiteSpace(label)) continue;
                    var qty = 1m;
                    if ((e.TryGetProperty("qty", out var qEl) || e.TryGetProperty("Qty", out qEl))
                        && qEl.TryGetDecimal(out var q) && q > 1)
                        qty = q;
                    extras.Add(qty > 1 ? $"{label} x{qty:0.##}" : label);
                }
                if (extras.Count > 0)
                    name = $"{name} ({string.Join(", ", extras)})";
            }
        }
        catch { /* ignore topping parse */ }
        return name;
    }

    sealed record LineCalc(
        int No, string Name, string Unit, decimal Qty, decimal UnitPrice,
        decimal Without, decimal Vat, decimal With, decimal LineDiscount, string? Note);

    sealed record InvoiceCalc(
        List<LineCalc> Lines, decimal SumWithout, decimal SumVat, decimal SumWith,
        decimal ExtraDiscount, decimal VatRate);

    static List<decimal> Allocate(List<decimal> amounts, decimal extraDiscount)
    {
        var sum = amounts.Sum();
        if (extraDiscount <= 0 || sum <= 0) return amounts;
        var left = extraDiscount;
        var result = new List<decimal>(amounts.Count);
        for (var i = 0; i < amounts.Count; i++)
        {
            var share = i == amounts.Count - 1
                ? left
                : RoundVnd(extraDiscount * amounts[i] / sum);
            if (i < amounts.Count - 1) left -= share;
            result.Add(Math.Max(0, amounts[i] - share));
        }
        return result;
    }

    static string MapPaymentMethod(string? method)
    {
        var m = (method ?? "").ToLowerInvariant();
        if (m.Contains('+') || (m.Contains("tiền mặt") && (m.Contains("ck") || m.Contains("chuyển"))))
            return "TM/CK";
        if (m.Contains("chuyển") || m.Contains("vietqr") || m.Contains("ck") || m.Contains("ngân hàng") || m.Contains("bank"))
            return "CK";
        return "TM";
    }

    static string MapEasyPayment(string? method) => MapPaymentMethod(method) switch
    {
        "CK" => "Chuyển khoản",
        "TM/CK" => "Tiền mặt/Chuyển khoản",
        _ => "Tiền mặt",
    };

    static string NormalizeProvider(string? raw)
    {
        var p = (raw ?? "").Trim();
        if (p.Equals("Easy", StringComparison.OrdinalIgnoreCase) ||
            p.Equals("EasyInvoice", StringComparison.OrdinalIgnoreCase) ||
            p.Contains("easy", StringComparison.OrdinalIgnoreCase))
            return "Easy";
        if (p.Equals("Misa", StringComparison.OrdinalIgnoreCase) ||
            p.Contains("misa", StringComparison.OrdinalIgnoreCase))
            return "Misa";
        return "Viettel";
    }

    static string NormalizeBaseUrl(string provider, string? raw)
    {
        if (provider == "Easy")
            return EasyInvoiceClient.NormalizeBaseUrl(raw);
        return ViettelSInvoiceClient.NormalizeBaseUrl(raw);
    }

    static string Num(decimal v, int decimals)
    {
        var rounded = decimals <= 0
            ? RoundVnd(v)
            : RoundMoney(v, decimals);
        return rounded.ToString(decimals <= 0 ? "0" : "0.####", CultureInfo.InvariantCulture);
    }

    static string SanitizeCode(string raw)
    {
        var sb = new StringBuilder();
        foreach (var c in raw)
        {
            if (char.IsLetterOrDigit(c)) sb.Append(c);
            if (sb.Length >= 40) break;
        }
        return sb.Length > 0 ? sb.ToString() : "KL";
    }

    static string VndInWords(decimal amount)
    {
        var n = (long)RoundVnd(amount);
        if (n == 0) return "Không đồng";
        var negative = n < 0;
        if (negative) n = -n;
        var words = ReadVndGroups(n);
        if (string.IsNullOrWhiteSpace(words)) return "Không đồng";
        words = char.ToUpper(words[0], CultureInfo.GetCultureInfo("vi-VN")) + words[1..];
        return negative ? $"Âm {words} đồng" : $"{words} đồng";
    }

    static string ReadVndGroups(long n)
    {
        string[] scales = ["", " nghìn", " triệu", " tỷ", " nghìn tỷ"];
        var parts = new List<string>();
        var scale = 0;
        while (n > 0 && scale < scales.Length)
        {
            var group = (int)(n % 1000);
            n /= 1000;
            if (group > 0)
            {
                var g = ReadVndTriple(group, scale > 0 && n > 0);
                parts.Insert(0, g + scales[scale]);
            }
            scale++;
        }
        return string.Join(" ", parts).Trim();
    }

    static string ReadVndTriple(int n, bool padHundred)
    {
        string[] digits = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"];
        var hundred = n / 100;
        var ten = (n % 100) / 10;
        var unit = n % 10;
        var sb = new StringBuilder();
        if (hundred > 0)
        {
            sb.Append(digits[hundred]).Append(" trăm");
        }
        else if (padHundred && (ten > 0 || unit > 0))
        {
            sb.Append("không trăm");
        }

        if (ten > 1)
        {
            if (sb.Length > 0) sb.Append(' ');
            sb.Append(digits[ten]).Append(" mươi");
            if (unit == 1) sb.Append(" mốt");
            else if (unit == 4) sb.Append(" tư");
            else if (unit == 5) sb.Append(" lăm");
            else if (unit > 0) sb.Append(' ').Append(digits[unit]);
        }
        else if (ten == 1)
        {
            if (sb.Length > 0) sb.Append(' ');
            sb.Append("mười");
            if (unit == 5) sb.Append(" lăm");
            else if (unit > 0) sb.Append(' ').Append(digits[unit]);
        }
        else if (unit > 0)
        {
            if (sb.Length > 0) sb.Append(" linh ");
            else if (padHundred) sb.Append("linh ");
            if (unit == 4 && sb.Length > 0) sb.Append("bốn");
            else sb.Append(digits[unit]);
        }
        return sb.ToString().Trim();
    }

    static decimal RoundVnd(decimal v) => Math.Round(v, 0, MidpointRounding.AwayFromZero);
    static decimal RoundMoney(decimal v, int d) => Math.Round(v, d, MidpointRounding.AwayFromZero);

    static string FirstNonEmpty(params string?[] values)
    {
        foreach (var v in values)
        {
            if (!string.IsNullOrWhiteSpace(v)) return v.Trim();
        }
        return "";
    }

    static string? Trim(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        return s.Length <= max ? s : s[..max];
    }
}
