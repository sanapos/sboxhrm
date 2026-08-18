using ClosedXML.Excel;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

internal record SampleCatalogExcelRow(
    Guid? Id,
    string Name,
    string? Barcode,
    string? UnitName,
    string? BrandName,
    string? CategoryName,
    PosProductSampleKind Kind,
    PosProductType ProductType,
    decimal? DefaultPrice,
    decimal? DefaultCostPrice,
    decimal VatRate,
    bool VatExempt,
    string? Description,
    int SortOrder,
    bool IsActive,
    string? SellProfiles = null);

internal static class PosProductSampleCatalogExcel
{
    public static readonly string[] Headers =
    [
        "Id", "Tên hàng", "Mã vạch", "Đơn vị", "Nhóm hàng", "Thương hiệu",
        "Loại mẫu", "Loại hàng", "Giá bán", "Giá vốn", "VAT %", "KCT",
        "Mô tả", "Thứ tự", "Đang dùng", "Ngành",
    ];

    public static byte[] BuildWorkbook(
        IReadOnlyList<SampleCatalogExcelRow> rows,
        IReadOnlyList<(string Name, string Kind, int Sort)>? categories = null)
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Hang mau");
        for (var i = 0; i < Headers.Length; i++)
        {
            ws.Cell(1, i + 1).Value = Headers[i];
            ws.Cell(1, i + 1).Style.Font.Bold = true;
        }

        var r = 2;
        foreach (var row in rows)
        {
            ws.Cell(r, 1).Value = row.Id?.ToString() ?? "";
            ws.Cell(r, 2).Value = row.Name;
            ws.Cell(r, 3).Value = row.Barcode ?? "";
            ws.Cell(r, 4).Value = row.UnitName ?? "";
            ws.Cell(r, 5).Value = row.CategoryName ?? "";
            ws.Cell(r, 6).Value = row.BrandName ?? "";
            ws.Cell(r, 7).Value = KindLabel(row.Kind);
            ws.Cell(r, 8).Value = PosProductTypeRules.DisplayName(row.ProductType);
            if (row.DefaultPrice.HasValue) ws.Cell(r, 9).Value = row.DefaultPrice.Value;
            if (row.DefaultCostPrice.HasValue) ws.Cell(r, 10).Value = row.DefaultCostPrice.Value;
            ws.Cell(r, 11).Value = row.VatExempt ? 0 : row.VatRate;
            ws.Cell(r, 12).Value = row.VatExempt ? "Có" : "Không";
            ws.Cell(r, 13).Value = row.Description ?? "";
            ws.Cell(r, 14).Value = row.SortOrder;
            ws.Cell(r, 15).Value = row.IsActive ? "Có" : "Không";
            ws.Cell(r, 16).Value = row.SellProfiles ?? "";
            r++;
        }

        ws.Columns(1, Headers.Length).AdjustToContents();
        ws.Column(1).Width = 12;
        ws.SheetView.FreezeRows(1);

        var hint = wb.Worksheets.Add("Huong dan");
        hint.Cell(1, 1).Value = "Hướng dẫn nhập catalog mẫu POS";
        hint.Cell(1, 1).Style.Font.Bold = true;
        hint.Cell(2, 1).Value = "• Tên hàng bắt buộc. Id để trống = thêm mới; điền Id = cập nhật mẫu có sẵn.";
        hint.Cell(3, 1).Value = "• Trùng mã vạch hoặc trùng tên (khi không có Id) sẽ cập nhật dòng cũ.";
        hint.Cell(4, 1).Value = "• Loại mẫu: Có mã vạch | Món ăn | Đồ uống  (hoặc Packaged / Food / Drink).";
        hint.Cell(5, 1).Value = "• Loại hàng: Hàng hóa | Dịch vụ | Combo | Nguyên vật liệu | Topping.";
        hint.Cell(6, 1).Value = "• KCT / Đang dùng: Có, Không, TRUE, FALSE, 1, 0.";
        hint.Cell(7, 1).Value = "• Ảnh không nhập bằng Excel — upload riêng trên Super Admin (độ phân giải tới 1920px).";
        hint.Cell(9, 1).Value = "• Ngành: Retail,Salon,RoomHourly,Restaurant,Gym,Hotel — cách nhau bởi dấu phẩy. Để trống = mọi ngành.";
        hint.Column(1).Width = 110;

        var catSheet = wb.Worksheets.Add("Nhom hang");
        catSheet.Cell(1, 1).Value = "Tên nhóm";
        catSheet.Cell(1, 2).Value = "Loại mẫu";
        catSheet.Cell(1, 3).Value = "Thứ tự";
        catSheet.Row(1).Style.Font.Bold = true;
        if (categories != null)
        {
            var cr = 2;
            foreach (var c in categories)
            {
                catSheet.Cell(cr, 1).Value = c.Name;
                catSheet.Cell(cr, 2).Value = c.Kind;
                catSheet.Cell(cr, 3).Value = c.Sort;
                cr++;
            }
        }
        catSheet.Columns(1, 3).AdjustToContents();

        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return stream.ToArray();
    }

    public static List<SampleCatalogExcelRow> Parse(Stream stream)
    {
        using var wb = new XLWorkbook(stream);
        var ws = wb.Worksheets.First(s =>
            !s.Name.StartsWith("Huong", StringComparison.OrdinalIgnoreCase) &&
            !s.Name.StartsWith("Hướng", StringComparison.OrdinalIgnoreCase) &&
            !s.Name.StartsWith("Nhom", StringComparison.OrdinalIgnoreCase) &&
            !s.Name.StartsWith("Nhóm", StringComparison.OrdinalIgnoreCase));

        var headerRow = 1;
        var lastHeader = Math.Min(8, ws.LastRowUsed()?.RowNumber() ?? 1);
        for (var r = 1; r <= lastHeader; r++)
        {
            var line = string.Join(' ', ws.Row(r).CellsUsed().Select(c => c.GetString()));
            if (LooksLikeHeader(line))
            {
                headerRow = r;
                break;
            }
        }

        int idCol = -1, nameCol = -1, barcodeCol = -1, unitCol = -1, catCol = -1, brandCol = -1;
        int kindCol = -1, typeCol = -1, priceCol = -1, costCol = -1, vatCol = -1, kctCol = -1;
        int descCol = -1, sortCol = -1, activeCol = -1, sellCol = -1;
        const int scanCols = 20;
        for (var c = 1; c <= scanCols; c++)
        {
            var h = Norm(ws.Cell(headerRow, c).GetString());
            if (h.Length == 0) continue;
            if (idCol < 0 && (h == "id" || h == "guid" || h.Contains("mauid"))) idCol = c;
            if (nameCol < 0 && (h.Contains("tenhang") || h == "ten" || h == "name" || h == "tensanpham" || h == "tensp"))
                nameCol = c;
            if (barcodeCol < 0 && (h.Contains("mavach") || h.Contains("barcode") || h.Contains("ean")))
                barcodeCol = c;
            if (unitCol < 0 && (h.Contains("donvi") || h.Contains("unit") || h == "dvt"))
                unitCol = c;
            if (catCol < 0 && (h.Contains("nhomhang") || h == "nhom" || h.Contains("category")))
                catCol = c;
            if (brandCol < 0 && (h.Contains("thuonghieu") || h.Contains("brand") || h.Contains("nhanhieu")))
                brandCol = c;
            if (kindCol < 0 && (h.Contains("loaimau") || h == "kind" || h.Contains("nhommau")))
                kindCol = c;
            if (typeCol < 0 && (h.Contains("loaihang") || h.Contains("producttype") || h == "type"))
                typeCol = c;
            if (priceCol < 0 && (h.Contains("giaban") || h.Contains("defaultprice") || h == "gia"))
                priceCol = c;
            if (costCol < 0 && (h.Contains("giavon") || h.Contains("cost") || h.Contains("gianhap")))
                costCol = c;
            if (vatCol < 0 && (h.Contains("vat") || h.Contains("thue")))
                vatCol = c;
            if (kctCol < 0 && (h == "kct" || h.Contains("khongchiuthue") || h.Contains("vatexempt")))
                kctCol = c;
            if (descCol < 0 && (h.Contains("mota") || h.Contains("desc")))
                descCol = c;
            if (sortCol < 0 && (h.Contains("thutu") || h.Contains("sort")))
                sortCol = c;
            if (activeCol < 0 && (h.Contains("dangdung") || h.Contains("active") || h == "hien"))
                activeCol = c;
            if (sellCol < 0 && (h.Contains("nganh") || h.Contains("sellprofile") || h.Contains("hosonganh")))
                sellCol = c;
        }

        if (nameCol < 0) nameCol = 2;

        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        var rows = new List<SampleCatalogExcelRow>();
        for (var r = headerRow + 1; r <= lastRow; r++)
        {
            var name = ws.Cell(r, nameCol).GetString().Trim();
            if (name.Length == 0) continue;

            Guid? id = null;
            if (idCol > 0 && Guid.TryParse(ws.Cell(r, idCol).GetString().Trim(), out var parsedId))
                id = parsedId;

            var vatExempt = kctCol > 0 && ParseBool(ws.Cell(r, kctCol).GetString(), false);
            var vat = vatExempt ? 0m : (vatCol > 0 ? ParseDecimal(ws.Cell(r, vatCol)) ?? 8m : 8m);

            rows.Add(new SampleCatalogExcelRow(
                id,
                name,
                barcodeCol > 0 ? EmptyToNull(ws.Cell(r, barcodeCol).GetString()) : null,
                unitCol > 0 ? EmptyToNull(ws.Cell(r, unitCol).GetString()) : null,
                brandCol > 0 ? EmptyToNull(ws.Cell(r, brandCol).GetString()) : null,
                catCol > 0 ? EmptyToNull(ws.Cell(r, catCol).GetString()) : null,
                kindCol > 0 ? ParseKind(ws.Cell(r, kindCol).GetString()) : PosProductSampleKind.Packaged,
                typeCol > 0 ? PosProductTypeRules.Parse(ws.Cell(r, typeCol).GetString()) : PosProductType.Goods,
                priceCol > 0 ? ParseDecimal(ws.Cell(r, priceCol)) : null,
                costCol > 0 ? ParseDecimal(ws.Cell(r, costCol)) : null,
                Math.Clamp(vat, 0, 100),
                vatExempt,
                descCol > 0 ? EmptyToNull(ws.Cell(r, descCol).GetString()) : null,
                sortCol > 0 ? ParseInt(ws.Cell(r, sortCol).GetString()) : 0,
                activeCol <= 0 || ParseBool(ws.Cell(r, activeCol).GetString(), true),
                sellCol > 0 ? EmptyToNull(ws.Cell(r, sellCol).GetString()) : null));
        }

        return rows;
    }

    public static string KindLabel(PosProductSampleKind kind) => kind switch
    {
        PosProductSampleKind.Food => "Món ăn",
        PosProductSampleKind.Drink => "Đồ uống",
        _ => "Có mã vạch",
    };

    public static PosProductSampleKind ParseKind(string? raw)
    {
        var s = Norm(raw ?? "");
        if (s.Contains("food") || s.Contains("monan") || s.Contains("mon an") || s == "1")
            return PosProductSampleKind.Food;
        if (s.Contains("drink") || s.Contains("douong") || s.Contains("do uong") || s == "2")
            return PosProductSampleKind.Drink;
        return PosProductSampleKind.Packaged;
    }

    static bool LooksLikeHeader(string line)
    {
        var n = Norm(line);
        return n.Contains("tenhang") || n.Contains("mavach") || n.Contains("barcode") || n == "ten";
    }

    static string Norm(string s)
    {
        var t = s.Trim().ToLowerInvariant();
        t = t.Replace(" ", "").Replace("_", "").Replace("-", "");
        t = t.Replace("đ", "d").Replace("á", "a").Replace("à", "a").Replace("ả", "a").Replace("ã", "a").Replace("ạ", "a")
            .Replace("ă", "a").Replace("ắ", "a").Replace("ằ", "a").Replace("ẳ", "a").Replace("ẵ", "a").Replace("ặ", "a")
            .Replace("â", "a").Replace("ấ", "a").Replace("ầ", "a").Replace("ẩ", "a").Replace("ẫ", "a").Replace("ậ", "a")
            .Replace("é", "e").Replace("è", "e").Replace("ẻ", "e").Replace("ẽ", "e").Replace("ẹ", "e")
            .Replace("ê", "e").Replace("ế", "e").Replace("ề", "e").Replace("ể", "e").Replace("ễ", "e").Replace("ệ", "e")
            .Replace("í", "i").Replace("ì", "i").Replace("ỉ", "i").Replace("ĩ", "i").Replace("ị", "i")
            .Replace("ó", "o").Replace("ò", "o").Replace("ỏ", "o").Replace("õ", "o").Replace("ọ", "o")
            .Replace("ô", "o").Replace("ố", "o").Replace("ồ", "o").Replace("ổ", "o").Replace("ỗ", "o").Replace("ộ", "o")
            .Replace("ơ", "o").Replace("ớ", "o").Replace("ờ", "o").Replace("ở", "o").Replace("ỡ", "o").Replace("ợ", "o")
            .Replace("ú", "u").Replace("ù", "u").Replace("ủ", "u").Replace("ũ", "u").Replace("ụ", "u")
            .Replace("ư", "u").Replace("ứ", "u").Replace("ừ", "u").Replace("ử", "u").Replace("ữ", "u").Replace("ự", "u")
            .Replace("ý", "y").Replace("ỳ", "y").Replace("ỷ", "y").Replace("ỹ", "y").Replace("ỵ", "y");
        return t;
    }

    static string? EmptyToNull(string? s)
    {
        var t = s?.Trim();
        return string.IsNullOrEmpty(t) ? null : t;
    }

    static decimal? ParseDecimal(IXLCell cell)
    {
        if (cell.TryGetValue<double>(out var d)) return (decimal)d;
        var raw = cell.GetString().Trim().Replace(",", "").Replace(" ", "");
        if (decimal.TryParse(raw, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var v))
            return v;
        return null;
    }

    static int ParseInt(string raw)
    {
        var t = raw.Trim();
        return int.TryParse(t, out var n) ? n : 0;
    }

    static bool ParseBool(string raw, bool fallback)
    {
        var s = Norm(raw);
        if (s is "1" or "true" or "yes" or "co" or "x") return true;
        if (s is "0" or "false" or "no" or "khong" or "") return s.Length == 0 ? fallback : false;
        return fallback;
    }
}
