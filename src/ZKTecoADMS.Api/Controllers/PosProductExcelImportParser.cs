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
        bool? IsActive = null);



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
        for (var r = headerRow + 1; r <= lastRow; r++)
        {
            var name = Cell(ws, r, cols.NameCol);
            if (string.IsNullOrWhiteSpace(name)) continue;
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
                ParseDec(Cell(ws, r, cols.CostCol)),
                ParseDec(Cell(ws, r, cols.PriceCol)),
                ParseDec(Cell(ws, r, cols.StockCol)),
                ParseDec(Cell(ws, r, cols.MinStockCol)),
                ParseDec(Cell(ws, r, cols.MaxStockCol)),
                string.IsNullOrWhiteSpace(Cell(ws, r, cols.UnitCol)) ? "Cái" : Cell(ws, r, cols.UnitCol).Trim(),
                productType,
                isDirect,
                ParseDecNullable(Cell(ws, r, cols.WeightCol)),
                NullIfEmpty(Cell(ws, r, cols.LocationCol)),
                NullIfEmpty(Cell(ws, r, cols.DescCol)),
                NullIfEmpty(Cell(ws, r, cols.PrinterCol)),
                ParseActive(Cell(ws, r, cols.IsActiveCol))));
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



            var qty = cols.QtyCol > 0 ? ParseDec(Cell(ws, r, cols.QtyCol)) : 1m;

            if (qty <= 0) qty = 1;



            rows.Add(new ComboLineImportRow(

                comboCode.Trim(),

                componentCode.Trim(),

                qty));

        }



        return rows;

    }



    static int FindHeaderRow(IXLWorksheet ws)

    {

        var lastRow = Math.Min(ws.LastRowUsed()?.RowNumber() ?? 30, 30);

        for (var r = 1; r <= lastRow; r++)

        {

            for (var c = 1; c <= 20; c++)

            {

                var h = Norm(ws.Cell(r, c).GetFormattedString());

                if (h.Contains("tenhang", StringComparison.Ordinal) ||

                    h.Contains("tên hàng", StringComparison.Ordinal) ||

                    h == "name")

                    return r;

            }

        }

        return -1;

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

        for (var c = 1; c <= 25; c++)

        {

            var h = Norm(ws.Cell(headerRow, c).GetFormattedString());

            if (h.Contains("mahang", StringComparison.Ordinal) || h == "code") map.CodeCol = c;

            else if (h.Contains("mavach", StringComparison.Ordinal) || h.Contains("barcode", StringComparison.Ordinal)) map.BarcodeCol = c;

            else if (h.Contains("tenhang", StringComparison.Ordinal) || h == "name") map.NameCol = c;

            else if (h.Contains("nhomhang", StringComparison.Ordinal) || h.Contains("category", StringComparison.Ordinal)) map.CategoryCol = c;

            else if (h.Contains("thuonghieu", StringComparison.Ordinal) || h.Contains("brand", StringComparison.Ordinal)) map.BrandCol = c;

            else if (h.Contains("nhacungcap", StringComparison.Ordinal) || h.Contains("supplier", StringComparison.Ordinal)) map.SupplierCol = c;

            else if (h.Contains("giavon", StringComparison.Ordinal) || h.Contains("cost", StringComparison.Ordinal)) map.CostCol = c;

            else if (h.Contains("giaban", StringComparison.Ordinal) || h.Contains("price", StringComparison.Ordinal)) map.PriceCol = c;

            else if (h.Contains("tonkho", StringComparison.Ordinal) || h.Contains("stock", StringComparison.Ordinal)) map.StockCol = c;

            else if (h.Contains("tonthap", StringComparison.Ordinal) || h.Contains("minstock", StringComparison.Ordinal)) map.MinStockCol = c;

            else if (h.Contains("toncao", StringComparison.Ordinal) || h.Contains("maxstock", StringComparison.Ordinal)) map.MaxStockCol = c;

            else if (h.Contains("donvi", StringComparison.Ordinal) || h.Contains("unit", StringComparison.Ordinal)) map.UnitCol = c;

            else if (h.Contains("loaihang", StringComparison.Ordinal) || h.Contains("type", StringComparison.Ordinal)) map.TypeCol = c;

            else if (h.Contains("bantructiep", StringComparison.Ordinal) || h.Contains("direct", StringComparison.Ordinal)) map.DirectSaleCol = c;

            else if (h.Contains("trongluong", StringComparison.Ordinal) || h.Contains("weight", StringComparison.Ordinal)) map.WeightCol = c;

            else if (h.Contains("vitri", StringComparison.Ordinal) || h.Contains("location", StringComparison.Ordinal)) map.LocationCol = c;

            else if (h.Contains("mota", StringComparison.Ordinal) || h.Contains("description", StringComparison.Ordinal)) map.DescCol = c;

            else if (h.Contains("mayin", StringComparison.Ordinal) || h.Contains("printer", StringComparison.Ordinal)) map.PrinterCol = c;
            else if (h.Contains("dangkd", StringComparison.Ordinal) ||
                     h.Contains("trangthai", StringComparison.Ordinal) ||
                     h.Contains("isactive", StringComparison.Ordinal) ||
                     h.Contains("active", StringComparison.Ordinal))
                map.IsActiveCol = c;

        }

        return map;

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


    static decimal ParseDec(string s) =>

        decimal.TryParse(s.Replace(",", "").Replace(" ", ""), NumberStyles.Any, CultureInfo.InvariantCulture, out var v) ? v : 0;



    static decimal? ParseDecNullable(string s) =>
        string.IsNullOrWhiteSpace(s) ? null : ParseDec(s);

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

}


