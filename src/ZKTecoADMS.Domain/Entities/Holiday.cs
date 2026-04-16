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
    public static List<Holiday> GetDefaultHolidays(int year = 2025)
    {
        return new List<Holiday>
        {
            // Tết Dương Lịch - New Year's Day
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Dương Lịch",
                Date = new DateTime(year, 1, 1),
                Description = "New Year's Day",
                IsRecurring = true,
                Region = "Vietnam",
                IsActive = true
            },

            // Tết Nguyên Đán - Lunar New Year (Tet Holiday) - Usually 5-7 days
            // Note: Lunar calendar dates vary by year, these are approximate for 2025
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Nguyên Đán (Giao Thừa)",
                Date = new DateTime(year, 1, 28),
                Description = "Lunar New Year's Eve",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Nguyên Đán (Mùng 1)",
                Date = new DateTime(year, 1, 29),
                Description = "Lunar New Year - Day 1",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Nguyên Đán (Mùng 2)",
                Date = new DateTime(year, 1, 30),
                Description = "Lunar New Year - Day 2",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Nguyên Đán (Mùng 3)",
                Date = new DateTime(year, 1, 31),
                Description = "Lunar New Year - Day 3",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Tết Nguyên Đán (Mùng 4)",
                Date = new DateTime(year, 2, 1),
                Description = "Lunar New Year - Day 4",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },

            // Giỗ Tổ Hùng Vương - Hung Kings' Commemoration Day
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Giỗ Tổ Hùng Vương",
                Date = new DateTime(year, 4, 18),
                Description = "Hung Kings' Commemoration Day (10th day of 3rd lunar month)",
                IsRecurring = false,
                Region = "Vietnam",
                IsActive = true
            },

            // Ngày Chiến Thắng - Reunification Day
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Ngày Chiến Thắng",
                Date = new DateTime(year, 4, 30),
                Description = "Reunification Day / Victory Day",
                IsRecurring = true,
                Region = "Vietnam",
                IsActive = true
            },

            // Ngày Quốc Tế Lao Động - International Labor Day
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Ngày Quốc Tế Lao Động",
                Date = new DateTime(year, 5, 1),
                Description = "International Labor Day",
                IsRecurring = true,
                Region = "Vietnam",
                IsActive = true
            },

            // Ngày Quốc Khánh - National Day
            new Holiday
            {
                Id = Guid.NewGuid(),
                Name = "Ngày Quốc Khánh",
                Date = new DateTime(year, 9, 2),
                Description = "National Day / Independence Day",
                IsRecurring = true,
                Region = "Vietnam",
                IsActive = true
            },

            // Additional observed holidays (optional)

        };
    }
}
