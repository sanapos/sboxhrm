using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class Holiday : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    public DateTime Date { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    public bool IsRecurring { get; set; } = true;

    [MaxLength(50)]
    public string? Region { get; set; } = "Vietnam";

    /// <summary>
    /// Hệ số lương ngày lễ (VD: 3.0 = 300%)
    /// </summary>
    public double SalaryRate { get; set; } = 3.0;

    /// <summary>
    /// Danh mục: Ngày nghỉ chính thức, Ngày nghỉ bù, Ngày nghỉ hàng tuần, Ngày đặc biệt công ty
    /// </summary>
    [MaxLength(100)]
    public string Category { get; set; } = "Ngày nghỉ chính thức";

    /// <summary>
    /// Danh sách ID nhân viên áp dụng (JSON array). Null/empty = tất cả NV.
    /// </summary>
    public string? EmployeeIds { get; set; }
    
    /// <summary>
    /// Cửa hàng sở hữu ngày lễ này (null = áp dụng cho tất cả)
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}

public static class VietnamHolidays
{
    /// <summary>
    /// Ngày lễ chính thức của <paramref name="year"/>. Tết và Giỗ Tổ tính theo âm lịch của đúng năm đó
    /// (trước đây ghi cứng ngày 2025 cho mọi năm: Tết 2026 ra 28/01–01/02, Giỗ Tổ 18/04).
    /// </summary>
    public static List<Holiday> GetDefaultHolidays(int year)
    {
        var list = new List<Holiday>
        {
            Make("Tết Dương Lịch", new DateTime(year, 1, 1), "New Year's Day", recurring: true),
        };

        // 30 Tết thuộc tháng Chạp năm âm trước; tháng Chạp thiếu thì giao thừa là 29.
        var chap = year - 1;
        var eveDay = Math.Min(30, VietnamLunarCalendar.MonthDays(chap, 12));
        list.Add(Make("Tết Nguyên Đán (Giao Thừa)", VietnamLunarCalendar.ToSolar(chap, 12, eveDay), "Lunar New Year's Eve"));
        for (var d = 1; d <= 4; d++)
        {
            list.Add(Make($"Tết Nguyên Đán (Mùng {d})", VietnamLunarCalendar.ToSolar(year, 1, d), $"Lunar New Year - Day {d}"));
        }

        list.Add(Make("Giỗ Tổ Hùng Vương", VietnamLunarCalendar.ToSolar(year, 3, 10),
            "Hung Kings' Commemoration Day (10th day of 3rd lunar month)"));
        list.Add(Make("Ngày Chiến Thắng", new DateTime(year, 4, 30), "Reunification Day / Victory Day", recurring: true));
        list.Add(Make("Ngày Quốc Tế Lao Động", new DateTime(year, 5, 1), "International Labor Day", recurring: true));
        list.Add(Make("Ngày Quốc Khánh", new DateTime(year, 9, 2), "National Day / Independence Day", recurring: true));
        return list;
    }

    private static Holiday Make(string name, DateTime date, string description, bool recurring = false) => new()
    {
        Id = Guid.NewGuid(),
        Name = name,
        Date = date,
        Description = description,
        IsRecurring = recurring,
        Region = "Vietnam",
        IsActive = true,
    };
}

/// <summary>
/// Âm lịch Việt Nam 1900–2049 (cùng bảng với <c>flutter_client/lib/utils/lunar_converter.dart</c>, nút
/// «Thêm ngày lễ chuẩn» trong app) — chỉ chiều âm → dương, đủ cho ngày lễ.
/// </summary>
public static class VietnamLunarCalendar
{
    private static readonly int[] Info =
    {
        0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
        0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
        0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
        0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
        0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
        0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
        0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
        0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
        0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
        0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0,
        0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
        0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
        0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
        0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d25f, 0x0d520, 0x0dd45,
        0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
    };

    private const int BaseYear = 1900;
    private static readonly DateTime BaseDate = new(1900, 1, 31);

    private static bool InRange(int year) => year >= BaseYear && year - BaseYear < Info.Length;

    private static int LeapMonth(int year) => InRange(year) ? Info[year - BaseYear] & 0xf : 0;

    private static int LeapDays(int year) =>
        LeapMonth(year) != 0 ? ((Info[year - BaseYear] & 0x10000) != 0 ? 30 : 29) : 0;

    /// <summary>Số ngày của tháng âm (thường, không nhuận): 29 hoặc 30.</summary>
    public static int MonthDays(int year, int month) =>
        InRange(year) && (Info[year - BaseYear] & (0x10000 >> month)) != 0 ? 30 : 29;

    private static int YearDays(int year)
    {
        var sum = 348;
        if (!InRange(year)) return sum;
        for (var i = 0x8000; i > 0x8; i >>= 1)
            sum += (Info[year - BaseYear] & i) != 0 ? 1 : 0;
        return sum + LeapDays(year);
    }

    /// <summary>Ngày dương lịch của ngày âm <paramref name="day"/>/<paramref name="month"/> năm âm <paramref name="year"/>.</summary>
    public static DateTime ToSolar(int year, int month, int day)
    {
        if (!InRange(year)) return new DateTime(year, month, Math.Min(day, 28));
        var offset = 0;
        for (var y = BaseYear; y < year; y++) offset += YearDays(y);
        var leap = LeapMonth(year);
        for (var m = 1; m < month; m++)
        {
            offset += MonthDays(year, m);
            if (leap > 0 && m == leap) offset += LeapDays(year);
        }
        return BaseDate.AddDays(offset + day - 1);
    }
}
