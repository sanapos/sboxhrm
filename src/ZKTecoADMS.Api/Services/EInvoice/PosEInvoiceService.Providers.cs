using System.Globalization;
using System.Xml.Linq;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.EInvoice;

/// <summary>MISA meInvoice + VNPT Invoice: phát hành, thay thế, đồng bộ.</summary>
public partial class PosEInvoiceService
{
    internal sealed record MisaReplaceInfo(string OrgNo, string OrgSeries, DateTime OrgIssuedUtc, string Reason);

    internal static string ProviderLabel(string provider) => provider switch
    {
        "Easy" => "Easy Invoice",
        "Misa" => "MISA meInvoice",
        "Vnpt" => "VNPT Invoice",
        _ => "Viettel SInvoice",
    };

    /// <summary>Thiếu cấu hình bắt buộc theo từng hãng → thông báo; null = đủ.</summary>
    static string? MissingConfig(PosEInvoiceSetting s, string provider)
    {
        bool Empty(string? v) => string.IsNullOrWhiteSpace(v);
        var baseCreds = Empty(s.Username) || Empty(s.Password) || Empty(s.SupplierTaxCode);
        return provider switch
        {
            "Easy" when baseCreds || Empty(s.TemplateCode) =>
                "Thiếu cấu hình Easy Invoice (tài khoản, MST, mẫu số Pattern)",
            "Misa" when baseCreds || Empty(s.AppId) || Empty(ResolveMisaSeries(s)) =>
                "Thiếu cấu hình MISA meInvoice (AppID, tài khoản, MST, ký hiệu hóa đơn vd. 1C25TAA)",
            "Vnpt" when baseCreds || Empty(s.ApiBaseUrl) || Empty(s.ServiceAccount) || Empty(s.ServicePassword) ||
                        Empty(s.TemplateCode) || Empty(s.InvoiceSeries) =>
                "Thiếu cấu hình VNPT (địa chỉ web service, Account/ACpass, tài khoản phát hành, MST, mẫu số, ký hiệu)",
            "Viettel" when baseCreds || Empty(s.TemplateCode) || Empty(s.InvoiceSeries) =>
                "Thiếu cấu hình Viettel (tài khoản, MST, mẫu, ký hiệu hóa đơn)",
            _ => null,
        };
    }

    // ───────────────────────────── MISA ─────────────────────────────

    /// <summary>Ký hiệu đầy đủ MISA «1C25TAA». Cho phép nhập tách mẫu «1» + ký hiệu «C25TAA».</summary>
    public static string ResolveMisaSeries(PosEInvoiceSetting s)
    {
        var series = (s.InvoiceSeries ?? "").Trim().Replace(" ", "").ToUpperInvariant();
        var template = (s.TemplateCode ?? "").Trim().Replace(" ", "");
        if (series.Length > 0 && char.IsLetter(series[0]) && template.Length is > 0 and <= 2 && template.All(char.IsDigit))
            return template + series;
        return series;
    }

    /// <summary>Ký tự thứ 2 của ký hiệu: C = có mã CQT, K = không mã.</summary>
    static bool MisaWithCode(PosEInvoiceSetting s)
    {
        var series = ResolveMisaSeries(s);
        return series.Length < 2 || char.ToUpperInvariant(series[1]) == 'C';
    }

    async Task<string> MisaTokenAsync(Guid storeId, PosEInvoiceSetting s, CancellationToken ct) =>
        await misa.GetTokenAsync(storeId, s.ApiBaseUrl, s.AppId, s.SupplierTaxCode, s.Username, s.Password, ct);

    async Task<(bool Ok, string Message)> TestMisaAsync(PosEInvoiceSetting s, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(s.AppId))
            return (false, "MISA cần AppID (MISA cấp khi đăng ký tích hợp API)");
        if (string.IsNullOrWhiteSpace(s.SupplierTaxCode))
            return (false, "MISA cần MST người bán");
        misa.InvalidateToken(s.StoreId);
        var login = await misa.LoginAsync(s.ApiBaseUrl, s.AppId, s.SupplierTaxCode, s.Username, s.Password, ct);
        if (!login.Ok)
            return (false, login.Error ?? "Đăng nhập MISA meInvoice thất bại");
        var tpl = await misa.GetTemplatesAsync(s.ApiBaseUrl, login.Token!, s.SupplierTaxCode, MisaWithCode(s), ct);
        return tpl.Ok
            ? (true, $"Đăng nhập MISA meInvoice thành công — {tpl.Count} ký hiệu hóa đơn khả dụng năm nay")
            : (true, "Đăng nhập MISA meInvoice thành công (chưa đọc được danh sách ký hiệu: " + tpl.Error + ")");
    }

    async Task IssueMisaAsync(
        PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting settings,
        MisaReplaceInfo? replace, CancellationToken ct)
    {
        var token = await MisaTokenAsync(order.StoreId, settings, ct);
        var data = BuildMisaInvoiceData(order, lines, settings, replace);
        var signType = settings.SignType == 5 ? 5 : 2;
        var res = await misa.PublishAsync(settings.ApiBaseUrl, token, settings.SupplierTaxCode, signType, data, ct);

        if (!res.Ok && res.ErrorCode is "TIMEOUT" or "InvoiceDuplicated")
        {
            // Có thể đã phát hành — tra lại theo RefID.
            try
            {
                await SyncMisaAsync(order, settings, ct);
                if (!string.IsNullOrWhiteSpace(order.EInvoiceReservationCode))
                {
                    await db.SaveChangesAsync(ct);
                    return;
                }
            }
            catch (InvalidOperationException) { /* chưa có trên MISA → báo lỗi gốc */ }
        }

        if (!res.Ok)
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = Trim(res.Error ?? res.ErrorCode ?? "MISA từ chối hóa đơn", 1000);
            await db.SaveChangesAsync(ct);
            return;
        }

        order.EInvoiceStatus = "Issued";
        order.EInvoiceNo = res.InvoiceNo;
        order.EInvoiceSeries = FirstNonEmpty(res.InvoiceSeries, ResolveMisaSeries(settings));
        order.EInvoiceReservationCode = res.TransactionId;
        order.EInvoiceCode = res.InvoiceCode;
        order.EInvoiceIssuedAt = DateTime.UtcNow;
        if (string.IsNullOrWhiteSpace(order.EInvoiceKind))
            order.EInvoiceKind = "Original";
        order.EInvoiceError = string.IsNullOrWhiteSpace(res.InvoiceNo)
            ? "Đã gửi MISA — chờ số hóa đơn (dùng Đồng bộ)"
            : null;
        await db.SaveChangesAsync(ct);
        await TrySendBuyerEmailAsync(order, settings, ct);
    }

    object BuildMisaInvoiceData(
        PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting s, MisaReplaceInfo? replace)
    {
        var calc = ComputeInvoice(order, lines, s);
        var rateName = VatRateName(calc.VatRate);
        var hasTax = !string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode);
        var personName = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName);
        var companyName = FirstNonEmpty(order.EInvoiceBuyerCompanyName);
        var invDate = DateTime.SpecifyKind(order.SaleDate ?? DateTime.UtcNow, DateTimeKind.Utc).AddHours(7);
        // Hóa đơn thay thế phải có ngày ≥ ngày HĐ gốc → dùng hôm nay.
        if (replace != null) invDate = DateTime.UtcNow.AddHours(7);

        var details = calc.Lines.Select(l => new Dictionary<string, object?>
        {
            ["ItemType"] = 1,
            ["LineNumber"] = l.No,
            ["SortOrder"] = l.No,
            ["ItemName"] = Trim(l.Name, 500),
            ["UnitName"] = ResolveInvoiceUnit(l.Unit),
            ["Quantity"] = l.Qty,
            ["UnitPrice"] = l.UnitPrice,
            ["DiscountRate"] = 0m,
            ["DiscountAmountOC"] = 0m,
            ["DiscountAmount"] = 0m,
            ["AmountOC"] = l.Without,
            ["Amount"] = l.Without,
            ["AmountWithoutVATOC"] = l.Without,
            ["AmountWithoutVAT"] = l.Without,
            ["VATRateName"] = rateName,
            ["VATAmountOC"] = l.Vat,
            ["VATAmount"] = l.Vat,
        }).ToList();

        var email = Trim(order.EInvoiceBuyerEmail, 200);
        var data = new Dictionary<string, object?>
        {
            ["RefID"] = order.EInvoiceTransactionUuid,
            ["InvSeries"] = ResolveMisaSeries(s),
            ["InvDate"] = invDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["IsInvoiceCalculatingMachine"] = s.SignType == 5,
            ["CurrencyCode"] = "VND",
            ["ExchangeRate"] = 1.0m,
            ["PaymentMethodName"] = MapPaymentMethod(order.PaymentMethod).Name,
            ["BuyerLegalName"] = hasTax ? Trim(FirstNonEmpty(companyName, personName), 400) : null,
            ["BuyerTaxCode"] = hasTax ? order.EInvoiceBuyerTaxCode!.Trim() : null,
            ["BuyerAddress"] = hasTax ? Trim(order.EInvoiceBuyerAddress, 400) : null,
            ["BuyerFullName"] = Trim(FirstNonEmpty(personName, hasTax ? "" : ConsumerBuyerLabel), 100),
            ["BuyerPhoneNumber"] = Trim(order.EInvoiceBuyerPhone, 20),
            ["BuyerEmail"] = email,
            ["IsSendEmail"] = email != null,
            ["ReceiverEmail"] = email,
            ["ReceiverName"] = email != null ? Trim(FirstNonEmpty(personName, companyName, "Quý khách"), 100) : null,
            ["TotalSaleAmountOC"] = calc.SumWithout,
            ["TotalSaleAmount"] = calc.SumWithout,
            ["TotalDiscountAmountOC"] = 0m,
            ["TotalDiscountAmount"] = 0m,
            ["TotalAmountWithoutVATOC"] = calc.SumWithout,
            ["TotalAmountWithoutVAT"] = calc.SumWithout,
            ["TotalVATAmountOC"] = calc.SumVat,
            ["TotalVATAmount"] = calc.SumVat,
            ["TotalAmountOC"] = calc.SumWith,
            ["TotalAmount"] = calc.SumWith,
            ["TotalAmountInWords"] = VndInWords(calc.SumWith) + ".",
            ["OriginalInvoiceDetail"] = details,
            ["TaxRateInfo"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["VATRateName"] = rateName,
                    ["AmountWithoutVATOC"] = calc.SumWithout,
                    ["VATAmountOC"] = calc.SumVat,
                },
            },
            ["OptionUserDefined"] = new Dictionary<string, string>
            {
                ["MainCurrency"] = "VND",
                ["AmountDecimalDigits"] = "0",
                ["AmountOCDecimalDigits"] = "0",
                ["UnitPriceOCDecimalDigits"] = "4",
                ["UnitPriceDecimalDigits"] = "4",
                ["QuantityDecimalDigits"] = "4",
            },
        };

        if (replace != null)
        {
            // Ký hiệu HĐ gốc «1C25TAA» → mẫu «1» + ký hiệu «C25TAA».
            var org = (replace.OrgSeries ?? "").Trim();
            var digits = new string(org.TakeWhile(char.IsDigit).ToArray());
            data["ReferenceType"] = 1;
            data["OrgInvoiceType"] = 1;
            data["OrgInvTemplateNo"] = digits.Length > 0 ? digits : "1";
            data["OrgInvSeries"] = digits.Length > 0 ? org[digits.Length..] : org;
            data["OrgInvNo"] = replace.OrgNo;
            data["OrgInvDate"] = replace.OrgIssuedUtc.AddHours(7).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            data["InvoiceNote"] = Trim(replace.Reason, 255);
        }
        return data;
    }

    async Task SyncMisaAsync(PosSaleOrder order, PosEInvoiceSetting settings, CancellationToken ct)
    {
        var token = await MisaTokenAsync(order.StoreId, settings, ct);
        var byRef = string.IsNullOrWhiteSpace(order.EInvoiceReservationCode);
        var key = byRef ? order.EInvoiceTransactionUuid! : order.EInvoiceReservationCode!;
        var list = await misa.GetStatusAsync(
            settings.ApiBaseUrl, token, settings.SupplierTaxCode, [key], byRefId: byRef,
            invoiceWithCode: MisaWithCode(settings), cashRegister: settings.SignType == 5, ct);
        var st = list.FirstOrDefault();
        if (st == null)
            throw new InvalidOperationException("Không tìm thấy hóa đơn trên MISA meInvoice");

        if (!string.IsNullOrWhiteSpace(st.TransactionId))
            order.EInvoiceReservationCode = st.TransactionId;
        if (!string.IsNullOrWhiteSpace(st.InvoiceCode))
            order.EInvoiceCode = st.InvoiceCode;
        if (st.IsSentEmail && order.EInvoiceEmailSentAt == null)
            order.EInvoiceEmailSentAt = DateTime.UtcNow;

        if (st.IsDeleted)
        {
            order.EInvoiceStatus = "Cancelled";
            order.EInvoiceCancelledAt ??= DateTime.UtcNow;
            order.EInvoiceCancelReason ??= Trim(st.DeletedReason, 400);
            order.EInvoiceError = null;
            return;
        }

        order.EInvoiceStatus = "Issued";
        order.EInvoiceIssuedAt ??= DateTime.UtcNow;
        order.EInvoiceError = MisaTaxStatusNote(st.SendTaxStatus, MisaWithCode(settings));
        if (string.IsNullOrWhiteSpace(order.EInvoiceNo))
            order.EInvoiceError = FirstNonEmpty(order.EInvoiceError,
                "Đã phát hành trên MISA — API trạng thái không trả số HĐ, xem trên trang quản lý MISA");
    }

    static string? MisaTaxStatusNote(int sendTaxStatus, bool withCode) => withCode
        ? sendTaxStatus switch
        {
            0 => "MISA: chờ CQT cấp mã",
            1 => "MISA: gửi CQT lỗi — kiểm tra trên trang quản lý MISA",
            3 => "MISA: CQT từ chối cấp mã",
            _ => null,
        }
        : sendTaxStatus switch
        {
            3 => "MISA: CQT không tiếp nhận hóa đơn",
            4 => "MISA: gửi CQT lỗi",
            _ => null,
        };

    // ───────────────────────────── VNPT ─────────────────────────────

    async Task IssueVnptAsync(
        PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting settings,
        string? originalFkey, CancellationToken ct)
    {
        var xml = BuildVnptXml(order, lines, settings);
        var pattern = settings.TemplateCode.Trim();
        var serial = settings.InvoiceSeries.Trim();
        var res = string.IsNullOrWhiteSpace(originalFkey)
            ? await vnpt.ImportAndPublishAsync(
                settings.ApiBaseUrl, settings.ServiceAccount, settings.ServicePassword,
                settings.Username, settings.Password, xml, pattern, serial, ct)
            : await vnpt.ReplaceAsync(
                settings.ApiBaseUrl, settings.ServiceAccount, settings.ServicePassword,
                settings.Username, settings.Password, xml, originalFkey, pattern, serial, ct);

        if (!res.Ok && (res.ErrorCode ?? "").StartsWith("ERR:13", StringComparison.OrdinalIgnoreCase))
        {
            // Fkey đã có trên VNPT (lần trước mất mạng) → lấy lại số.
            try
            {
                await SyncVnptAsync(order, settings, ct);
                await db.SaveChangesAsync(ct);
                return;
            }
            catch (InvalidOperationException) { /* rơi xuống báo lỗi gốc */ }
        }

        if (!res.Ok)
        {
            order.EInvoiceStatus = "Failed";
            order.EInvoiceError = Trim(res.Error ?? res.ErrorCode ?? "VNPT từ chối hóa đơn", 1000);
            await db.SaveChangesAsync(ct);
            return;
        }

        order.EInvoiceStatus = "Issued";
        order.EInvoiceNo = res.InvoiceNo;
        order.EInvoiceSeries = FirstNonEmpty(res.Serial, serial);
        order.EInvoiceReservationCode = order.EInvoiceTransactionUuid;
        order.EInvoiceIssuedAt = DateTime.UtcNow;
        if (string.IsNullOrWhiteSpace(order.EInvoiceKind))
            order.EInvoiceKind = "Original";
        order.EInvoiceError = string.IsNullOrWhiteSpace(res.InvoiceNo)
            ? "Đã gửi VNPT — chưa đọc được số HĐ (dùng Đồng bộ)"
            : null;
        // VNPT tự gửi mail theo DCTDTu trên hóa đơn.
        if (!string.IsNullOrWhiteSpace(order.EInvoiceBuyerEmail))
        {
            order.EInvoiceEmailSentAt = DateTime.UtcNow;
            order.EInvoiceEmailTo = Trim(order.EInvoiceBuyerEmail, 200);
        }
        await db.SaveChangesAsync(ct);
    }

    /// <summary>XML dữ liệu hóa đơn VNPT theo TT78 (DSHDon/HDon/DLHDon).</summary>
    string BuildVnptXml(PosSaleOrder order, List<PosSaleOrderLine> lines, PosEInvoiceSetting s)
    {
        var calc = ComputeInvoice(order, lines, s);
        var rate = VatRateName(calc.VatRate);
        var hasTax = !string.IsNullOrWhiteSpace(order.EInvoiceBuyerTaxCode);
        var personName = FirstNonEmpty(order.EInvoiceBuyerName, order.CustomerName);
        var companyName = FirstNonEmpty(order.EInvoiceBuyerCompanyName);
        var saleLocal = DateTime.SpecifyKind(order.SaleDate ?? DateTime.UtcNow, DateTimeKind.Utc).AddHours(7);

        XElement? Opt(string name, string? value) =>
            string.IsNullOrWhiteSpace(value) ? null : new XElement(name, value.Trim());

        var buyer = new XElement("NMua",
            new XElement("Ten", Trim(hasTax ? FirstNonEmpty(companyName, personName) : FirstNonEmpty(personName, ConsumerBuyerLabel), 400)),
            Opt("MST", hasTax ? order.EInvoiceBuyerTaxCode : null),
            Opt("DChi", hasTax ? Trim(order.EInvoiceBuyerAddress, 400) : null),
            Opt("MKHang", order.CustomerId?.ToString("N")[..12]),
            Opt("SDThoai", Trim(order.EInvoiceBuyerPhone, 20)),
            Opt("DCTDTu", Trim(order.EInvoiceBuyerEmail, 200)),
            Opt("HVTNMHang", Trim(personName, 100)));

        var items = new XElement("DSHHDVu");
        foreach (var l in calc.Lines)
        {
            items.Add(new XElement("HHDVu",
                new XElement("TChat", 1),
                new XElement("STT", l.No),
                new XElement("THHDVu", Trim(l.Name, 500)),
                Opt("DVTinh", ResolveInvoiceUnit(l.Unit)),
                new XElement("SLuong", Num(l.Qty, 4)),
                new XElement("DGia", Num(l.UnitPrice, 4)),
                new XElement("TLCKhau", 0),
                new XElement("STCKhau", 0),
                new XElement("ThTien", Num(l.Without, 0)),
                new XElement("TSuat", rate),
                new XElement("TThue", Num(l.Vat, 0)),
                new XElement("TSThue", Num(l.With, 0))));
        }

        var totals = new XElement("TToan",
            new XElement("THTTLTSuat",
                new XElement("LTSuat",
                    new XElement("TSuat", rate),
                    new XElement("ThTien", Num(calc.SumWithout, 0)),
                    new XElement("TThue", Num(calc.SumVat, 0)))),
            new XElement("TgTCThue", Num(calc.SumWithout, 0)),
            new XElement("TgTThue", Num(calc.SumVat, 0)),
            new XElement("TTCKTMai", 0),
            new XElement("TgTTTBSo", Num(calc.SumWith, 0)),
            new XElement("TgTTTBChu", VndInWords(calc.SumWith)));

        var doc = new XElement("DSHDon",
            new XElement("HDon",
                new XElement("key", order.EInvoiceTransactionUuid),
                new XElement("DLHDon",
                    new XElement("TTChung",
                        new XElement("NLap", saleLocal.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)),
                        new XElement("DVTTe", "VND"),
                        new XElement("TGia", 1),
                        new XElement("HTTToan", MapEasyPayment(order.PaymentMethod))),
                    new XElement("NDHDon", buyer, items, totals))));
        return doc.ToString(SaveOptions.DisableFormatting);
    }

    async Task SyncVnptAsync(PosSaleOrder order, PosEInvoiceSetting settings, CancellationToken ct)
    {
        var fkey = order.EInvoiceTransactionUuid!;
        var sale = DateTime.SpecifyKind(order.SaleDate ?? DateTime.UtcNow, DateTimeKind.Utc).AddHours(7).Date;
        var from = sale.AddDays(-3);
        var to = DateTime.UtcNow.AddHours(7).Date.AddDays(1);
        if ((to - from).TotalDays > 90) to = from.AddDays(90);
        var found = await vnpt.ListByFkeyAsync(settings.ApiBaseUrl, settings.Username, settings.Password, fkey, from, to, ct);
        var item = found.Items.FirstOrDefault(i => string.Equals(i.Fkey, fkey, StringComparison.OrdinalIgnoreCase))
                   ?? (found.Items.Count == 1 ? found.Items[0] : null);
        if (item == null)
        {
            // Dự phòng: xem được hóa đơn theo fkey = đã tồn tại trên VNPT.
            var view = await vnpt.ViewHtmlAsync(settings.ApiBaseUrl, settings.Username, settings.Password, fkey, ct);
            if (!view.Ok)
                throw new InvalidOperationException(found.Error ?? view.Error ?? "Không tìm thấy hóa đơn trên VNPT");
            order.EInvoiceStatus = "Issued";
            order.EInvoiceReservationCode ??= fkey;
            order.EInvoiceError = string.IsNullOrWhiteSpace(order.EInvoiceNo)
                ? "Hóa đơn có trên VNPT — chưa đọc được số, xem trên trang quản lý VNPT"
                : null;
            return;
        }

        if (!string.IsNullOrWhiteSpace(item.InvoiceNo)) order.EInvoiceNo = item.InvoiceNo;
        if (!string.IsNullOrWhiteSpace(item.Serial)) order.EInvoiceSeries = item.Serial;
        order.EInvoiceReservationCode ??= fkey;
        order.EInvoiceIssuedAt ??= item.PublishDate?.AddHours(-7) ?? DateTime.UtcNow;
        order.EInvoiceStatus = string.IsNullOrWhiteSpace(order.EInvoiceNo) ? "Pending" : "Issued";
        order.EInvoiceError = null;
    }

    /// <summary>Tên thuế suất theo chuẩn TT78: 10% / 8% / 5% / 0% / KCT / KKKNT.</summary>
    static string VatRateName(decimal rate) => rate switch
    {
        -1 => "KCT",
        -2 or < 0 => "KKKNT",
        _ => $"{rate.ToString("0.##", CultureInfo.InvariantCulture)}%",
    };
}
