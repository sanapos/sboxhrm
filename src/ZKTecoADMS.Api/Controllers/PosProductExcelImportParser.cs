using System.Globalization;

using System.Text;

using System.Text.RegularExpressions;

using ClosedXML.Excel;

using ZKTecoADMS.Domain.Enums;



namespace ZKTecoADMS.Api.Controllers;



internal static class PosProductExcelImportParser

{

    sealed class ColumnMap

    {

        public int CodeCol = -1;

        public int BarcodeCol = -1;

        public int NameCol = -1;

        public int CategoryCol = -1;

        public int BrandCol = -1;

        public int SupplierCol = -1;

        public int CostCol = -1;

        public int PriceCol = -1;

        public int StockCol = -1;

        public int MinStockCol = -1;

        public int MaxStockCol = -1;

        public int UnitCol = -1;

        public int TypeCol = -1;

        public int DirectSaleCol = -1;

        public int WeightCol = -1;

        public int LocationCol = -1;

        public int DescCol = -1;

        public int PrinterCol = -1;
        public int IsActiveCol = -1;
        public int ImageCol = -1;
    }



    sealed class ComboColumnMap

    {

        public int ComboCodeCol = -1;

        public int ComponentCodeCol = -1;

        public int QtyCol = -1;

    }



    public record ImportRow(

        string? ProductCode,

        string? Barcode,

        string Name,

        string? CategoryName,

        string? BrandName,

        string? SupplierName,

        decimal CostPrice,

        decimal BasePrice,

        decimal OnHandQty,

        decimal MinStockQty,

        decimal MaxStockQty,

        string BaseUnitName,

        PosProductType ProductType,

        bool IsDirectSale,

        decimal? Weight,

        string? LocationName,

        string? Description,
        string? PrinterName,
        bool? IsActive = null,
        string? ImageUrl = null);



    public record ComboLineImportRow(

        string ComboProductCode,

        string ComponentProductCode,

        decimal Qty);



    public record ParseResult(List<ImportRow> Products, List<ComboLineImportRow> ComboLines);



    public static ParseResult ParseAll(Stream stream)

    {

        using var workbook = new XLWorkbook(stream);

        var products = ParseProductsWorkbook(workbook);

        var comboLines = ParseComboWorkbook(workbook);

        return new ParseResult(products, comboLines);

    }

    /// <summary>File .xls (Excel 97-2003) — ClosedXML không đọc được.</summary>
    public static bool IsLegacyXls(byte[] head, string? fileName) =>
        string.Equals(Path.GetExtension(fileName ?? ""), ".xls", StringComparison.OrdinalIgnoreCase)
        || (head.Length >= 4 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0);

    static bool IsCsv(byte[] bytes, string? fileName)
    {
        var ext = Path.GetExtension(fileName ?? "").ToLowerInvariant();
        var isZip = bytes.Length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
        return !isZip && ext is ".csv" or ".tsv" or ".txt";
    }

    /// <summary>Đọc .xlsx hoặc CSV (CSV dựng thành một sheet tạm rồi đọc như Excel).</summary>
    public static ParseResult ParseAll(byte[] bytes, string? fileName)
    {
        if (!IsCsv(bytes, fileName))
        {
            using var ms = new MemoryStream(bytes);
            return ParseAll(ms);
        }
        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("HangHoa");
        var r = 1;
        foreach (var cells in ZKTecoADMS.Api.Services.PosMenuSheetReader.ReadCsvCells(bytes))
        {
            for (var c = 0; c < cells.Count; c++)
                if (cells[c].Length > 0) ws.Cell(r, c + 1).SetValue(cells[c]);
            r++;
        }
        return new ParseResult(ParseProductSheet(ws), []);
    }



    public static List<ImportRow> Parse(Stream stream) => ParseAll(stream).Products;



    static List<ImportRow> ParseProductsWorkbook(XLWorkbook workbook)
    {
        var rows = new List<ImportRow>();
        foreach (var ws in workbook.Worksheets)
        {
            var n = (ws.Name ?? "").Trim();
            if (n.Equals("Combo", StringComparison.OrdinalIgnoreCase) ||
                n.Equals("HuongDan", StringComparison.OrdinalIgnoreCase) ||
                n.StartsWith("Hướng", StringComparison.OrdinalIgnoreCase))
                continue;
            rows.AddRange(ParseProductSheet(ws));
        }
        return rows;
    }

    static List<ImportRow> ParseProductSheet(IXLWorksheet ws)
    {
        var headerRow = FindHeaderRow(ws);
        if (headerRow <= 0) return [];
        var cols = BuildColumnMap(ws, headerRow);
        if (cols.NameCol <= 0) return [];
        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        var rows = new List<ImportRow>();
        for (var r = DataStartRow(ws, headerRow); r <= lastRow; r++)
        {
            var name = Cell(ws, r, cols.NameCol);
            if (string.IsNullOrWhiteSpace(name)) continue;
            // Dòng tiêu đề lặp lại giữa bảng (in nhiều trang) → bỏ.
            if (IsNameHeader(Norm(name))) continue;
            var typeRaw = Cell(ws, r, cols.TypeCol);
            var productType = PosProductTypeRules.Parse(typeRaw);
            var directRaw = Cell(ws, r, cols.DirectSaleCol);
            var isDirect = string.IsNullOrWhiteSpace(directRaw) ||
                           directRaw.Equals("có", StringComparison.OrdinalIgnoreCase) ||
                           directRaw.Equals("yes", StringComparison.OrdinalIgnoreCase) ||
                           directRaw == "1" ||
                           directRaw.Equals("true", StringComparison.OrdinalIgnoreCase);
            rows.Add(new ImportRow(
                NullIfEmpty(Cell(ws, r, cols.CodeCol)),
                NullIfEmpty(Cell(ws, r, cols.BarcodeCol)),
                name.Trim(),
                NullIfEmpty(Cell(ws, r, cols.CategoryCol)),
                NullIfEmpty(Cell(ws, r, cols.BrandCol)),
                NullIfEmpty(Cell(ws, r, cols.SupplierCol)),
                NumCell(ws, r, cols.CostCol, price: true),
                NumCell(ws, r, cols.PriceCol, price: true),
                NumCell(ws, r, cols.StockCol),
                NumCell(ws, r, cols.MinStockCol),
                NumCell(ws, r, cols.MaxStockCol),
                string.IsNullOrWhiteSpace(Cell(ws, r, cols.UnitCol)) ? "Cái" : Cell(ws, r, cols.UnitCol).Trim(),
                productType,
                isDirect,
                string.IsNullOrWhiteSpace(Cell(ws, r, cols.WeightCol)) ? null : NumCell(ws, r, cols.WeightCol),
                NullIfEmpty(Cell(ws, r, cols.LocationCol)),
                NullIfEmpty(Cell(ws, r, cols.DescCol)),
                NullIfEmpty(Cell(ws, r, cols.PrinterCol)),
                ParseActive(Cell(ws, r, cols.IsActiveCol)),
                NullIfEmpty(ImageCell(ws, r, cols.ImageCol))));
        }
        return rows;
    }



    static List<ComboLineImportRow> ParseComboWorkbook(XLWorkbook workbook)

    {

        var ws = workbook.Worksheets.FirstOrDefault(w =>

            string.Equals(w.Name, "Combo", StringComparison.OrdinalIgnoreCase));

        if (ws == null) return [];



        var headerRow = FindComboHeaderRow(ws);

        if (headerRow <= 0) return [];



        var cols = BuildComboColumnMap(ws, headerRow);

        if (cols.ComboCodeCol <= 0 || cols.ComponentCodeCol <= 0) return [];



        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;

        var rows = new List<ComboLineImportRow>();



        for (var r = headerRow + 1; r <= lastRow; r++)

        {

            var comboCode = Cell(ws, r, cols.ComboCodeCol);

            var componentCode = Cell(ws, r, cols.ComponentCodeCol);

            if (string.IsNullOrWhiteSpace(comboCode) || string.IsNullOrWhiteSpace(componentCode))

                continue;



            var qty = cols.QtyCol > 0 ? NumCell(ws, r, cols.QtyCol) : 1m;

            if (qty <= 0) qty = 1;



            rows.Add(new ComboLineImportRow(

                comboCode.Trim(),

                componentCode.Trim(),

                qty));

        }



        return rows;

    }



    const int HeaderScanRows = 15;
    const int HeaderScanCols = 30;

    /// <summary>Cột tên hàng: «Tên hàng», «Tên món», «Tên sản phẩm», «Mặt hàng», «Sản phẩm», «Món», «Product», «Item»…</summary>
    internal static bool IsNameHeader(string h) =>
        h.Length > 0 &&
        (h.Contains("tenhang", StringComparison.Ordinal) ||
         h.Contains("tenmon", StringComparison.Ordinal) ||
         h.Contains("tensanpham", StringComparison.Ordinal) ||
         h.Contains("tenmathang", StringComparison.Ordinal) ||
         h.Contains("tendichvu", StringComparison.Ordinal) ||
         h.Contains("productname", StringComparison.Ordinal) ||
         h.Contains("itemname", StringComparison.Ordinal) ||
         h is "name" or "ten" or "tensp" or "mon" or "monan" or "mathang" or "sanpham" or "hanghoa" or "product"
             or "item" or "items" or "products" or "menu" or "dichvu");

    internal static bool IsPriceHeader(string h) =>
        h.Length > 0 && !IsCostHeader(h) &&
        (h.StartsWith("giaban", StringComparison.Ordinal) ||
         h.StartsWith("dongia", StringComparison.Ordinal) ||
         h.StartsWith("giale", StringComparison.Ordinal) ||
         h.StartsWith("gianiemyet", StringComparison.Ordinal) ||
         h.StartsWith("giatien", StringComparison.Ordinal) ||
         h is "gia" or "giavnd" or "giad" or "giadong" or "giak" or "gia1000d" ||
         h.Contains("saleprice", StringComparison.Ordinal) ||
         h.Contains("price", StringComparison.Ordinal));

    internal static bool IsCostHeader(string h) =>
        h.Contains("giavon", StringComparison.Ordinal) ||
        h.Contains("gianhap", StringComparison.Ordinal) ||
        h.Contains("giamua", StringComparison.Ordinal) ||
        h.Contains("cost", StringComparison.Ordinal);

    /// <summary>Dòng tiêu đề trong ~15 dòng đầu: có cột tên hàng (ưu tiên dòng có thêm cột giá / mã / đơn vị…).</summary>
    static int FindHeaderRow(IXLWorksheet ws)

    {

        var lastRow = Math.Min(ws.LastRowUsed()?.RowNumber() ?? HeaderScanRows, HeaderScanRows);
        var nameOnly = -1;

        for (var r = 1; r <= lastRow; r++)

        {

            var hasName = false;
            var others = 0;
            for (var c = 1; c <= HeaderScanCols; c++)

            {

                var h = Norm(HeaderText(ws, r, c));
                if (h.Length == 0) continue;
                if (IsNameHeader(h)) hasName = true;
                else if (KnownHeader(h)) others++;

            }

            if (hasName && others > 0) return r;
            if (hasName && nameOnly < 0) nameOnly = r;

        }

        return nameOnly;

    }

    static bool KnownHeader(string h)
    {
        var m = new ColumnMap();
        MapHeader(m, h, 1);
        return m.CodeCol > 0 || m.BarcodeCol > 0 || m.CategoryCol > 0 || m.CostCol > 0 || m.PriceCol > 0
               || m.StockCol > 0 || m.UnitCol > 0 || m.TypeCol > 0;
    }

    /// <summary>Chữ tiêu đề; ô nằm trong vùng gộp lấy chữ của ô đầu vùng.</summary>
    static string HeaderText(IXLWorksheet ws, int r, int c)
    {
        var cell = ws.Cell(r, c);
        var text = cell.GetFormattedString();
        if (string.IsNullOrWhiteSpace(text) && cell.IsMerged())
            text = cell.MergedRange()?.FirstCell().GetFormattedString() ?? "";
        return text;
    }

    /// <summary>Tiêu đề gộp dọc nhiều dòng → dữ liệu bắt đầu sau dòng cuối của vùng gộp.</summary>
    static int DataStartRow(IXLWorksheet ws, int headerRow)
    {
        var start = headerRow + 1;
        for (var c = 1; c <= HeaderScanCols; c++)
        {
            var cell = ws.Cell(headerRow, c);
            if (!cell.IsMerged()) continue;
            var last = cell.MergedRange()?.LastRow().RowNumber() ?? headerRow;
            if (last + 1 > start && last - headerRow <= 3) start = last + 1;
        }
        return start;
    }



    static int FindComboHeaderRow(IXLWorksheet ws)

    {

        var lastRow = Math.Min(ws.LastRowUsed()?.RowNumber() ?? 20, 20);

        for (var r = 1; r <= lastRow; r++)

        {

            for (var c = 1; c <= 10; c++)

            {

                var h = Norm(ws.Cell(r, c).GetFormattedString());

                if (h.Contains("macombo", StringComparison.Ordinal) ||

                    h.Contains("combo", StringComparison.Ordinal) && h.Contains("ma", StringComparison.Ordinal))

                    return r;

            }

        }

        return -1;

    }



    static ColumnMap BuildColumnMap(IXLWorksheet ws, int headerRow)

    {

        var map = new ColumnMap();

        for (var c = 1; c <= HeaderScanCols; c++)

        {

            var h = Norm(HeaderText(ws, headerRow, c));
            if (h.Length > 0) MapHeader(map, h, c);

        }

        return map;

    }

    /// <summary>Gán cột theo tiêu đề (đã chuẩn hóa bỏ dấu); cột đầu tiên khớp được giữ (không ghi đè).</summary>
    static void MapHeader(ColumnMap map, string h, int c)
    {
        static void Set(ref int field, int col)
        {
            if (field <= 0) field = col;
        }

        if (h.Contains("mahang", StringComparison.Ordinal) || h.Contains("masanpham", StringComparison.Ordinal) ||
            h.Contains("productcode", StringComparison.Ordinal) || h.Contains("itemcode", StringComparison.Ordinal) ||
            h is "code" or "ma" or "masp" or "mamon" or "mahh" or "sku" or "mahanghoa")
            Set(ref map.CodeCol, c);

        else if (h.Contains("mavach", StringComparison.Ordinal) || h.Contains("barcode", StringComparison.Ordinal) ||
                 h is "ean" or "upc" or "ean13")
            Set(ref map.BarcodeCol, c);

        else if (IsNameHeader(h)) Set(ref map.NameCol, c);

        else if (h.Contains("nhomhang", StringComparison.Ordinal) || h.Contains("nhommon", StringComparison.Ordinal) ||
                 h.Contains("category", StringComparison.Ordinal) || h.Contains("danhmuc", StringComparison.Ordinal) ||
                 h.Contains("nganhhang", StringComparison.Ordinal) ||
                 h is "nhom" or "nhomsp" or "nhomsanpham" or "group")
            Set(ref map.CategoryCol, c);

        else if (h.Contains("thuonghieu", StringComparison.Ordinal) || h.Contains("brand", StringComparison.Ordinal)) Set(ref map.BrandCol, c);

        else if (h.Contains("nhacungcap", StringComparison.Ordinal) || h.Contains("supplier", StringComparison.Ordinal) || h == "ncc")
            Set(ref map.SupplierCol, c);

        else if (IsCostHeader(h)) Set(ref map.CostCol, c);

        else if (IsPriceHeader(h)) Set(ref map.PriceCol, c);

        else if (h.Contains("tonthap", StringComparison.Ordinal) || h.Contains("minstock", StringComparison.Ordinal)) Set(ref map.MinStockCol, c);

        else if (h.Contains("toncao", StringComparison.Ordinal) || h.Contains("maxstock", StringComparison.Ordinal)) Set(ref map.MaxStockCol, c);

        else if (h.Contains("tonkho", StringComparison.Ordinal) || h.Contains("soluongton", StringComparison.Ordinal) ||
                 h.Contains("stock", StringComparison.Ordinal) || h.Contains("onhand", StringComparison.Ordinal) ||
                 h is "ton" or "slton" or "tondauky" or "soluong" or "sl" or "qty" or "quantity")
            Set(ref map.StockCol, c);

        else if (h.Contains("donvi", StringComparison.Ordinal) || h.Contains("unit", StringComparison.Ordinal) ||
                 h is "dvt" or "uom")
            Set(ref map.UnitCol, c);

        else if (h.Contains("loaihang", StringComparison.Ordinal) || h.Contains("type", StringComparison.Ordinal) ||
                 h is "kieuhang" or "loaisp")
            Set(ref map.TypeCol, c);

        else if (h.Contains("bantructiep", StringComparison.Ordinal) || h.Contains("direct", StringComparison.Ordinal)) Set(ref map.DirectSaleCol, c);

        else if (h.Contains("trongluong", StringComparison.Ordinal) || h.Contains("weight", StringComparison.Ordinal)) Set(ref map.WeightCol, c);

        else if (h.Contains("vitri", StringComparison.Ordinal) || h.Contains("location", StringComparison.Ordinal)) Set(ref map.LocationCol, c);

        else if (h.Contains("mota", StringComparison.Ordinal) || h.Contains("description", StringComparison.Ordinal) ||
                 h is "ghichu" or "note")
            Set(ref map.DescCol, c);

        else if (h.Contains("mayin", StringComparison.Ordinal) || h.Contains("printer", StringComparison.Ordinal)) Set(ref map.PrinterCol, c);
        else if (h.Contains("dangkd", StringComparison.Ordinal) ||
                 h.Contains("trangthai", StringComparison.Ordinal) ||
                 h.Contains("isactive", StringComparison.Ordinal) ||
                 h.Contains("active", StringComparison.Ordinal))
            Set(ref map.IsActiveCol, c);
        else if (h is "anh" or "hinh" or "photo" or "picture" ||
                 h.Contains("hinhanh") ||
                 h.Contains("linkanh") ||
                 h.Contains("linkhinh") ||
                 h.Contains("urlanh") ||
                 h.Contains("anhsp") ||
                 h.Contains("imageurl") ||
                 h.Contains("image"))
            Set(ref map.ImageCol, c);

    }



    static ComboColumnMap BuildComboColumnMap(IXLWorksheet ws, int headerRow)

    {

        var map = new ComboColumnMap();

        for (var c = 1; c <= 10; c++)

        {

            var h = Norm(ws.Cell(headerRow, c).GetFormattedString());

            if (h.Contains("macombo", StringComparison.Ordinal) ||

                (h.Contains("combo", StringComparison.Ordinal) && h.Contains("ma", StringComparison.Ordinal)))

                map.ComboCodeCol = c;

            else if (h.Contains("mathanhphan", StringComparison.Ordinal) ||

                     h.Contains("thanhphan", StringComparison.Ordinal) ||

                     h.Contains("component", StringComparison.Ordinal))

                map.ComponentCodeCol = c;

            else if (h.Contains("soluong", StringComparison.Ordinal) ||

                     h == "sl" ||

                     h.Contains("qty", StringComparison.Ordinal) ||

                     h.Contains("quantity", StringComparison.Ordinal))

                map.QtyCol = c;

        }

        return map;

    }



    static string Cell(IXLWorksheet ws, int row, int col) =>

        col > 0 ? ws.Cell(row, col).GetFormattedString().Trim() : "";

    static string ImageCell(IXLWorksheet ws, int row, int col)
    {
        if (col <= 0) return "";
        var cell = ws.Cell(row, col);
        var text = cell.GetFormattedString().Trim();
        if (cell.HasHyperlink)
        {
            var link = cell.GetHyperlink().ExternalAddress?.AbsoluteUri
                       ?? cell.GetHyperlink().InternalAddress ?? "";
            if (link.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                link.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                return NormalizeImageLink(link);
        }
        if (text.Length > 0) return NormalizeImageLink(text);
        return "";
    }

    /// <summary>Link public-serve / serve của hàng khác → path lưu DB. URL ngoài giữ nguyên.</summary>
    static string NormalizeImageLink(string raw)
    {
        var s = raw.Trim();
        if (s.Length == 0) return "";
        if (!s.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            && !s.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            return s.TrimStart('/');
        if (!Uri.TryCreate(s, UriKind.Absolute, out var uri)) return s;
        var host = uri.Host;
        if (host.Contains("drive.google.com", StringComparison.OrdinalIgnoreCase) ||
            host.Contains("docs.google.com", StringComparison.OrdinalIgnoreCase))
        {
            var segs = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            var fileIdx = Array.FindIndex(segs, x => x.Equals("d", StringComparison.OrdinalIgnoreCase));
            if (fileIdx >= 0 && fileIdx + 1 < segs.Length)
                return $"https://drive.google.com/uc?export=view&id={segs[fileIdx + 1]}";
            var id = "";
            var q = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries);
            foreach (var part in q)
            {
                var eq = part.IndexOf('=');
                if (eq <= 0) continue;
                if (part[..eq].Equals("id", StringComparison.OrdinalIgnoreCase))
                    id = Uri.UnescapeDataString(part[(eq + 1)..]);
            }
            if (id.Length > 0)
                return $"https://drive.google.com/uc?export=view&id={id}";
        }
        var query = uri.Query;
        if (query.Contains("path=", StringComparison.OrdinalIgnoreCase))
        {
            var parts = query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries);
            foreach (var part in parts)
            {
                var eq = part.IndexOf('=');
                if (eq <= 0) continue;
                if (!part[..eq].Equals("path", StringComparison.OrdinalIgnoreCase)) continue;
                var path = Uri.UnescapeDataString(part[(eq + 1)..]).Trim().TrimStart('/');
                if (path.Length > 0) return path;
            }
        }
        var abs = uri.AbsolutePath.TrimStart('/');
        if (abs.StartsWith("stores/", StringComparison.OrdinalIgnoreCase)
            || abs.StartsWith("uploads/", StringComparison.OrdinalIgnoreCase)
            || abs.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase))
            return abs;
        return s;
    }



    static string Norm(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return string.Empty;
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark)
                continue;
            sb.Append(ch);
        }

        return Regex.Replace(
            sb.ToString().Replace('đ', 'd').Replace('Đ', 'd'),
            @"[^a-z0-9]",
            "");
    }


    /// <summary>
    /// Số trong ô: ô kiểu số lấy thẳng giá trị (không qua chữ hiển thị «25.000 ₫»); ô chữ đọc kiểu Việt Nam
    /// («25.000» / «25,000đ» = 25000, «1,5» = 1.5, giá «35k» / «1tr2»).
    /// </summary>
    static decimal NumCell(IXLWorksheet ws, int row, int col, bool price = false)
    {
        if (col <= 0) return 0;
        var cell = ws.Cell(row, col);
        try
        {
            if (cell.DataType == XLDataType.Number && cell.TryGetValue<double>(out var d)
                && !double.IsNaN(d) && !double.IsInfinity(d) && Math.Abs(d) < 1e15)
                return (decimal)d;
        }
        catch (Exception)
        {
            // Công thức lỗi… → đọc theo chữ hiển thị.
        }
        return ParseDec(cell.GetFormattedString(), price);
    }

    internal static decimal ParseDec(string? s, bool price = false)
    {
        if (string.IsNullOrWhiteSpace(s)) return 0;
        var t = s.Trim();
        var negative = t.StartsWith('-') || (t.StartsWith('(') && t.EndsWith(')'));
        t = t.Trim('-', '(', ')', ' ');
        if (price)
        {
            var p = ZKTecoADMS.Api.Services.MenuPriceParser.Parse(t);
            if (p.Value is decimal pv && p.Flag is not ZKTecoADMS.Api.Services.MenuPriceFlag.Unreadable)
                return negative ? -pv : pv;
        }
        // Số lượng / trọng lượng: lấy số đầu chuỗi («10 cái», «1,5 kg»).
        var m = Regex.Match(t.Replace(" ", ""), @"^\d+(?:[.,]\d+)*");
        if (!m.Success) return 0;
        var v = ZKTecoADMS.Api.Services.MenuPriceParser.ParseNumber(m.Value) ?? 0;
        return negative ? -v : v;
    }

    static bool? ParseActive(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var t = s.Trim();
        if (t.Equals("có", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("yes", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("true", StringComparison.OrdinalIgnoreCase) ||
            t == "1" ||
            t.Equals("dangkd", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("hoatdong", StringComparison.OrdinalIgnoreCase))
            return true;
        if (t.Equals("không", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("khong", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("no", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("false", StringComparison.OrdinalIgnoreCase) ||
            t == "0" ||
            t.Equals("ngungkd", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("ngừng", StringComparison.OrdinalIgnoreCase))
            return false;
        return null;
    }



    static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    /// <summary>Kiểm tra dòng trước khi tạo / sửa hàng (không để entity dở dang vào DbContext). Null = hợp lệ.</summary>
    internal static string? ValidateRow(ImportRow row)
    {
        if (string.IsNullOrWhiteSpace(row.Name)) return "thiếu tên hàng";
        if (row.Name.Trim().Length > 500) return "tên hàng dài quá 500 ký tự";
        if (row.ProductCode?.Trim().Length > 50) return "mã hàng dài quá 50 ký tự";
        if (row.Barcode?.Trim().Length > 50) return "mã vạch dài quá 50 ký tự";
        if (row.BaseUnitName.Trim().Length > 100) return "đơn vị dài quá 100 ký tự";
        if (row.CategoryName?.Trim().Length > 200) return "tên nhóm hàng dài quá 200 ký tự";
        if (row.BasePrice < 0) return "giá bán âm";
        if (row.CostPrice < 0) return "giá vốn âm";
        if (row.BasePrice > 100_000_000_000m || row.CostPrice > 100_000_000_000m) return "giá quá lớn";
        if (row.MinStockQty < 0 || row.MaxStockQty < 0) return "tồn thấp / tồn cao âm";
        return null;
    }

    /// <summary>
    /// Hàng đã có ứng với dòng Excel: theo mã hàng, rồi mã vạch; dòng KHÔNG ghi mã hàng / mã vạch thì theo tên giống hệt
    /// (không phân biệt hoa thường / khoảng trắng, giữ dấu) — nhập lại file không có cột mã không nhân đôi hàng.
    /// </summary>
    internal static T? MatchExisting<T>(
        ImportRow row,
        IReadOnlyDictionary<string, T> byCode,
        IReadOnlyDictionary<string, T> byBarcode,
        IReadOnlyDictionary<string, T> byNameKey) where T : class
    {
        if (!string.IsNullOrWhiteSpace(row.ProductCode))
            return byCode.TryGetValue(row.ProductCode.Trim(), out var c) ? c
                : !string.IsNullOrWhiteSpace(row.Barcode) && byBarcode.TryGetValue(row.Barcode.Trim(), out var cb) ? cb
                : null;
        // Có mã vạch mà chưa có → hàng mới (cùng tên khác mã vạch là hàng khác, vd nhiều quy cách).
        if (!string.IsNullOrWhiteSpace(row.Barcode))
            return byBarcode.TryGetValue(row.Barcode.Trim(), out var b) ? b : null;
        return byNameKey.TryGetValue(ZKTecoADMS.Api.Services.PosProductNameMatch.ExactKey(row.Name), out var n) ? n : null;
    }

}


