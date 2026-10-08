using System.Globalization;
using System.Security.Cryptography;
using System.Text;
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
        bool includeStamp = true,
        Guid? templateId = null)
    {
        var docType = PrintDocumentTypeOf(kind);
        var templateHtml = await ResolveTemplateHtmlAsync(db, quote, docType, templateId);
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
        var stages = await db.Set<PosQuotePaymentStage>().AsNoTracking()
            .Where(x => x.QuoteId == quote.Id && x.StoreId == quote.StoreId && x.Deleted == null)
            .OrderBy(x => x.SortOrder)
            .ToListAsync();
        var collected = await db.Set<PosQuotePayment>().AsNoTracking()
            .Where(x => x.QuoteId == quote.Id && x.StoreId == quote.StoreId && x.Deleted == null)
            .SumAsync(x => (decimal?)x.Amount) ?? 0;
        var data = BuildData(quote, kind, docNo, extraNote, store, branch, customer, profile, stages, collected);
        var lines = await BuildLinesAsync(db, quote, includeImages, contentRootPath);
        data["Co_Anh"] = lines.Any(l => !string.IsNullOrWhiteSpace(l.GetValueOrDefault("Hinh_Anh"))) ? "1" : "";
        data["Co_Bao_Hanh_Dong"] = lines.Any(l => !string.IsNullOrWhiteSpace(l.GetValueOrDefault("Bao_Hanh"))) ? "1" : "";
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
        return "<img data-sbox=\"stamp\" src=\"data:image/png;base64," + s +
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
                // Hàng gia công theo m²: diện tích 1 bộ, tổng m², đơn giá / m²
                ["Dien_Tich"] = l.AreaM2 is > 0 ? l.AreaM2.Value.ToString("0.###", vn) : "",
                ["Tong_M2"] = l.AreaM2 is > 0 ? (l.AreaM2.Value * l.Qty).ToString("0.###", vn) : "",
                ["Don_Gia_M2"] = l.PricePerM2 is > 0 ? l.PricePerM2.Value.ToString("#,##0", vn) : "",
                ["Hinh_Anh"] = "",
            }).ToList();
    }

    /// <summary>
    /// Mẫu HTML: mẫu chọn riêng cho chứng từ → mẫu chọn trên báo giá → mẫu mặc định cửa hàng → mẫu chuẩn hệ thống.
    /// Chỉ nhận mẫu cùng loại chứng từ, cùng cửa hàng.
    /// </summary>
    static async Task<string> ResolveTemplateHtmlAsync(
        ZKTecoDbContext db, PosQuote quote, PosPrintDocumentType docType, Guid? documentTemplateId = null)
    {
        foreach (var id in new[] { documentTemplateId, quote.PrintTemplateId })
        {
            if (id is not Guid tid) continue;
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

    /// <summary>Trường đổi theo giờ in (ngày lập, giờ, ảnh) — không tính vào dấu số liệu.</summary>
    static readonly HashSet<string> VolatileKeys =
    [
        "Ngay", "Ngay_So", "Thang", "Nam", "Gio", "Ngay_HD_So", "Thang_HD", "Nam_HD",
        "Con_Dau", "Logo", "Hinh_Anh", "Co_Anh",
    ];

    /// <summary>
    /// Dấu (SHA-256) số liệu báo giá dùng cho chứng từ: khách, dòng hàng, tiền, đợt, đã thu, điều khoản…
    /// Lưu lúc sửa lời văn; khác dấu hiện tại → bản sửa riêng đã cũ so với báo giá.
    /// </summary>
    public static async Task<string> SourceHashAsync(
        ZKTecoDbContext db, PosQuote quote, PosQuoteDocumentKind kind, string docNo, string? note)
    {
        var (data, lines) = await BuildFieldsAsync(db, quote, kind, docNo, note);
        var sb = new StringBuilder();
        foreach (var (k, v) in data.Where(kv => !VolatileKeys.Contains(kv.Key)).OrderBy(kv => kv.Key, StringComparer.Ordinal))
            sb.Append(k).Append('=').Append(v).Append('\n');
        foreach (var l in lines)
        {
            foreach (var (k, v) in l.Where(kv => !VolatileKeys.Contains(kv.Key)).OrderBy(kv => kv.Key, StringComparer.Ordinal))
                sb.Append(k).Append('=').Append(v).Append(';');
            sb.Append('\n');
        }
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString())));
    }

    static readonly Regex StampImgRe = new(
        @"<img\b(?=[^>]*(?:data-sbox=[""']stamp[""']|width=[""']112[""'][^>]*height=[""']112[""']))[^>]*>",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>Bỏ ảnh con dấu khỏi bản đã sửa lời văn (in «không dấu»), giữ chỗ trống ký tên.</summary>
    public static string StripStamp(string html) =>
        StampImgRe.Replace(html ?? "", "<div style=\"height:48px\"></div>");

    /// <summary>
    /// Nội dung in của MỘT chứng từ đã lập: lời văn sửa riêng (giữ nguyên) → nếu không thì dựng lại từ số liệu
    /// hiện tại với mẫu chọn riêng của chứng từ. <c>IsStale</c> = bản sửa riêng không còn khớp số liệu báo giá.
    /// </summary>
    public static async Task<(string Html, bool IsStale)> RenderDocumentAsync(
        ZKTecoDbContext db, PosQuote quote, PosQuoteDocument doc,
        bool includeStamp = true, bool includeImages = false, string? contentRootPath = null)
    {
        if (doc.IsCustomWording && !string.IsNullOrWhiteSpace(doc.HtmlContent))
        {
            var stale = doc.SourceHash != null
                && doc.SourceHash != await SourceHashAsync(db, quote, doc.Kind, doc.DocNo, doc.Note);
            return (includeStamp ? doc.HtmlContent : StripStamp(doc.HtmlContent), stale);
        }
        var html = await BuildAsync(db, quote, doc.Kind, doc.DocNo, doc.Note,
            includeImages, contentRootPath, includeStamp, doc.PrintTemplateId);
        return (html, false);
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
        PosStoreCommercialProfile? profile,
        IReadOnlyList<PosQuotePaymentStage>? stages = null,
        decimal collected = 0)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        // Máy chủ chạy giờ UTC — mọi ngày in trên chứng từ theo giờ Việt Nam.
        var now = DateTime.UtcNow.AddHours(7);
        static DateTime Vn(DateTime d) => d.Kind == DateTimeKind.Local ? d : d.AddHours(7);
        string Day(DateTime? d) => d.HasValue ? Vn(d.Value).ToString("dd/MM/yyyy", vn) : "";
        string Money(decimal v) => v.ToString("#,##0", vn);

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
        var contactName = FirstText(quote.CustomerName, customer?.Name);
        var customerCompany = FirstText(customer?.CompanyName);
        var benA = FirstText(customerCompany, contactName);
        var customerRep = FirstText(customer?.LegalRepresentative, contactName);
        var lines = quote.Lines.Where(l => l.Deleted == null).ToList();
        var preVat = quote.VatMode is "included" or "added" or "none"
            ? Math.Max(0, quote.Total - quote.VatAmount)
            : Math.Max(0, lines.Sum(l => Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount)) - quote.Discount);
        var vatRateText = (quote.VatPercent ?? 8m).ToString("0.##", vn);
        var total = quote.Total;

        // ── Đợt thanh toán (đợt nhập % tính lại trên giá trị hợp đồng hiện tại) — chia số đã thu theo thứ tự ──
        var stageRows = new List<Dictionary<string, string>>();
        var left = collected;
        (string Title, decimal Remaining)? nextDue = null;
        var stageList = stages ?? [];
        var i = 1;
        foreach (var st in stageList)
        {
            var amount = st.Percent is > 0 ? Math.Round(total * st.Percent.Value / 100m, 0, MidpointRounding.AwayFromZero) : st.Amount;
            var paid = Math.Min(amount, Math.Max(0, left));
            left -= paid;
            var remaining = Math.Max(0, amount - paid);
            if (remaining > 0 && nextDue == null) nextDue = (st.Title, remaining);
            stageRows.Add(new Dictionary<string, string>
            {
                ["Dot_STT"] = (i++).ToString(),
                ["Dot_Ten"] = st.Title,
                ["Dot_Phan_Tram"] = st.Percent is > 0
                    ? st.Percent.Value.ToString("0.##", vn) + "%"
                    : (total > 0 ? Math.Round(amount / total * 100m, 1).ToString("0.#", vn) + "%" : ""),
                ["Dot_So_Tien"] = Money(amount),
                ["Dot_Han"] = Day(st.DueDate),
                ["Dot_Da_Thu"] = Money(paid),
                ["Dot_Con_Lai"] = Money(remaining),
                ["Dot_Ghi_Chu"] = st.Note ?? "",
            });
        }

        // ── Đặt cọc: có đợt → đợt 1; không thì theo báo giá (không tự gán 50% khi không yêu cầu cọc) ──
        decimal deposit;
        string depositPct;
        string depositBase;
        if (stageRows.Count > 0)
        {
            deposit = decimal.Parse(stageRows[0]["Dot_So_Tien"].Replace(".", "").Replace(",", ""), CultureInfo.InvariantCulture);
            depositPct = stageRows[0]["Dot_Phan_Tram"].TrimEnd('%');
            depositBase = "giá trị hợp đồng";
        }
        else
        {
            deposit = quote.DepositAmount > 0
                ? quote.DepositAmount
                : quote.DepositPercent is > 0
                    ? Math.Round(preVat * quote.DepositPercent.Value / 100m, 0, MidpointRounding.AwayFromZero)
                    : 0;
            deposit = Math.Min(deposit, total);
            depositPct = quote.DepositPercent is > 0
                ? quote.DepositPercent.Value.ToString("0.##", vn)
                : (preVat > 0 && deposit > 0 ? Math.Round(deposit / preVat * 100m, 1).ToString("0.#", vn) : "");
            depositBase = "giá trị trước VAT";
        }
        var remainAfterDeposit = Math.Max(0, total - deposit);
        var stillDue = Math.Max(0, total - collected);
        var request = nextDue?.Remaining ?? stillDue;
        var requestTitle = nextDue?.Title ?? (collected > 0 ? "Thanh toán phần còn lại" : "Thanh toán giá trị hợp đồng");

        var payMethod = FirstText(quote.PaymentMethod, "Chuyển khoản");

        // ── Ngày hợp đồng / thời hạn ──
        var contractNo = FirstText(quote.ContractNo, kind == PosQuoteDocumentKind.Contract ? docNo : null);
        DateTime? contractDate = quote.ContractSignedAt.HasValue ? Vn(quote.ContractSignedAt.Value)
            : kind == PosQuoteDocumentKind.Contract ? now : null;
        var doneBy = quote.HandoverDueAt ?? quote.InstallDueAt;
        var term = doneBy.HasValue ? $"hoàn thành trước ngày {Day(doneBy)}" : "";
        if (quote.InstallDueAt.HasValue && quote.HandoverDueAt.HasValue)
            term = $"lắp đặt trước ngày {Day(quote.InstallDueAt)}, bàn giao trước ngày {Day(quote.HandoverDueAt)}";

        // ── Bảo hành / điều khoản: hồ sơ thương mại → từng dòng hàng ──
        var warranty = FirstText(profile?.WarrantyPolicy);
        if (warranty.Length == 0 && lines.Any(l => l.WarrantyMonths is > 0))
            warranty = "Theo thời hạn bảo hành ghi tại từng hạng mục, tính từ ngày nghiệm thu bàn giao";

        var vatText = quote.VatMode switch
        {
            "included" => $"Giá đã bao gồm thuế GTGT {vatRateText}%",
            "added" => $"Giá đã cộng thuế GTGT {vatRateText}%",
            "none" => "Giá không bao gồm thuế GTGT",
            _ => "Thuế GTGT tính theo từng mặt hàng",
        };

        var data = new Dictionary<string, string>
        {
            ["PaperSize"] = "A4",
            ["Ten_Cua_Hang"] = companyName,
            ["Ten_Cong_Ty"] = companyName,
            ["Dia_Chi_Chi_Nhanh"] = companyAddress,
            ["Dia_Chi_Cong_Ty"] = companyAddress,
            ["Dien_Thoai_Chi_Nhanh"] = companyPhone,
            ["Dien_Thoai_Cong_Ty"] = companyPhone,
            ["Email_Cua_Hang"] = storeEmail,
            // Mẫu cũ của cửa hàng (soạn trên app) dùng dòng email dựng sẵn.
            ["Dong_Email"] = string.IsNullOrWhiteSpace(storeEmail) ? "" : "Email: " + storeEmail.Trim(),
            ["MST_Cua_Hang"] = storeTaxCode,
            ["MST_Cong_Ty"] = storeTaxCode,
            ["Tai_Khoan_Cua_Hang"] = storeBankNo,
            ["Ngan_Hang_Cua_Hang"] = storeBankName,
            ["Chu_Tai_Khoan_Cua_Hang"] = storeBankHolder,
            ["Nguoi_Dai_Dien_Cua_Hang"] = storeRep,
            ["Chuc_Vu_Cua_Hang"] = storeTitle,
            ["Con_Dau"] = StampHtml(profile?.StampPngBase64),
            ["Logo"] = StampHtml(profile?.LogoPngBase64),
            ["Tieu_De_In"] = TitleOf(kind),
            ["Ma_Don_Hang"] = docNo,
            ["Ma_Bao_Gia"] = quote.QuoteNo,
            ["So_Chung_Tu"] = docNo,
            ["So_Hop_Dong"] = contractNo,
            ["Ngay_Hop_Dong"] = Day(contractDate),
            ["Ngay_HD_So"] = (contractDate ?? now).ToString("dd", vn),
            ["Thang_HD"] = (contractDate ?? now).ToString("MM", vn),
            ["Nam_HD"] = (contractDate ?? now).ToString("yyyy", vn),
            ["Ngay"] = now.ToString("dd/MM/yyyy", vn),
            ["Ngay_So"] = now.ToString("dd", vn),
            ["Thang"] = now.ToString("MM", vn),
            ["Nam"] = now.ToString("yyyy", vn),
            ["Gio"] = now.ToString("HH:mm", vn),
            ["Khach_Hang"] = contactName,
            ["Ben_A_Ten"] = benA,
            ["Nguoi_Lien_He_Khac"] = customerCompany.Length > 0 && !string.Equals(customerCompany, contactName, StringComparison.OrdinalIgnoreCase) && contactName.Length > 0 ? "1" : "",
            ["Ten_Cong_Ty_Khach"] = benA,
            ["MST_Khach_Hang"] = customer?.TaxCode ?? "",
            ["Tai_Khoan_Khach_Hang"] = "",
            ["Ngan_Hang_Khach_Hang"] = "",
            ["Email_Khach_Hang"] = customer?.Email ?? "",
            ["Nguoi_Dai_Dien_Khach"] = customerRep,
            ["Chuc_Vu_Khach"] = customerCompany.Length > 0 ? FirstText(customer?.LegalTitle, "Giám đốc") : FirstText(customer?.LegalTitle),
            ["SDT"] = FirstText(quote.CustomerPhone, customer?.Phone),
            ["Dia_Chi_Khach_Hang"] = FirstText(quote.CustomerAddress, customer?.Address),
            ["Dia_Diem_Thi_Cong"] = FirstText(quote.CustomerAddress, customer?.Address),
            ["Dia_Diem_Ky"] = "",
            ["Han_Bao_Gia"] = Day(quote.ValidUntil),
            ["Tong_Tien_Hang"] = Money(quote.SubTotal),
            ["Chiet_Khau_Hoa_Don"] = Money(quote.Discount),
            ["Tien_Thue"] = Money(quote.VatAmount),
            ["Thue"] = Money(quote.VatAmount),
            ["VAT"] = Money(quote.VatAmount),
            ["Thue_Suat"] = quote.VatMode is "included" or "added" ? vatRateText + "%" : "",
            ["Cach_Tinh_VAT"] = vatText,
            ["Tong_Cong"] = Money(total),
            ["Khach_Can_Tra"] = Money(total),
            ["Tong_Cong_Bang_Chu"] = PosVietnameseMoney.InWords(total),
            ["Gia_Tri_Truoc_VAT"] = Money(preVat),
            ["Tam_Ung"] = deposit > 0 ? Money(deposit) : "",
            ["Tien_Coc"] = deposit > 0 ? Money(deposit) : "",
            ["Phan_Tram_Coc"] = depositPct,
            ["Coc_Tinh_Tren"] = depositBase,
            ["Tien_Coc_Bang_Chu"] = deposit > 0 ? PosVietnameseMoney.InWords(deposit) : "",
            ["Con_Lai_Hop_Dong"] = Money(remainAfterDeposit),
            ["Con_Lai_Bang_Chu"] = PosVietnameseMoney.InWords(remainAfterDeposit),
            ["Da_Thanh_Toan"] = collected > 0 ? Money(collected) : "",
            ["Da_Thanh_Toan_Hien"] = Money(collected),
            ["Con_Phai_Thu"] = Money(stillDue),
            ["Con_Phai_Thu_Bang_Chu"] = PosVietnameseMoney.InWords(stillDue),
            ["De_Nghi_Dot"] = requestTitle,
            ["De_Nghi_So_Tien"] = Money(request),
            ["De_Nghi_Bang_Chu"] = PosVietnameseMoney.InWords(request),
            ["Co_Dot_Thanh_Toan"] = stageRows.Count > 0 ? "1" : "",
            [PosPrintTemplateHtmlRenderer.StagesKey] = System.Text.Json.JsonSerializer.Serialize(stageRows),
            ["Ky_Han_Thi_Cong"] = term,
            ["Ngay_San_Xuat"] = Day(quote.ProductionDueAt),
            ["Ngay_Lap_Dat"] = Day(quote.InstallDueAt),
            ["Ngay_Ban_Giao"] = Day(quote.HandoverDueAt),
            ["Ky_Han_Thanh_Toan"] = stageRows.Count > 0 ? "theo tiến độ các đợt tại Điều 2" : "",
            ["Hinh_Thuc_Thanh_Toan"] = payMethod,
            ["Dieu_Khoan"] = FirstText(quote.Terms, profile?.DefaultTerms),
            ["Bao_Hanh"] = warranty,
            ["Ton_Tai"] = "Không có.",
            ["Ghi_Chu"] = string.Join("\n", new[] { quote.Note, quote.ContractNote, extraNote }
                .Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x!.Trim()).Distinct()),
            ["Nguoi_Bao_Gia"] = quote.QuotedBy ?? quote.IssuedBy ?? "",
            ["Nguoi_Ban"] = quote.QuotedBy ?? "",
        };
        return data;
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
                ["Dien_Tich"] = l.AreaM2 is > 0 ? l.AreaM2.Value.ToString("0.###", vn) : "",
                ["Tong_M2"] = l.AreaM2 is > 0 ? (l.AreaM2.Value * l.Qty).ToString("0.###", vn) : "",
                ["Don_Gia_M2"] = l.PricePerM2 is > 0 ? l.PricePerM2.Value.ToString("#,##0", vn) : "",
                ["Hinh_Anh"] = img,
            };
        }).ToList();
    }

    public static string DefaultA4Html(string title) => DefaultA4For(kindFromTitle(title));

    public static string DefaultA4For(PosQuoteDocumentKind kind) => LoadA4(kind switch
    {
        PosQuoteDocumentKind.Contract => "Contract",
        PosQuoteDocumentKind.Handover => "Handover",
        PosQuoteDocumentKind.Acceptance => "Acceptance",
        PosQuoteDocumentKind.PaymentRequest => "PaymentRequest",
        _ => "Quote",
    });

    static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string> A4Cache = new();

    /// <summary>Mẫu A4 mặc định — một nguồn duy nhất: PrintTemplates/A4/{name}.html (app Flutter sinh từ cùng file).</summary>
    static string LoadA4(string name) => A4Cache.GetOrAdd(name, n =>
    {
        using var stream = typeof(PosQuoteDocumentHtml).Assembly.GetManifestResourceStream($"Sbox.A4.{n}.html");
        if (stream == null) return "<div>{Tieu_De_In}</div>";
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    });

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
}
