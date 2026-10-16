using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Thu luôn nợ cũ khi thanh toán: khách đưa vượt đơn → phần vượt thành phiếu thu nợ (trừ đơn nợ cũ, ghi số đơn);
/// lọc «Công nợ» ở danh sách đơn = đơn còn nợ.
/// </summary>
[Collection("pos-pg")]
public class PosCollectOldDebtTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosSalesController.CreateSaleDto Sale(Guid productId, decimal paid, Guid customerId, bool collect = false) =>
        new([new PosSalesController.SaleLineDto(productId, 1, null, 100000, null)], 0, paid, "Tiền mặt", null, customerId, null,
            Payments: paid > 0 ? [new PosSalesController.SalePaymentInputDto(paid, "Tiền mặt")] : null,
            CollectOldDebt: collect);

    [Fact]
    public async Task Khach_dua_them_tien_tru_vao_no_cu_va_ghi_so_don()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Bia", PosProductType.Goods, 100, 0, 100000);
        Guid customerId;
        await using (var db = Fx.NewDb())
        {
            var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KHNC1", Name = "Anh Năm", IsActive = true };
            db.PosCustomers.Add(c);
            await db.SaveChangesAsync();
            customerId = c.Id;
        }
        // Đơn 1: ghi nợ toàn bộ 100.000.
        string debtOrderNo;
        await using (var db = Fx.NewDb())
            debtOrderNo = Data(await Sales(db, store).CreateSale(Sale(p.Id, 0, customerId))).OrderNo;

        // Lọc «Công nợ»: thấy đơn nợ.
        await using (var db = Fx.NewDb())
            Assert.Equal(1, await CountAsync(Sales(db, store), "Công nợ"));

        // Đơn 2: 100.000, khách đưa 250.000, tick thu nợ cũ → trừ 100.000 nợ cũ, thối 50.000.
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(Sale(p.Id, 250000, customerId, collect: true)));

        await using (var db = Fx.NewDb())
        {
            var c = await db.PosCustomers.FirstAsync(x => x.Id == customerId);
            Assert.Equal(0m, c.CurrentDebt);
            var pay = await db.PosCustomerPayments.SingleAsync(x => x.CustomerId == customerId);
            Assert.Equal(100000m, pay.Amount);
            Assert.Contains("Thu nợ cũ kèm đơn", pay.Note);
            Assert.Contains($"Trừ nợ đơn: {debtOrderNo}", pay.Note);
            // Trừ đúng một đơn → phiếu gắn đơn đó (mở hóa đơn gốc từ phiếu thu).
            var debtOrder = await db.PosSaleOrders.FirstAsync(o => o.OrderNo == debtOrderNo);
            Assert.Equal(debtOrder.Id, pay.SaleOrderId);
            Assert.Equal(100000m, debtOrder.PaidAmount);
            // Đơn 2 chỉ ghi nhận đúng số phải trả (phần thối không vào đơn).
            var second = await db.PosSaleOrders.Where(o => o.CustomerId == customerId && o.OrderNo != debtOrderNo).SingleAsync();
            Assert.Equal(100000m, second.PaidAmount);
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(0, await CountAsync(Sales(db, store), "Công nợ"));

        // Lịch sử thanh toán của đơn nợ: chỉ dòng thu nợ 100.000 (không tính thêm «thu khi bán» = PaidAmount).
        await using (var db = Fx.NewDb())
        {
            var debtId = (await db.PosSaleOrders.FirstAsync(o => o.OrderNo == debtOrderNo)).Id;
            var pays = Data(await Sales(db, store).GetPayments(debtId));
            Assert.Equal(100000m, pays.Sum(x => x.Amount));
        }
    }

    [Fact]
    public async Task Khong_tick_thu_no_cu_thi_tien_du_la_tien_thoi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 100, 0, 100000);
        Guid customerId;
        await using (var db = Fx.NewDb())
        {
            var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KHNC2", Name = "Chị Sáu", IsActive = true };
            db.PosCustomers.Add(c);
            await db.SaveChangesAsync();
            customerId = c.Id;
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(Sale(p.Id, 0, customerId)));
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(Sale(p.Id, 250000, customerId)));
        await using (var db = Fx.NewDb())
        {
            Assert.Equal(100000m, (await db.PosCustomers.FirstAsync(x => x.Id == customerId)).CurrentDebt);
            Assert.False(await db.PosCustomerPayments.AnyAsync(x => x.CustomerId == customerId));
        }
    }

    static async Task<int> CountAsync(PosSalesController ctl, string paymentMethod)
    {
        var data = Data(await ctl.GetSales(null, "Completed", null, paymentMethod, null, null, null, null, null, null,
            null, null, null, null, null, null));
        using var doc = JsonDocument.Parse(JsonSerializer.Serialize(data));
        var root = doc.RootElement;
        foreach (var name in new[] { "total", "Total", "totalCount", "TotalCount" })
            if (root.TryGetProperty(name, out var t) && t.ValueKind == JsonValueKind.Number) return t.GetInt32();
        foreach (var name in new[] { "items", "Items" })
            if (root.TryGetProperty(name, out var arr)) return arr.GetArrayLength();
        throw new InvalidOperationException("Không đọc được số đơn: " + root);
    }
}
