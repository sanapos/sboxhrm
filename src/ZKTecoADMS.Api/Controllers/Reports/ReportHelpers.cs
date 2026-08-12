using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Shared helpers for report controllers: VN time math, Excel export builders.
/// Kept internal (no DI) so controllers stay slim and testable.
/// </summary>
internal static class ReportHelpers
{
    /// <summary>VN timezone offset (UTC+7).</summary>
    public const int VnOffsetHours = VnTimeHelper.OffsetHours;

    public static DateTime NowVn() => VnTimeHelper.NowVn();

    /// <summary>UTC-stored timestamps → VN (CreatedAt, giao dịch UTC, …).</summary>
    public static DateTime ToVn(DateTime utc) => VnTimeHelper.UtcToVn(utc);

    /// <summary>Chấm công máy/mobile — giá trị DB đã là giờ tường VN.</summary>
    public static DateTime AttendanceToVn(DateTime punch) => VnTimeHelper.AttendanceWallClock(punch);

    /// <summary>VN-day window for attendance wall-clock columns [queryStart, queryEnd).</summary>
    public static (DateTime dateLocal, DateTime queryStart, DateTime queryEnd) AttendanceDayRange(DateTime? date)
    {
        var (local, start, end) = VnTimeHelper.AttendanceDayRange(date);
        return (local, start, end);
    }

    /// <summary>VN-month window for attendance queries.</summary>
    public static (DateTime startLocal, DateTime endLocal, DateTime queryStart, DateTime queryEnd)
        AttendanceMonthRange(int year, int month)
    {
        var (start, end, qs, qe) = VnTimeHelper.AttendanceMonthRange(year, month);
        return (start, end, qs, qe);
    }

    /// <summary>Arbitrary VN date range for attendance queries.</summary>
    public static (DateTime fromLocal, DateTime toLocal, DateTime queryStart, DateTime queryEnd)
        AttendanceVnRange(DateTime? from, DateTime? to)
    {
        var (f, t, qs, qe) = VnTimeHelper.AttendanceDateRange(from, to);
        return (f, t, qs, qe);
    }

    /// <summary>VN-day UTC window: [utcStart, utcEnd) for UTC-stored columns (audit, …).</summary>
    public static (DateTime dateLocal, DateTime utcStart, DateTime utcEnd) VnDayRange(DateTime? date)
    {
        var local = (date ?? NowVn()).Date;
        var utcStart = local.AddHours(-VnOffsetHours);
        return (local, utcStart, utcStart.AddDays(1));
    }

    /// <summary>VN-month UTC window: [utcStart, utcEnd) for the given VN year/month.</summary>
    public static (DateTime startLocal, DateTime endLocal, DateTime utcStart, DateTime utcEnd) VnMonthRange(int year, int month)
    {
        var start = new DateTime(year, month, 1);
        var endExclusive = start.AddMonths(1);
        var utcStart = start.AddHours(-VnOffsetHours);
        var utcEnd = endExclusive.AddHours(-VnOffsetHours);
        return (start, endExclusive.AddDays(-1), utcStart, utcEnd);
    }

    /// <summary>Range helper for arbitrary [from, to] VN dates (inclusive).</summary>
    public static (DateTime fromLocal, DateTime toLocal, DateTime utcStart, DateTime utcEnd) VnRange(DateTime? from, DateTime? to)
    {
        var now = NowVn().Date;
        var f = (from ?? now.AddDays(-30)).Date;
        var t = (to ?? now).Date;
        if (t < f) t = f;
        var utcStart = f.AddHours(-VnOffsetHours);
        var utcEnd = t.AddDays(1).AddHours(-VnOffsetHours);
        return (f, t, utcStart, utcEnd);
    }

    /// <summary>
    /// Báo cáo POS: ngày lịch VN + giờ cắt qua đêm → cửa sổ UTC wall cho SaleDate/CreatedAt.
    /// </summary>
    public static (DateTime fromUtc, DateTime toUtcExclusive, DateTime fromVn, DateTime toVnExclusive)
        PosBusinessRange(DateTime? from, DateTime? to, int dayStartHour = 0,
            DateTime? defaultFrom = null, DateTime? defaultTo = null)
        => VnTimeHelper.ResolvePosBusinessRange(from, to, dayStartHour, defaultFrom, defaultTo);

    /// <summary>Count working days in VN range excluding weekends + given holiday dates (local).</summary>
    public static int CountWorkingDays(DateTime fromLocal, DateTime toLocal, HashSet<DateTime> holidays)
    {
        var count = 0;
        for (var d = fromLocal.Date; d <= toLocal.Date; d = d.AddDays(1))
        {
            if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday) continue;
            if (holidays.Contains(d)) continue;
            count++;
        }
        return count;
    }

    public static string FullName(string? lastName, string? firstName)
        => $"{lastName} {firstName}".Trim();

    // ── Excel ──────────────────────────────────────────────────────────────

    /// <summary>
    /// Build a single-sheet Excel file with standard title / store / export metadata.
    /// <paramref name="writeRows"/> receives the worksheet and the first data row index.
    /// </summary>
    public static FileContentResult ExcelFile(
        string sheetName,
        IEnumerable<string> headers,
        Action<IXLWorksheet, int> writeRows,
        string fileName,
        ClaimsPrincipal? user = null,
        string? reportTitle = null,
        string? periodLabel = null,
        string? filterLabel = null,
        IReadOnlyList<string>? summaryLines = null,
        int? dataRowCount = null)
    {
        var hdrs = headers.ToList();
        var meta = ReportExcelMeta.FromUser(
            user,
            reportTitle ?? sheetName,
            periodLabel,
            filterLabel,
            summaryLines,
            dataRowCount);

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add(Trim(sheetName, 31));

        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, hdrs.Count);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, hdrs);
        writeRows(ws, dataStartRow);
        ReportExcelLayout.FinishSheet(ws, headerRow);

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return new FileContentResult(ms.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        {
            FileDownloadName = fileName
        };
    }

    private static string Trim(string s, int max) => s.Length <= max ? s : s[..max];

    /// <summary>Set a VN local date cell with standard format dd/MM/yyyy.</summary>
    public static IXLCell DateCell(IXLCell c, DateTime? date)
    {
        if (date.HasValue)
        {
            c.Value = date.Value;
            c.Style.DateFormat.Format = "dd/MM/yyyy";
        }
        return c;
    }

    public static IXLCell TimeCell(IXLCell c, DateTime? date)
    {
        if (date.HasValue)
        {
            c.Value = date.Value;
            c.Style.DateFormat.Format = "dd/MM/yyyy HH:mm";
        }
        return c;
    }

    public static IXLCell MoneyCell(IXLCell c, decimal? amount)
    {
        if (amount.HasValue)
        {
            c.Value = amount.Value;
            c.Style.NumberFormat.Format = "#,##0";
        }
        return c;
    }

    public static IXLCell PercentCell(IXLCell c, double? value)
    {
        if (value.HasValue)
        {
            c.Value = value.Value / 100.0;
            c.Style.NumberFormat.Format = "0.00%";
        }
        return c;
    }
}
