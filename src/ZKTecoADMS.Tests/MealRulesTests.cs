using Xunit;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Chọn buổi ăn theo giờ chấm + giá suất chốt.</summary>
public class MealRulesTests
{
    static MealSession S(string name, int h1, int m1, int h2, int m2, decimal price = 25_000) =>
        new() { Id = Guid.NewGuid(), Name = name, StartTime = new TimeSpan(h1, m1, 0), EndTime = new TimeSpan(h2, m2, 0), PricePerMeal = price };

    static readonly MealSession Sang = S("Sáng", 6, 30, 7, 30);
    static readonly MealSession Trua = S("Trưa", 11, 0, 12, 30);
    static readonly MealSession Dem = S("Đêm", 23, 30, 0, 30);
    static readonly MealSession[] All = [Sang, Trua, Dem];

    [Theory]
    [InlineData(11, 45, "Trưa")]
    [InlineData(10, 40, "Trưa")]   // sớm 20 phút — trong dung sai
    [InlineData(12, 55, "Trưa")]   // trễ 25 phút
    [InlineData(6, 10, "Sáng")]
    [InlineData(0, 10, "Đêm")]     // buổi qua nửa đêm
    [InlineData(23, 50, "Đêm")]
    public void Chon_buoi_theo_gio(int h, int m, string expected) =>
        Assert.Equal(expected, MealRules.MatchSession(All, new TimeSpan(h, m, 0))?.Name);

    [Theory]
    [InlineData(3, 0)]
    [InlineData(9, 30)]
    [InlineData(16, 0)]
    public void Ngoai_moi_khung_gio_khong_gan_buoi(int h, int m) =>
        Assert.Null(MealRules.MatchSession(All, new TimeSpan(h, m, 0)));

    [Fact]
    public void Gia_chot_luc_cham_uu_tien_hon_gia_buoi_hien_tai()
    {
        var prices = new Dictionary<Guid, decimal> { [Trua.Id] = 30_000 };
        Assert.Equal(25_000m, MealRules.PriceOf(new MealRecord { MealSessionId = Trua.Id, Price = 25_000 }, prices));
        Assert.Equal(30_000m, MealRules.PriceOf(new MealRecord { MealSessionId = Trua.Id }, prices));
        Assert.Equal(0m, MealRules.PriceOf(new MealRecord { MealSessionId = Guid.NewGuid() }, prices));
    }
}
