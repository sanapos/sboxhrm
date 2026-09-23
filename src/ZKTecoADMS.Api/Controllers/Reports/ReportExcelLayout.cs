using ClosedXML.Excel;

namespace ZKTecoADMS.Api.Controllers;

internal static class ReportExcelLayout
{
    private static readonly XLColor HeaderFill = XLColor.FromHtml("#6366F1");
    private static readonly XLColor HeaderFont = XLColor.White;
    private static readonly XLColor TitleFill = XLColor.FromHtml("#EEF2FF");

    /// <summary>Writes title/meta rows. Returns header row index and first data row index.</summary>
    public static (int headerRow, int dataStartRow) ApplyMeta(
        IXLWorksheet ws,
        ReportExcelMeta meta,
        int columnCount)
    {
        var cols = Math.Max(columnCount, 1);
        var row = 1;

        ws.Cell(row, 1).Value = meta.Title;
        ws.Range(row, 1, row, cols).Merge();
        ws.Range(row, 1, row, cols).Style
            .Font.SetBold(true)
            .Font.SetFontSize(16)
            .Fill.SetBackgroundColor(TitleFill)
            .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);
        row++;

        if (!string.IsNullOrWhiteSpace(meta.StoreName))
        {
            ws.Cell(row, 1).Value = $"Cửa hàng: {meta.StoreName}";
            ws.Range(row, 1, row, cols).Merge();
            row++;
        }

        var periodFilter = new List<string>();
        if (!string.IsNullOrWhiteSpace(meta.PeriodLabel))
            periodFilter.Add($"Kỳ dữ liệu: {meta.PeriodLabel}");
        if (!string.IsNullOrWhiteSpace(meta.FilterLabel))
            periodFilter.Add($"Bộ lọc: {meta.FilterLabel}");
        if (periodFilter.Count > 0)
        {
            ws.Cell(row, 1).Value = string.Join("  |  ", periodFilter);
            ws.Range(row, 1, row, cols).Merge();
            row++;
        }

        var exportLine = $"Xuất lúc: {meta.ExportedAtVn:dd/MM/yyyy HH:mm}";
        if (!string.IsNullOrWhiteSpace(meta.ExportedBy))
            exportLine += $"  |  Người xuất: {meta.ExportedBy}";
        if (meta.DataRowCount.HasValue)
            exportLine += $"  |  Số dòng: {meta.DataRowCount.Value}";
        ws.Cell(row, 1).Value = exportLine;
        ws.Range(row, 1, row, cols).Merge();
        row++;

        foreach (var line in meta.SummaryLines)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            ws.Cell(row, 1).Value = line;
            ws.Range(row, 1, row, cols).Merge();
            row++;
        }

        row++; // blank spacer

        var headerRow = row;
        return (headerRow, headerRow + 1);
    }

    public static void ApplyHeaderRow(IXLWorksheet ws, int headerRow, IReadOnlyList<string> headers)
    {
        for (var i = 0; i < headers.Count; i++)
            ws.Cell(headerRow, i + 1).Value = headers[i];

        var range = ws.Range(headerRow, 1, headerRow, Math.Max(1, headers.Count));
        range.Style.Font.Bold = true;
        range.Style.Fill.BackgroundColor = HeaderFill;
        range.Style.Font.FontColor = HeaderFont;
        range.Style.Alignment.Horizontal = XLAlignmentHorizontalValues.Center;
        range.Style.Border.OutsideBorder = XLBorderStyleValues.Thin;
    }

    public static void FinishSheet(IXLWorksheet ws, int headerRow)
    {
        var lastCol = Math.Max(1, ws.LastColumnUsed()?.ColumnNumber() ?? 1);
        var lastRow = Math.Max(1, ws.LastRowUsed()?.RowNumber() ?? 1);
        for (var r = 1; r <= lastRow; r++)
        {
            for (var c = 1; c <= lastCol; c++)
            {
                var cell = ws.Cell(r, c);
                if (cell.DataType != XLDataType.Number) continue;
                var fmt = cell.Style.NumberFormat.Format ?? "";
                var bare = string.IsNullOrEmpty(fmt)
                    || fmt == "General"
                    || fmt == "0"
                    || fmt == "0.00";
                if (!bare) continue;
                var rounded = Math.Round(cell.GetDouble(), 1, MidpointRounding.AwayFromZero);
                if (Math.Abs(rounded - Math.Round(rounded)) < 0.0000001)
                {
                    cell.Value = (double)Math.Round(rounded);
                    cell.Style.NumberFormat.Format = "#,##0";
                }
                else
                {
                    cell.Value = rounded;
                    cell.Style.NumberFormat.Format = "#,##0.0";
                }
            }
        }

        var width = Math.Max(8d, 145d / lastCol);
        for (var c = 1; c <= lastCol; c++)
            ws.Column(c).Width = width;

        if (headerRow > 0 && headerRow <= lastRow)
        {
            ws.Row(headerRow).Height = 32;
            ws.Row(headerRow).Style.Alignment.WrapText = true;
            ws.SheetView.FreezeRows(headerRow);
        }

        ws.PageSetup.PaperSize = XLPaperSize.A4Paper;
        ws.PageSetup.PageOrientation = XLPageOrientation.Landscape;
        ws.PageSetup.PagesWide = 1;
        ws.PageSetup.PagesTall = 0;
        ws.PageSetup.CenterHorizontally = true;
    }
}
