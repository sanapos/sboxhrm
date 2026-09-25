using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public static class PosQuoteDocumentHtml
{
    public static string TitleOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => "BÁO GIÁ",
        PosQuoteDocumentKind.Contract => "HỢP ĐỒNG THI CÔNG",
        PosQuoteDocumentKind.Handover => "BIÊN BẢN BÀN GIAO",
        PosQuoteDocumentKind.Acceptance => "BIÊN BẢN NGHIỆM THU HOÀN THÀNH",
        PosQuoteDocumentKind.PaymentRequest => "ĐỀ NGHỊ THANH TOÁN",
        PosQuoteDocumentKind.StockIssue => "PHIẾU XUẤT KHO",
        _ => "CHỨNG TỪ",
    };

    public static string PrefixOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => "BG",
        PosQuoteDocumentKind.Contract => "HD",
        PosQuoteDocumentKind.Handover => "BB",
        PosQuoteDocumentKind.Acceptance => "NT",
        PosQuoteDocumentKind.PaymentRequest => "DN",
        PosQuoteDocumentKind.StockIssue => "PX",
        _ => "CT",
    };

    public static PosPrintDocumentType PrintDocumentTypeOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => PosPrintDocumentType.Quote,
        PosQuoteDocumentKind.Contract => PosPrintDocumentType.Contract,
        PosQuoteDocumentKind.Handover => PosPrintDocumentType.Handover,
        PosQuoteDocumentKind.Acceptance => PosPrintDocumentType.Acceptance,
        PosQuoteDocumentKind.PaymentRequest => PosPrintDocumentType.PaymentRequest,
        _ => PosPrintDocumentType.StockIssue,
    };

    public static async Task<string> BuildAsync(
        ZKTecoDbContext db,
        PosQuote quote,
        PosQuoteDocumentKind kind,
        string docNo,
        string? extraNote,
        bool includeImages = false,
        string? contentRootPath = null,
        bool includeStamp = true)
    {
        var docType = PrintDocumentTypeOf(kind);
        var templateHtml = await ResolveTemplateHtmlAsync(db, quote, docType);
        var (data, lines) = await BuildFieldsAsync(db, quote, kind, docNo, extraNote, includeImages, contentRootPath);
        if (!includeStamp) data["Con_Dau"] = "<div style=\"height:48px\"></div>";
        return PosPrintTemplateHtmlRenderer.Render(templateHtml, data, lines);
    }

    /// <summary>Dữ liệu điền mẫu (trường chung + từng dòng hàng) — dùng cho mẫu HTML và mẫu Word.</summary>
    public static async Task<(Dictionary<string, string> Data, List<Dictionary<string, string>> Lines)> BuildFieldsAsync(
        ZKTecoDbContext db,
        PosQuote quote,
        PosQuoteDocumentKind kind,
        string docNo,
        string? extraNote,
        bool includeImages = false,
        string? contentRootPath = null)
    {
        var store = quote.Store ?? await db.Stores.AsNoTracking()
            .FirstOrDefaultAsync(s => s.Id == quote.StoreId);
        // Chi tiết chi nhánh & MST bên B từ Branch (mã thuế / địa chỉ) — nếu store
        // có `HeadquarterBranchId`. `PosQuote` không lưu BranchId nên tìm trụ sở.
        Branch? branch = null;
        if (store != null)
        {
            branch = await db.Branches.AsNoTracking()
                .Where(b => b.StoreId == store.Id && (b.IsHeadquarter || b.TaxCode != null))
                .OrderByDescending(b => b.IsHeadquarter)
                .FirstOrDefaultAsync();
        }
        // Khách hàng: pull TaxCode + CompanyName từ PosCustomer nếu có.
        PosCustomer? customer = null;
        if (quote.CustomerId is Guid cid)
        {
            customer = await db.PosCustomers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == cid);
        }
        var profile = await db.PosStoreCommercialProfiles.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == quote.StoreId && x.Deleted == null);
        var data = BuildData(quote, kind, docNo, extraNote, store, branch, customer, profile);
        var lines = await BuildLinesAsync(db, quote, includeImages, contentRootPath);
        return (data, lines);
    }

    /// <summary>Fallback đồng bộ khi chưa có DbContext (giữ chữ ký cũ).</summary>
    public static string Build(PosQuote quote, PosQuoteDocumentKind kind, string docNo, string? extraNote)
    {
        var data = BuildData(quote, kind, docNo, extraNote, quote.Store, null, null, null);
        var lines = activeLinesSync(quote);
        var html = DefaultA4For(kind);
        return PosPrintTemplateHtmlRenderer.Render(html, data, lines);
    }

    static string ProductLabel(string name, string? note) => name;

    static string StampHtml(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        var s = raw.Trim();
        var comma = s.IndexOf(',');
        if (s.StartsWith("data:", StringComparison.OrdinalIgnoreCase) && comma > 0)
            s = s[(comma + 1)..].Trim();
        s = s.Replace(" ", "").Replace("\r", "").Replace("\n", "");
        if (s.Length < 32) return "<div style=\"height:64px\"></div>";
        return "<img src=\"data:image/png;base64," + s +
               "\" alt=\"\" width=\"112\" height=\"112\" style=\"width:112px;height:112px;object-fit:contain;display:inline-block;vertical-align:middle\"/>";
    }

    static string DimCell(decimal? stored, string? note, string label)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        if (stored is > 0)
            return stored.Value.ToString("0.####", vn);
        if (string.IsNullOrWhiteSpace(note)) return "";
        var m = Regex.Match(note, label + @"\s+(\d+(?:[.,]\d+)?)", RegexOptions.IgnoreCase);
        if (!m.Success) return "";
        var raw = m.Groups[1].Value.Replace(',', '.');
        return decimal.TryParse(raw, NumberStyles.Number, CultureInfo.InvariantCulture, out var v) && v > 0
            ? v.ToString("0.####", vn)
            : "";
    }

    static List<Dictionary<string, string>> activeLinesSync(PosQuote quote)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        var i = 1;
        return quote.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder)
            .Select(l => new Dictionary<string, string>
            {
                ["STT"] = (i++).ToString(),
                ["Ma_Hang"] = l.ProductCode ?? "",
                ["Ten_Hang_Hoa"] = ProductLabel(l.ProductName, l.LineNote),
                ["Don_Vi_Tinh"] = l.UnitName ?? "",
                ["So_Luong"] = l.Qty.ToString("0.##", vn),
                ["Don_Gia"] = l.UnitPrice.ToString("#,##0", vn),
                ["Thanh_Tien"] = l.LineTotal.ToString("#,##0", vn),
                ["Chiet_Khau"] = l.DiscountAmount.ToString("#,##0", vn),
                ["Ghi_Chu"] = l.LineNote ?? "",
                ["Chieu_Dai"] = DimCell(l.Length, l.LineNote, "Dài"),
                ["Chieu_Rong"] = DimCell(l.Width, l.LineNote, "Rộng"),
                ["Chieu_Cao"] = DimCell(l.Height, l.LineNote, "Cao"),
                ["Bao_Hanh"] = l.WarrantyMonths is > 0 ? l.WarrantyMonths + " tháng" : "",
                ["Hinh_Anh"] = "",
            }).ToList();
    }

    static async Task<string> ResolveTemplateHtmlAsync(
        ZKTecoDbContext db, PosQuote quote, PosPrintDocumentType docType)
    {
        if (quote.PrintTemplateId is Guid tid)
        {
            var picked = await db.PosPrintTemplates.AsNoTracking()
                .Where(t => t.Id == tid && t.StoreId == quote.StoreId && t.Deleted == null
                            && t.DocumentType == docType)
                .Select(t => t.HtmlContent)
                .FirstOrDefaultAsync();
            if (IsUsableHtml(picked)) return picked!;
        }
        var def = await db.PosPrintTemplates.AsNoTracking()
            .Where(t => t.StoreId == quote.StoreId && t.DocumentType == docType
                        && t.Deleted == null && t.IsActive)
            .OrderByDescending(t => t.IsDefault)
            .ThenBy(t => t.SortOrder)
            .Select(t => t.HtmlContent)
            .FirstOrDefaultAsync();
        if (IsUsableHtml(def)) return def!;
        return DefaultA4For(kindFromDocType(docType));
    }

    static PosQuoteDocumentKind kindFromDocType(PosPrintDocumentType t) => t switch
    {
        PosPrintDocumentType.Contract => PosQuoteDocumentKind.Contract,
        PosPrintDocumentType.Handover => PosQuoteDocumentKind.Handover,
        PosPrintDocumentType.Acceptance => PosQuoteDocumentKind.Acceptance,
        PosPrintDocumentType.PaymentRequest => PosQuoteDocumentKind.PaymentRequest,
        PosPrintDocumentType.StockIssue => PosQuoteDocumentKind.StockIssue,
        _ => PosQuoteDocumentKind.Quote,
    };

    static bool IsUsableHtml(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return false;
        var t = html.TrimStart();
        // Reject JSON V2 marker (`<!--POS_TEMPLATE_V2-->…{ }`) — cũng bắt đầu bằng `<`.
        if (t.StartsWith("<!--POS_TEMPLATE_V2", StringComparison.OrdinalIgnoreCase)) return false;
        if (!t.StartsWith("<", StringComparison.Ordinal) || t.StartsWith("{", StringComparison.Ordinal))
            return false;
        return Regex.IsMatch(t, @"<!--POS_A4_V(?:[8-9]|\d{2,})", RegexOptions.IgnoreCase);
    }

    static string FirstText(params string?[] values)
    {
        foreach (var v in values)
        {
            if (!string.IsNullOrWhiteSpace(v)) return v.Trim();
        }
        return "";
    }

    static Dictionary<string, string> BuildData(
        PosQuote quote,
        PosQuoteDocumentKind kind,
        string docNo,
        string? extraNote,
        Store? store,
        Branch? branch,
        PosCustomer? customer,
        PosStoreCommercialProfile? profile)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        var now = DateTime.Now;
        var shopName = FirstText(store?.Name);
        var companyName = FirstText(profile?.CompanyName, shopName);
        var storeAddress = FirstText(branch?.Address, store?.Address);
        var companyAddress = FirstText(profile?.Address, storeAddress);
        var storePhone = FirstText(branch?.Phone, store?.Phone);
        var companyPhone = FirstText(profile?.Phone, storePhone);
        var storeTaxCode = FirstText(profile?.TaxCode, branch?.TaxCode);
        var storeEmail = FirstText(profile?.Email, branch?.Email);
        var storeBankNo = FirstText(profile?.BankAccountNumber);
        var storeBankName = FirstText(profile?.BankName);
        var storeBankHolder = FirstText(profile?.BankAccountHolder, companyName);
        var storeRep = FirstText(profile?.LegalRepresentative);
        var storeTitle = FirstText(profile?.LegalTitle, "Giám đốc");
        var customerCompany = FirstText(customer?.CompanyName, quote.CustomerName);
        var customerTaxCode = customer?.TaxCode ?? "";
        var lines = quote.Lines.Where(l => l.Deleted == null).ToList();
        var preVat = Math.Max(0, lines.Sum(l => Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount)) - quote.Discount);
        var deposit = quote.DepositAmount;
        if (deposit <= 0 && quote.DepositPercent is > 0)
            deposit = Math.Round(preVat * quote.DepositPercent.Value / 100m, 0, MidpointRounding.AwayFromZero);
        if (deposit <= 0)
            deposit = Math.Round(quote.Total * 0.5m, 0, MidpointRounding.AwayFromZero);
        deposit = Math.Min(deposit, quote.Total);
        var depositPct = quote.DepositPercent is > 0
            ? quote.DepositPercent.Value.ToString("0.##", vn)
            : (preVat > 0 ? Math.Round(deposit / preVat * 100m, 2).ToString("0.##", vn) : "0");
        var payMethod = quote.PaymentMethod ?? "Chuyển khoản";
        var depositPayText = string.IsNullOrWhiteSpace(storeBankNo)
            ? payMethod
            : $"{payMethod} — TK {storeBankNo} ({storeBankName}), chủ TK {storeBankHolder}";
        return new Dictionary<string, string>
        {
            ["PaperSize"] = "A4",
            ["Ten_Cua_Hang"] = companyName,
            ["Ten_Cong_Ty"] = companyName,
            ["Dia_Chi_Chi_Nhanh"] = companyAddress,
            ["Dia_Chi_Cong_Ty"] = companyAddress,
            ["Dien_Thoai_Chi_Nhanh"] = companyPhone,
            ["Dien_Thoai_Cong_Ty"] = companyPhone,
            ["Email_Cua_Hang"] = storeEmail,
            ["MST_Cua_Hang"] = storeTaxCode,
            ["MST_Cong_Ty"] = storeTaxCode,
            ["Tai_Khoan_Cua_Hang"] = storeBankNo,
            ["Ngan_Hang_Cua_Hang"] = storeBankName,
            ["Chu_Tai_Khoan_Cua_Hang"] = storeBankHolder,
            ["Nguoi_Dai_Dien_Cua_Hang"] = storeRep,
            ["Chuc_Vu_Cua_Hang"] = storeTitle,
            ["Con_Dau"] = StampHtml(profile?.StampPngBase64),
            ["Tieu_De_In"] = TitleOf(kind),
            ["Ma_Don_Hang"] = docNo,
            ["Ma_Bao_Gia"] = quote.QuoteNo,
            ["So_Chung_Tu"] = docNo,
            ["So_Hop_Dong"] = kind == PosQuoteDocumentKind.Contract ? docNo : quote.QuoteNo,
            ["Ngay_Hop_Dong"] = now.ToString("dd/MM/yyyy", vn),
            ["Ngay"] = now.ToString("dd/MM/yyyy", vn),
            ["Gio"] = now.ToString("HH:mm", vn),
            ["Khach_Hang"] = quote.CustomerName ?? "",
            ["Ten_Cong_Ty_Khach"] = customerCompany,
            ["MST_Khach_Hang"] = customerTaxCode,
            ["Tai_Khoan_Khach_Hang"] = "",
            ["Ngan_Hang_Khach_Hang"] = "",
            ["Nguoi_Dai_Dien_Khach"] = customer?.LegalRepresentative ?? quote.CustomerName ?? "",
            ["Chuc_Vu_Khach"] = string.IsNullOrWhiteSpace(customer?.LegalTitle)
                ? "Giám đốc"
                : customer!.LegalTitle!,
            ["SDT"] = quote.CustomerPhone ?? "",
            ["Dia_Chi_Khach_Hang"] = quote.CustomerAddress ?? "",
            ["Dia_Diem_Thi_Cong"] = quote.CustomerAddress ?? "",
            ["Han_Bao_Gia"] = quote.ValidUntil?.ToLocalTime().ToString("dd/MM/yyyy", vn) ?? "",
            ["Tong_Tien_Hang"] = quote.SubTotal.ToString("#,##0", vn),
            ["Chiet_Khau_Hoa_Don"] = quote.Discount.ToString("#,##0", vn),
            ["Tien_Thue"] = quote.VatAmount.ToString("#,##0", vn),
            ["Thue"] = quote.VatAmount.ToString("#,##0", vn),
            ["VAT"] = quote.VatAmount.ToString("#,##0", vn),
            ["Tong_Cong"] = quote.Total.ToString("#,##0", vn),
            ["Khach_Can_Tra"] = quote.Total.ToString("#,##0", vn),
            ["Tam_Ung"] = deposit.ToString("#,##0", vn),
            ["Tien_Coc"] = deposit.ToString("#,##0", vn),
            ["Phan_Tram_Coc"] = depositPct,
            ["Gia_Tri_Truoc_VAT"] = preVat.ToString("#,##0", vn),
            ["Con_Lai_Hop_Dong"] = (quote.Total - deposit).ToString("#,##0", vn),
            ["Tien_Coc_Bang_Chu"] = PosVietnameseMoney.InWords(deposit),
            ["Con_Lai_Bang_Chu"] = PosVietnameseMoney.InWords(quote.Total - deposit),
            ["Ky_Han_Thi_Cong"] = "Theo thỏa thuận",
            ["Ky_Han_Thanh_Toan"] = "10 ngày kể từ ký hợp đồng",
            ["Tong_Cong_Bang_Chu"] = PosVietnameseMoney.InWords(quote.Total),
            ["Hinh_Thuc_Thanh_Toan"] = depositPayText,
            ["Dieu_Khoan"] = quote.Terms ?? "",
            ["Bao_Hanh"] = "12 tháng",
            ["Ghi_Chu"] = string.Join("\n", new[] { quote.Note, extraNote }.Where(s => !string.IsNullOrWhiteSpace(s))),
            ["Nguoi_Bao_Gia"] = quote.QuotedBy ?? quote.IssuedBy ?? "",
            ["Nguoi_Ban"] = quote.QuotedBy ?? "",
        };
    }

    static async Task<List<Dictionary<string, string>>> BuildLinesAsync(
        ZKTecoDbContext db,
        PosQuote quote,
        bool includeImages,
        string? contentRootPath)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        var active = quote.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder).ToList();
        var productIds = active.Where(l => l.ProductId.HasValue).Select(l => l.ProductId!.Value).Distinct().ToList();
        var imageByProduct = new Dictionary<Guid, string>();
        if (includeImages && productIds.Count > 0 && !string.IsNullOrWhiteSpace(contentRootPath))
        {
            var products = await db.PosProducts.AsNoTracking()
                .Where(p => productIds.Contains(p.Id) && p.Deleted == null)
                .Select(p => new { p.Id, p.ImageUrl })
                .ToListAsync();
            foreach (var p in products)
            {
                if (string.IsNullOrWhiteSpace(p.ImageUrl)) continue;
                imageByProduct[p.Id] = PosProductImageFiles.EmbedImgTag(contentRootPath, p.ImageUrl);
            }
        }

        var i = 1;
        return active.Select(l =>
        {
            var img = "";
            if (includeImages && l.ProductId is Guid pid)
                imageByProduct.TryGetValue(pid, out img);
            img ??= "";
            return new Dictionary<string, string>
            {
                ["STT"] = (i++).ToString(),
                ["Ma_Hang"] = l.ProductCode ?? "",
                ["Ten_Hang_Hoa"] = ProductLabel(l.ProductName, l.LineNote),
                ["Don_Vi_Tinh"] = l.UnitName ?? "",
                ["So_Luong"] = l.Qty.ToString("0.##", vn),
                ["Don_Gia"] = l.UnitPrice.ToString("#,##0", vn),
                ["Thanh_Tien"] = l.LineTotal.ToString("#,##0", vn),
                ["Chiet_Khau"] = l.DiscountAmount.ToString("#,##0", vn),
                ["Ghi_Chu"] = l.LineNote ?? "",
                ["Chieu_Dai"] = DimCell(l.Length, l.LineNote, "Dài"),
                ["Chieu_Rong"] = DimCell(l.Width, l.LineNote, "Rộng"),
                ["Chieu_Cao"] = DimCell(l.Height, l.LineNote, "Cao"),
                ["Bao_Hanh"] = l.WarrantyMonths is > 0 ? l.WarrantyMonths + " tháng" : "",
                ["Hinh_Anh"] = img,
            };
        }).ToList();
    }

    public static string DefaultA4Html(string title) => DefaultA4For(kindFromTitle(title));

    public static string DefaultA4For(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Contract => ContractHtml(),
        PosQuoteDocumentKind.Handover => HandoverHtml(),
        PosQuoteDocumentKind.Acceptance => AcceptanceHtml(),
        PosQuoteDocumentKind.PaymentRequest => PaymentRequestHtml(),
        _ => QuoteHtml(),
    };

    static PosQuoteDocumentKind kindFromTitle(string title)
    {
        var t = (title ?? "").ToUpperInvariant();
        if (t.Contains("HỢP ĐỒNG") || t.Contains("HOP DONG") || t.Contains("THI CÔNG"))
            return PosQuoteDocumentKind.Contract;
        if (t.Contains("NGHIỆM") || t.Contains("NGHIEM"))
            return PosQuoteDocumentKind.Acceptance;
        if (t.Contains("BÀN GIAO") || t.Contains("BAN GIAO"))
            return PosQuoteDocumentKind.Handover;
        if (t.Contains("THANH TOÁN") || t.Contains("THANH TOAN") || t.Contains("ĐỀ NGHỊ") || t.Contains("DE NGHI"))
            return PosQuoteDocumentKind.PaymentRequest;
        return PosQuoteDocumentKind.Quote;
    }

    static string Motto() =>
        """
        <div style="text-align:center;line-height:1.35">
          <div style="font-weight:bold">CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM</div>
          <div style="font-weight:bold">Độc lập - Tự do - Hạnh phúc</div>
          <div style="border-top:1px solid #000;width:180px;margin:4px auto 10px"></div>
        </div>
        """;

    static string ItemTable() =>
        """
        <table style="width:100%;border-collapse:collapse;table-layout:fixed;margin:8px 0;font-size:11px;line-height:1.3">
          <colgroup>
            <col width="46"/><col width="216"/><col width="62"/><col width="62"/>
            <col width="108"/><col width="108"/><col width="62"/><col width="108"/>
          </colgroup>
          <thead><tr style="background:#f3f4f6">
            <th style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">STT</th>
            <th style="width:28%;border:1px solid #111;padding:4px 4px;text-align:left">Tên hàng</th>
            <th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">ĐVT</th>
            <th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">SL</th>
            <th style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">Đơn giá</th>
            <th style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">Thành tiền</th>
            <th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">BH</th>
            <th style="width:14%;border:1px solid #111;padding:4px 2px;text-align:center">Ảnh</th>
          </tr></thead>
          <tbody><!--BEGIN_ITEMS-->
            <tr>
              <td style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{STT}</td>
              <td style="width:28%;border:1px solid #111;padding:4px 4px;text-align:left;vertical-align:middle">{Ten_Hang_Hoa}</td>
              <td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{Don_Vi_Tinh}</td>
              <td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{So_Luong}</td>
              <td style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right;vertical-align:middle">{Don_Gia}</td>
              <td style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right;vertical-align:middle">{Thanh_Tien}</td>
              <td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{Bao_Hanh}</td>
              <td style="width:14%;border:1px solid #111;padding:3px;text-align:center;vertical-align:middle">{Hinh_Anh}</td>
            </tr><!--END_ITEMS-->
          </tbody>
          <tfoot>
            <tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Tổng tiền hàng</td>
            <td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right"><b>{Tong_Tien_Hang}</b></td></tr>
            <tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Chiết khấu</td>
            <td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right">{Chiet_Khau_Hoa_Don}</td></tr>
            <tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Thuế GTGT</td>
            <td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right">{Tien_Thue}</td></tr>
            <tr style="background:#f8fafc"><td colspan="5" style="border:1px solid #111;padding:6px 6px;text-align:right"><b>TỔNG CỘNG</b></td>
            <td colspan="3" style="border:1px solid #111;padding:6px 6px;text-align:right"><b>{Tong_Cong}</b></td></tr>
          </tfoot>
        </table>
        """;

    static string QuoteHtml() =>
        $$"""
        <div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:12px">
          <table style="width:100%"><tr>
            <td style="width:50%;vertical-align:top">
              <div style="font-weight:bold;text-transform:uppercase">{Ten_Cong_Ty}</div>
              <div>MST: {MST_Cua_Hang}</div>
              <div>{Dia_Chi_Cong_Ty}</div>
              <div>ĐT: {Dien_Thoai_Cong_Ty} &nbsp; Email: {Email_Cua_Hang}</div>
              <div>TK: {Tai_Khoan_Cua_Hang} — {Ngan_Hang_Cua_Hang}</div>
              <div>Chủ TK: {Chu_Tai_Khoan_Cua_Hang}</div>
              <div>Đại diện: {Nguoi_Dai_Dien_Cua_Hang} — {Chuc_Vu_Cua_Hang}</div>
            </td>
            <td>{{Motto()}}<div style="text-align:center">{Dia_Chi_Cong_Ty}, ngày {Ngay}</div></td>
          </tr></table>
          <h2 style="text-align:center;margin:12px 0 4px">BẢNG BÁO GIÁ</h2>
          <div style="text-align:center">Số: <b>{So_Chung_Tu}</b> &nbsp; Theo BG: {Ma_Bao_Gia} &nbsp; Hiệu lực đến: <b>{Han_Bao_Gia}</b></div>
          <p><b>Kính gửi:</b> {Ten_Cong_Ty_Khach}<br/>
          MST: {MST_Khach_Hang} &nbsp; ĐT: {SDT}<br/>
          Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
          Đại diện: {Nguoi_Dai_Dien_Khach} — {Chuc_Vu_Khach}<br/>
          Hình thức thanh toán: {Hinh_Thuc_Thanh_Toan}</p>
          <p>Công ty chúng tôi xin trân trọng gửi Quý khách hàng bảng báo giá hàng hóa / dịch vụ như sau:</p>
          {{ItemTable()}}
          <div style="text-align:right;margin:4px 0 10px"><i>Bằng chữ: {Tong_Cong_Bang_Chu}</i></div>
          <p><b>Tiền cọc thực hiện hợp đồng:</b> <b>{Tien_Coc} VNĐ</b>
          ({Phan_Tram_Coc}% trên giá trị trước VAT: {Gia_Tri_Truoc_VAT} VNĐ).<br/>
          <b>Tài khoản nhận cọc:</b> {Tai_Khoan_Cua_Hang} — {Ngan_Hang_Cua_Hang} — Chủ TK: {Chu_Tai_Khoan_Cua_Hang}<br/>
          <b>Hình thức thanh toán cọc:</b> {Hinh_Thuc_Thanh_Toan}<br/>
          <b>Còn lại sau cọc:</b> {Con_Lai_Hop_Dong} VNĐ</p>
          <p><b>Điều khoản:</b><br/>{Dieu_Khoan}<br/>Bảo hành: {Bao_Hanh}<br/>{Ghi_Chu}</p>
          <p>Rất mong nhận được sự hợp tác của Quý khách hàng.<br/><b>Trân trọng!</b></p>
          <table style="width:100%;margin-top:16px;border-collapse:collapse"><tr>
            <td style="width:50%;text-align:center;vertical-align:top">KHÁCH HÀNG<br/><i>Ký, ghi rõ họ tên</i><div style="height:64px"></div><b>{Nguoi_Dai_Dien_Khach}</b></td>
            <td style="width:50%;text-align:center;vertical-align:top">ĐẠI DIỆN CÔNG TY<br/><i>{Chuc_Vu_Cua_Hang}</i><div style="text-align:center">{Con_Dau}</div><b>{Nguoi_Dai_Dien_Cua_Hang}</b></td>
          </tr></table>
        </div>
        """;

    static string ContractHtml() =>
        $$"""
        <div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:12px">
          {{Motto()}}
          <h2 style="text-align:center;margin:8px 0 4px">HỢP ĐỒNG THI CÔNG</h2>
          <div style="text-align:center">Số HĐ: <b>{So_Hop_Dong}</b> &nbsp; Theo báo giá: {Ma_Bao_Gia}</div>
          <p>- Căn cứ Bộ luật Dân sự số 91/2015/QH13 ngày 24/11/2015;<br/>
          - Căn cứ Luật Thương mại số 36/2005/QH11 ngày 14/6/2005;<br/>
          - Căn cứ nhu cầu của các bên.</p>
          <p>Hợp đồng này được ký kết ngày {Ngay} giữa hai đơn vị:</p>
          <p><b>BÊN A (Chủ đầu tư): {Ten_Cong_Ty_Khach}</b><br/>
          Mã số thuế: {MST_Khach_Hang}<br/>
          Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
          Điện thoại: {SDT}<br/>
          Tài khoản: {Tai_Khoan_Khach_Hang} — {Ngan_Hang_Khach_Hang}<br/>
          Đại diện: {Nguoi_Dai_Dien_Khach} — Chức vụ: {Chuc_Vu_Khach}</p>
          <p><b>BÊN B (Nhà thầu / shop): {Ten_Cong_Ty}</b><br/>
          Mã số thuế: {MST_Cua_Hang}<br/>
          Địa chỉ: {Dia_Chi_Cong_Ty}<br/>
          Điện thoại: {Dien_Thoai_Cong_Ty} &nbsp; Email: {Email_Cua_Hang}<br/>
          Tài khoản: {Tai_Khoan_Cua_Hang} tại {Ngan_Hang_Cua_Hang}<br/>
          Chủ tài khoản: {Chu_Tai_Khoan_Cua_Hang}<br/>
          Đại diện: {Nguoi_Dai_Dien_Cua_Hang} — Chức vụ: {Chuc_Vu_Cua_Hang}</p>
          <p>Sau khi thỏa thuận, Bên A giao cho Bên B cung cấp / lắp đặt các hạng mục dưới đây:</p>
          <p><b>Điều 1: Hạng mục thi công, giá trị hợp đồng</b><br/>Địa điểm: {Dia_Diem_Thi_Cong}</p>
          {{ItemTable()}}
          <p>Giá trị hợp đồng: <b>{Tong_Cong} VNĐ</b> (Bằng chữ: {Tong_Cong_Bang_Chu}).
          Trọn gói vật tư, nhân công, vận chuyển, lắp đặt, đã gồm thuế GTGT.</p>
          <p><b>Điều 2: Thời gian và phương thức thanh toán</b><br/>
          Hình thức: {Hinh_Thuc_Thanh_Toan}.<br/>
          Đợt 1: Bên A tạm ứng 50% — <b>{Tam_Ung} VNĐ</b> trong vòng {Ky_Han_Thanh_Toan}.<br/>
          Đợt 2: Thanh toán phần còn lại <b>{Con_Lai_Hop_Dong} VNĐ</b> sau nghiệm thu. Hồ sơ: biên bản nghiệm thu, đề nghị thanh toán, hóa đơn GTGT.</p>
          <p><b>Điều 3: Thời gian thi công</b><br/>
          Dự kiến {Ky_Han_Thi_Cong} kể từ ngày Bên B nhận tạm ứng, trừ bất khả kháng.</p>
          <p><b>Điều 4: Bảo hành</b><br/>{Bao_Hanh}. {Dieu_Khoan}</p>
          <p><b>Điều 5: Quyền và nghĩa vụ</b><br/>
          Bên A thanh toán đúng hạn. Bên B thi công đúng chủng loại, chất lượng, tiến độ và bảo hành theo Điều 4.</p>
          <p><b>Điều 6: Điều khoản chung</b><br/>
          Hợp đồng có hiệu lực từ ngày ký, lập thành 02 bản, mỗi bên giữ 01 bản có giá trị như nhau.</p>
          <table style="width:100%;margin-top:28px"><tr>
            <td style="width:50%;text-align:center"><b>ĐẠI DIỆN BÊN A</b><br/><i>Ký, ghi rõ họ tên</i><div style="height:56px"></div>{Nguoi_Dai_Dien_Khach}</td>
            <td style="width:50%;text-align:center"><b>ĐẠI DIỆN BÊN B</b><br/><i>Ký, ghi rõ họ tên</i><div style="height:56px"></div>{Nguoi_Dai_Dien_Cua_Hang}</td>
          </tr></table>
        </div>
        """;

    static string AcceptanceHtml() =>
        $$"""
        <div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:12px">
          <table style="width:100%"><tr>
            <td style="width:42%;font-weight:bold">{Ten_Cong_Ty}</td>
            <td>{{Motto()}}</td>
          </tr></table>
          <div style="text-align:right">{Dia_Chi_Cong_Ty}, ngày {Ngay}</div>
          <h2 style="text-align:center;margin:10px 0 4px">BIÊN BẢN NGHIỆM THU HOÀN THÀNH<br/>BÀN GIAO SẢN PHẨM ĐƯA VÀO SỬ DỤNG</h2>
          <div style="text-align:center">Số: <b>{So_Chung_Tu}</b> &nbsp; Theo HĐ/BG: {Ma_Bao_Gia}</div>
          <p><b>1. Đối tượng nghiệm thu</b><br/>
          - Tên hạng mục: theo bảng chi tiết bên dưới<br/>
          - Địa điểm: {Dia_Chi_Khach_Hang}<br/>
          - Căn cứ hợp đồng / báo giá: {Ma_Bao_Gia}</p>
          <p><b>2. Thành phần trực tiếp nghiệm thu</b><br/>
          ● Chủ đầu tư: {Khach_Hang} — ĐT {SDT} — {Dia_Chi_Khach_Hang}<br/>
          ● Nhà thầu: {Ten_Cong_Ty} — {Dia_Chi_Cong_Ty}</p>
          <p><b>3. Thời gian nghiệm thu:</b> ngày {Ngay} tại hiện trường.</p>
          <p><b>4. Đánh giá khối lượng / chất lượng</b></p>
          {{ItemTable()}}
          <p>Về chất lượng: Đạt yêu cầu. Ý kiến khác: {Ghi_Chu}</p>
          <p><b>Giá trị quyết toán:</b> {Tong_Cong} VNĐ (Bằng chữ: {Tong_Cong_Bang_Chu}).</p>
          <p><b>Kết luận:</b> Chấp nhận nghiệm thu hạng mục và đưa vào sử dụng.
          Biên bản lập thành 02 bản, mỗi bên 01 bản, có giá trị pháp lý như nhau.</p>
          <table style="width:100%;margin-top:28px"><tr>
            <td style="width:50%;text-align:center"><b>ĐẠI DIỆN CHỦ ĐẦU TƯ</b></td>
            <td style="width:50%;text-align:center"><b>ĐẠI DIỆN NHÀ THẦU</b></td>
          </tr></table>
        </div>
        """;

    static string HandoverHtml() =>
        $$"""
        <div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:12px">
          <table style="width:100%"><tr>
            <td style="width:42%;font-weight:bold">{Ten_Cong_Ty}</td>
            <td>{{Motto()}}</td>
          </tr></table>
          <div style="text-align:right">{Dia_Chi_Cong_Ty}, ngày {Ngay}</div>
          <h2 style="text-align:center;margin:10px 0 4px">BIÊN BẢN BÀN GIAO CÔNG TRÌNH</h2>
          <div style="text-align:center">Số: <b>{So_Chung_Tu}</b> &nbsp; Theo HĐ/BG: {Ma_Bao_Gia}</div>
          <p>Hôm nay, các bên tiến hành bàn giao hạng mục đã thi công:</p>
          <p><b>Bên giao (Nhà thầu):</b> {Ten_Cong_Ty} — {Dia_Chi_Cong_Ty}<br/>
          <b>Bên nhận (Chủ đầu tư):</b> {Khach_Hang} — {Dia_Chi_Khach_Hang} — ĐT {SDT}</p>
          {{ItemTable()}}
          <p>Tổng giá trị: <b>{Tong_Cong} VNĐ</b> ({Tong_Cong_Bang_Chu}).</p>
          <p>Bên nhận đã kiểm tra hiện trường, đồng ý nhận bàn giao. {Ghi_Chu}</p>
          <p>{Dieu_Khoan}</p>
          <table style="width:100%;margin-top:28px"><tr>
            <td style="width:50%;text-align:center"><b>BÊN NHẬN</b></td>
            <td style="width:50%;text-align:center"><b>BÊN GIAO</b></td>
          </tr></table>
        </div>
        """;

    static string PaymentRequestHtml() =>
        $$"""
        <div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:12px">
          <table style="width:100%"><tr>
            <td style="width:42%;vertical-align:top">
              <div style="font-weight:bold">{Ten_Cong_Ty}</div>
              <div>Số: {So_Chung_Tu}</div>
            </td>
            <td>{{Motto()}}</td>
          </tr></table>
          <div style="text-align:right">ngày {Ngay}</div>
          <h2 style="text-align:center;margin:12px 0 4px">ĐỀ NGHỊ THANH TOÁN</h2>
          <div style="text-align:center">V/v: Thanh toán theo báo giá / hợp đồng {Ma_Bao_Gia}</div>
          <p><b>Kính gửi:</b> {Khach_Hang}</p>
          <p>Căn cứ hợp đồng / báo giá số {Ma_Bao_Gia} ngày {Ngay} giữa {Khach_Hang} và {Ten_Cong_Ty}.</p>
          <p>Đến nay chúng tôi đã hoàn tất hạng mục theo danh sách:</p>
          {{ItemTable()}}
          <p>Nay kính đề nghị Quý Công ty thanh toán:</p>
          <p>- Giá trị đề nghị thanh toán: <b>{Tong_Cong} VNĐ</b> (Bằng chữ: {Tong_Cong_Bang_Chu}).<br/>
          - Hình thức thanh toán: {Hinh_Thuc_Thanh_Toan}</p>
          <p>Rất mong Quý Công ty xem xét, đối chiếu và thanh toán theo đúng tiến độ đã thỏa thuận.</p>
          <p>Trân trọng!</p>
          <table style="width:100%;margin-top:28px"><tr>
            <td style="width:50%"></td>
            <td style="width:50%;text-align:center"><b>ĐẠI DIỆN {Ten_Cong_Ty}</b><br/>{Chuc_Vu_Cua_Hang}</td>
          </tr></table>
        </div>
        """;
}
