using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Ngày lễ lặp hằng năm tạo năm trước vẫn có trong năm sau (bảng công / lương dùng danh sách này).</summary>
public class HolidayYearViewTests
{
    static Holiday H(string name, int y, int m, int d, bool recurring) =>
        new() { Id = Guid.NewGuid(), Name = name, Date = new DateTime(y, m, d), IsRecurring = recurring };

    [Fact]
    public void Recurring_holidays_from_earlier_years_are_projected()
    {
        var list = new[]
        {
            H("Tết Dương lịch", 2025, 1, 1, true),
            H("Quốc khánh", 2025, 9, 2, true),
            H("Tết Nguyên Đán 2025", 2025, 1, 29, false),   // không lặp → không sang 2026
            H("Mùng 1 Tết 2026", 2026, 2, 17, false),
            H("Quốc khánh (sửa 2026)", 2026, 9, 2, false),  // năm 2026 đã có ngày 2/9 → bỏ bản lặp
            H("29/02", 2024, 2, 29, true),                  // 2026 không nhuận → bỏ
        };
        var y2026 = HolidaysController.ForYear(list, 2026);
        Assert.Equal(new[] { "Tết Dương lịch", "Mùng 1 Tết 2026", "Quốc khánh (sửa 2026)" }, y2026.Select(d => d.Name));
        var ny = y2026[0];
        Assert.True(ny.IsProjected);
        Assert.Equal(2025, ny.OriginYear);
        Assert.Equal(new DateTime(2026, 1, 1), ny.Date);
        Assert.False(y2026[1].IsProjected);

        var y2028 = HolidaysController.ForYear(list, 2028);
        Assert.Contains(y2028, d => d.Name == "29/02" && d.Date == new DateTime(2028, 2, 29));
    }
}
