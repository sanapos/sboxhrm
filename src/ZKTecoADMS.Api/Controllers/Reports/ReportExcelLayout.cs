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
        ws.Columns().AdjustToContents();
        ws.SheetView.FreezeRows(headerRow);
    }
}
