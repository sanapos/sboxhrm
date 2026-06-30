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
        string? Description);

    public static List<ImportRow> Parse(Stream stream)
    {
        using var workbook = new XLWorkbook(stream);
        var ws = workbook.Worksheets.FirstOrDefault(w =>
                     string.Equals(w.Name, "Hàng hóa", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(w.Name, "Hang hoa", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(w.Name, "Products", StringComparison.OrdinalIgnoreCase))
                 ?? workbook.Worksheets.First();

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
            var productType = typeRaw.Contains("dịch vụ", StringComparison.OrdinalIgnoreCase) ||
                              typeRaw.Contains("service", StringComparison.OrdinalIgnoreCase)
                ? PosProductType.Service
                : PosProductType.Goods;

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
                NullIfEmpty(Cell(ws, r, cols.DescCol))));
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
        }
        return map;
    }

    static string Cell(IXLWorksheet ws, int row, int col) =>
        col > 0 ? ws.Cell(row, col).GetFormattedString().Trim() : "";

    static string Norm(string s) =>
        Regex.Replace(Encoding.UTF8.GetString(Encoding.UTF8.GetBytes(
            s.Trim().ToLowerInvariant()
                .Replace("đ", "d").Replace("ă", "a").Replace("â", "a")
                .Replace("ê", "e").Replace("ô", "o").Replace("ơ", "o")
                .Replace("ư", "u"))), @"[^a-z0-9]", "");

    static decimal ParseDec(string s) =>
        decimal.TryParse(s.Replace(",", "").Replace(" ", ""), NumberStyles.Any, CultureInfo.InvariantCulture, out var v) ? v : 0;

    static decimal? ParseDecNullable(string s) =>
        string.IsNullOrWhiteSpace(s) ? null : ParseDec(s);

    static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
