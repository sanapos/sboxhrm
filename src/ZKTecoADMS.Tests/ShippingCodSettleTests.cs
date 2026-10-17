using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Đối soát COD: ghi sổ quỹ + đã trả của đơn + công nợ khách; cước hoàn trong báo cáo.</summary>
public class ShippingCodSettleTests
{
    readonly Guid _store = Guid.NewGuid();
    readonly Guid _user = Guid.NewGuid();

    ZKTecoDbContext NewDb(string name) =>
        new(new DbContextOptionsBuilder<ZKTecoDbContext>().UseInMemoryDatabase(name).Options);

    static PosShippingService Svc(ZKTecoDbContext db) => new(db, [], NullLogger<PosShippingService>.Instance);

    PosSaleOrder Order(decimal total, decimal cod, decimal fee = 0, string payer = "shop", Guid? customerId = null,
        string status = ShipmentStatus.Delivered) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, OrderNo = "HD" + Guid.NewGuid().ToString("N")[..6],
        Status = PosSaleOrderStatus.Completed, Total = total, DeliveryFee = fee, PaidAmount = 0,
        IsDelivery = true, DeliveryCarrierCode = "Ghn", DeliveryStatusCode = status,
        DeliveryCodAmount = cod, DeliveryFeePayer = payer, CustomerId = customerId, CustomerName = "Khách",
    };

    [Fact]
    public async Task Khach_le_doi_soat_ghi_phieu_thu_va_cap_nhat_da_tra()
    {
        var name = Guid.NewGuid().ToString();
        var o = Order(100000, 100000);
        await using (var db = NewDb(name)) { db.PosSaleOrders.Add(o); await db.SaveChangesAsync(); }

        await using (var db = NewDb(name))
        {
            var (n, errors) = await Svc(db).SettleCodAsync(_store, [o.Id], true, _user, "u@x", default);
            Assert.Equal(1, n);
            Assert.Empty(errors);
        }
        await using (var db = NewDb(name))
        {
            var x = await db.PosSaleOrders.SingleAsync(a => a.Id == o.Id);
            Assert.Equal(100000m, x.PaidAmount);
            Assert.NotNull(x.DeliveryCodSettledAt);
            Assert.Equal(100000m, x.DeliveryCodReceivedAmount);
            var cash = await db.CashTransactions.SingleAsync(c => c.StoreId == _store);
            Assert.Equal(100000m, cash.Amount);
            Assert.Equal(CashTransactionType.Income, cash.Type);
        }
        // Bấm lần 2: không ghi trùng.
        await using (var db = NewDb(name))
        {
            var (n, _) = await Svc(db).SettleCodAsync(_store, [o.Id], true, _user, "u@x", default);
            Assert.Equal(0, n);
            Assert.Equal(1, await db.CashTransactions.CountAsync(c => c.StoreId == _store));
        }
    }

    [Fact]
    public async Task Khach_co_cong_no_duoc_tru_no_va_don_het_con_no()
    {
        var name = Guid.NewGuid().ToString();
        var cust = new PosCustomer { Id = Guid.NewGuid(), StoreId = _store, Name = "Lan", CurrentDebt = 100000 };
        var o = Order(100000, 100000, customerId: cust.Id);
        await using (var db = NewDb(name)) { db.PosCustomers.Add(cust); db.PosSaleOrders.Add(o); await db.SaveChangesAsync(); }

        await using (var db = NewDb(name))
            Assert.Equal(1, (await Svc(db).SettleCodAsync(_store, [o.Id], true, _user, "u@x", default)).Updated);
        await using (var db = NewDb(name))
        {
            Assert.Equal(0m, (await db.PosCustomers.SingleAsync(c => c.Id == cust.Id)).CurrentDebt);
            Assert.Equal(100000m, (await db.PosSaleOrders.SingleAsync(a => a.Id == o.Id)).PaidAmount);
            Assert.Equal(1, await db.PosCustomerPayments.CountAsync(p => p.CustomerId == cust.Id));
        }
    }

    [Fact]
    public async Task Khach_tra_cuoc_thang_cho_hang_cuoc_do_khong_vao_quy_nhung_het_con_no()
    {
        var name = Guid.NewGuid().ToString();
        var cust = new PosCustomer { Id = Guid.NewGuid(), StoreId = _store, Name = "Hoa", CurrentDebt = 118000 };
        // Phải trả 118.000 = hàng 100.000 + cước 18.000 (khách trả hãng); COD chỉ 100.000.
        var o = Order(100000, 100000, fee: 18000, payer: "customer", customerId: cust.Id);
        await using (var db = NewDb(name)) { db.PosCustomers.Add(cust); db.PosSaleOrders.Add(o); await db.SaveChangesAsync(); }

        await using (var db = NewDb(name))
            await Svc(db).SettleCodAsync(_store, [o.Id], true, _user, "u@x", default);
        await using (var db = NewDb(name))
        {
            var x = await db.PosSaleOrders.SingleAsync(a => a.Id == o.Id);
            Assert.Equal(118000m, x.PaidAmount);
            Assert.Equal(0m, x.PayableTotal - x.PaidAmount);
            Assert.Equal(0m, (await db.PosCustomers.SingleAsync(c => c.Id == cust.Id)).CurrentDebt);
            Assert.Equal(100000m, (await db.CashTransactions.SingleAsync(c => c.StoreId == _store)).Amount); // chỉ COD vào quỹ
        }
    }

    [Fact]
    public async Task Don_chua_giao_khong_doi_soat_duoc_va_da_ghi_so_khong_bo_doi_soat()
    {
        var name = Guid.NewGuid().ToString();
        var pending = Order(50000, 50000, status: ShipmentStatus.InTransit);
        var done = Order(70000, 70000);
        await using (var db = NewDb(name)) { db.PosSaleOrders.AddRange(pending, done); await db.SaveChangesAsync(); }

        await using (var db = NewDb(name))
        {
            var (n, errors) = await Svc(db).SettleCodAsync(_store, [pending.Id], true, _user, null, default);
            Assert.Equal(0, n);
            Assert.Single(errors);
            await Svc(db).SettleCodAsync(_store, [done.Id], true, _user, null, default);
        }
        await using (var db = NewDb(name))
        {
            var (n, errors) = await Svc(db).SettleCodAsync(_store, [done.Id], false, _user, null, default);
            Assert.Equal(1, n); // khách lẻ: hoàn tác được — hủy phiếu thu, trả «đã trả» về 0
            Assert.Empty(errors);
        }
        await using (var db = NewDb(name))
        {
            var x = await db.PosSaleOrders.SingleAsync(o => o.Id == done.Id);
            Assert.Null(x.DeliveryCodSettledAt);
            Assert.Equal(0m, x.PaidAmount);
            Assert.Empty(await db.CashTransactions.Where(c => c.StoreId == _store && c.IsActive && c.Deleted == null).ToListAsync());
        }
    }

    [Fact]
    public async Task Phieu_thu_COD_la_phieu_tu_sinh_va_da_tru_cong_no_thi_khong_bo_doi_soat()
    {
        var name = Guid.NewGuid().ToString();
        var cust = new PosCustomer { Id = Guid.NewGuid(), StoreId = _store, Name = "Mai", CurrentDebt = 100000 };
        var o = Order(100000, 100000, customerId: cust.Id);
        await using (var db = NewDb(name)) { db.PosCustomers.Add(cust); db.PosSaleOrders.Add(o); await db.SaveChangesAsync(); }
        await using (var db = NewDb(name))
            await Svc(db).SettleCodAsync(_store, [o.Id], true, _user, "u@x", default);
        await using (var db = NewDb(name))
        {
            var (n, errors) = await Svc(db).SettleCodAsync(_store, [o.Id], false, _user, "u@x", default);
            Assert.Equal(0, n); // đã trừ công nợ khách → phải hủy phiếu thu nợ trước
            Assert.Single(errors);
        }
        var src = ZKTecoADMS.Application.Services.CashSources.ParseNote($"pos cod #{o.Id}");
        Assert.Equal(ZKTecoADMS.Application.Services.CashSources.PosCodReceipt, src?.Type);
    }

    [Fact]
    public void Cuoc_hoan_tinh_vao_chi_phi_van_chuyen()
    {
        var returned = new ShippingReportRow(Guid.NewGuid(), "HD", null, null, "Ghn", "GHN", "T", null,
            ShipmentStatus.Returned, "x", 0, 25000, "shop", 0, DateTime.UtcNow, null, null, 0, null,
            null, null, null, null, null, ReturnFee: 12000);
        var s = PosShippingService.Summarize("Ghn", "GHN", [returned]);
        Assert.Equal(37000m, s.CarrierCost); // cước đi + cước hoàn
    }
}
