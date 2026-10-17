using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.DTOs.Hkd;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Thuế hộ kinh doanh: ngưỡng 1 tỷ / 3 tỷ, sổ ghi đủ tiền khách trả, doanh thu theo hóa đơn đã xuất hoặc tất cả.</summary>
[Collection("pos-pg")]
public class HkdTaxOverviewTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Theory]
    [InlineData(0, 1)]
    [InlineData(999_999_999, 1)]
    [InlineData(1_000_000_000, 2)]
    [InlineData(3_000_000_000, 2)]
    [InlineData(3_000_000_001, 3)]
    public void Nhom_theo_doanh_thu_nam_nguong_1_ty_va_3_ty(long revenue, int group) =>
        Assert.Equal(group, HkdBooksController.GroupForRevenue(revenue));

    [Fact]
    public void Tien_de_doc() =>
        Assert.Equal(["1,5 tỷ", "640 triệu", "850.000 đ"],
            new[] { HkdBooksController.Money(1_500_000_000m), HkdBooksController.Money(640_000_000m), HkdBooksController.Money(850_000m) });

    static PosSaleOrder Order(Guid store, string no, DateTime saleUtc, decimal total, decimal vat = 0,
        decimal surcharge = 0, decimal delivery = 0, string? invoiceNo = null) => new()
    {
        Id = Guid.NewGuid(), StoreId = store, OrderNo = no, SaleDate = saleUtc, CreatedAt = saleUtc,
        Status = PosSaleOrderStatus.Completed, IsActive = true, SubTotal = total, Total = total, VatAmount = vat,
        SurchargeAmount = surcharge, DeliveryFee = delivery, PaidAmount = total + vat + surcharge + delivery,
        EInvoiceStatus = invoiceNo == null ? "None" : "Issued", EInvoiceSeries = invoiceNo == null ? null : "1C26TAA",
        EInvoiceNo = invoiceNo, EInvoiceIssuedAt = invoiceNo == null ? null : saleUtc.AddMinutes(5),
    };

    static HkdBookPreviewDto Preview(IActionResult r) =>
        ((AppResponse<HkdBookPreviewDto>)((OkObjectResult)r).Value!).Data!;

    static decimal Revenue(HkdBookPreviewDto d) =>
        d.Summary.First(x => x.Label.Contains("doanh thu", StringComparison.OrdinalIgnoreCase)).Value;

    [Fact]
    public async Task So_doanh_thu_cong_du_VAT_phu_thu_phi_giao_hang_va_loc_theo_hoa_don()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var now = DateTime.UtcNow;
        await using (var db = Fx.NewDb())
        {
            db.PosSaleOrders.AddRange(
                Order(store, "DH001", now.AddMinutes(-30), 100_000, vat: 8_000, surcharge: 5_000, delivery: 15_000, invoiceNo: "0000123"),
                Order(store, "DH002", now.AddMinutes(-20), 50_000));
            await db.SaveChangesAsync();
        }
        var today = now.AddHours(7).Date;
        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new HkdBooksController(db2), store);

        // Trước đây sổ chỉ cộng tiền hàng (150.000) — sót VAT, phụ thu, phí giao hàng khách đã trả.
        var all = Preview(await ctl.PreviewBook("S1a", today, today));
        Assert.Equal(178_000m, Revenue(all));
        Assert.Equal(2, all.RowCount);

        var inv = Preview(await ctl.PreviewBook("S2a", today, today, "invoice"));
        Assert.Equal(128_000m, Revenue(inv));
        Assert.Equal(1, inv.RowCount);
        Assert.Equal("1C26TAA0000123", inv.Rows[0]["code"]);
        Assert.Contains("hóa đơn", inv.PeriodLabel);
    }

    [Fact]
    public async Task Tong_quan_bao_khai_thap_hon_doanh_thu_that_va_thieu_ty_le()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await using (var db = Fx.NewDb())
        {
            db.AppSettings.Add(new AppSettings { Id = Guid.NewGuid(), StoreId = store, Key = "hkd_tax_group", Value = "1", Group = "Hkd" });
            db.PosSaleOrders.AddRange(
                // 15/03/2025 giờ VN: 1 tỷ đã xuất hóa đơn (900tr hàng + 100tr VAT).
                Order(store, "DH101", new DateTime(2025, 3, 15, 3, 0, 0), 900_000_000, vat: 100_000_000, invoiceNo: "0000001"),
                Order(store, "DH102", new DateTime(2025, 8, 10, 3, 0, 0), 500_000_000),
                // 31/12/2025 18:00 UTC = 01:00 ngày 01/01/2026 giờ VN → không thuộc năm 2025.
                Order(store, "DH103", new DateTime(2025, 12, 31, 18, 0, 0), 700_000_000));
            await db.SaveChangesAsync();
        }
        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new HkdBooksController(db2), store);
        var d = JsonSerializer.SerializeToElement(
            ((AppResponse<object>)((OkObjectResult)await ctl.Overview(2025)).Value!).Data!,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        Assert.Equal(1_500_000_000m, d.GetProperty("ytd").GetDecimal());
        Assert.Equal(1_000_000_000m, d.GetProperty("ytdInvoiced").GetDecimal());
        Assert.Equal(1_000_000_000m, d.GetProperty("months")[2].GetProperty("all").GetDecimal());
        Assert.Equal(0m, d.GetProperty("months")[11].GetProperty("all").GetDecimal());
        Assert.Equal(1, d.GetProperty("configuredGroup").GetInt32());
        Assert.Equal(2, d.GetProperty("suggestedGroup").GetInt32());
        Assert.Equal("red", d.GetProperty("verdict").GetString());
        var titles = d.GetProperty("actions").EnumerateArray().Select(a => a.GetProperty("title").GetString()!).ToList();
        Assert.Contains(titles, t => t.Contains("hồ sơ đang khai nhóm 1"));
        Assert.Contains(titles, t => t.Contains("Chưa nhập tỷ lệ"));
        Assert.Contains(titles, t => t.Contains("chưa xuất hóa đơn"));

        // Theo hóa đơn đã xuất: chỉ 1 tỷ — vẫn nhóm 2 (đủ 1 tỷ).
        var inv = JsonSerializer.SerializeToElement(
            ((AppResponse<object>)((OkObjectResult)await ctl.Overview(2025, "invoice")).Value!).Data!,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Equal(1_000_000_000m, inv.GetProperty("ytd").GetDecimal());
        Assert.Equal(2, inv.GetProperty("suggestedGroup").GetInt32());
    }
}
