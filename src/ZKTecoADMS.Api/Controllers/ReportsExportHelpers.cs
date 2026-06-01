using System.Text;
using ClosedXML.Excel;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Shared labels and formatting for attendance report exports.</summary>
internal static class ReportLabels
{
    public const string Absent = "Vắng mặt";
    public const string AbsentUnexcused = "Vắng không phép";
    public const string OnTime = "Đúng giờ";
    public const string Late = "Đi muộn";
    public const string Early = "Về sớm";
    public const string LateAndEarly = "Đi muộn + Về sớm";
    public const string Leave = "Nghỉ phép";
    public const string Holiday = "Nghỉ lễ";
    public const string DayOff = "Ngày nghỉ";
    /// <summary>Legacy label when schedule cannot be inferred (prefer <see cref="NoSalaryProfile"/>).</summary>
    public const string NoSchedule = "Không có lịch";
    public const string NoSalaryProfile = "Chưa thiết lập lương";
    public const string SalarySetupReminder =
        "Chưa gán hồ sơ lương. Vui lòng thiết lập tại Cài đặt > Hồ sơ lương (HRM).";

    public static string? ResolveAttendanceNote(string status, string? punchNote)
    {
        if (status == NoSalaryProfile)
        {
            return string.IsNullOrWhiteSpace(punchNote)
                ? SalarySetupReminder
                : $"{SalarySetupReminder} | {punchNote}";
        }

        return punchNote;
    }
}

internal static class ReportsExportHelpers
{
    public static DateTime ToVietnamTime(DateTime dt)
    {
        return dt.Kind switch
        {
            DateTimeKind.Utc => dt.AddHours(7),
            DateTimeKind.Local => dt.ToUniversalTime().AddHours(7),
            _ => DateTime.SpecifyKind(dt, DateTimeKind.Utc).AddHours(7),
        };
    }

    public static string FormatVnTime(DateTime? value)
        => value == null ? "-" : ToVietnamTime(value.Value).ToString("HH:mm");

    public static int WorkedMinutesVn(DateTime? checkIn, DateTime? checkOut)
    {
        if (checkIn == null || checkOut == null) return 0;
        var a = ToVietnamTime(checkIn.Value);
        var b = ToVietnamTime(checkOut.Value);
        return (int)Math.Max(0, (b - a).TotalMinutes);
    }

    public static string CsvEscape(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "\"\"";
        var v = value.Replace("\"", "\"\"");
        return $"\"{v}\"";
    }

    public static void ApplyDailyStatusFill(IXLCell cell, string? status)
    {
        var s = status ?? string.Empty;
        if (s.Contains("Vắng", StringComparison.OrdinalIgnoreCase))
        {
            cell.Style.Fill.SetBackgroundColor(XLColor.LightPink);
            return;
        }
        if (s.Contains("Nghỉ", StringComparison.OrdinalIgnoreCase)
            || s.Contains("Ngày nghỉ", StringComparison.OrdinalIgnoreCase))
        {
            cell.Style.Fill.SetBackgroundColor(XLColor.LightYellow);
            return;
        }
        if (s.Contains("muộn", StringComparison.OrdinalIgnoreCase)
            || s.Contains("sớm", StringComparison.OrdinalIgnoreCase))
        {
            cell.Style.Fill.SetBackgroundColor(XLColor.LightSalmon);
            return;
        }
        if (s.Contains("Đúng giờ", StringComparison.OrdinalIgnoreCase))
        {
            cell.Style.Fill.SetBackgroundColor(XLColor.LightGreen);
        }
    }

    public static HashSet<string>? ParseEmployeeCodes(string? employeeCodes)
    {
        if (string.IsNullOrWhiteSpace(employeeCodes)) return null;
        return employeeCodes
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(c => c.Length > 0)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }
}
