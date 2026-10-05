using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Interceptors;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Sổ quỹ chung HRM + POS: phiếu tự sinh mang nguồn chuẩn + chi nhánh của chứng từ gốc.</summary>
public class CashSourceTests
{
    static ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .AddInterceptors(new CashSourceInterceptor())
        .Options);

    static CashTransaction Cash(Guid storeId, string? note, CashTransactionType type = CashTransactionType.Income) => new()
    {
        Id = Guid.NewGuid(), StoreId = storeId, TransactionCode = "TH-" + Guid.NewGuid().ToString("N")[..6],
        Type = type, Amount = 100_000, CategoryId = Guid.NewGuid(), Description = "test",
        TransactionDate = DateTime.UtcNow, Status = CashTransactionStatus.Completed, IsPaid = true,
        InternalNote = note, IsActive = true, CreatedByUserId = Guid.NewGuid(),
    };

    [Theory]
    [InlineData("pos bán hàng #{0}|0", CashSources.PosSale)]
    [InlineData("pos hoàn cọc đặt chỗ #{0}", CashSources.PosDepositRefund)]
    [InlineData("pos cọc đặt chỗ #{0}|50000|123", CashSources.PosDeposit)]
    [InlineData("pos thu hđ #{0}|abc", CashSources.PosContract)]
    [InlineData("Tự động tạo từ thu hoàn ứng công tác #{0}", CashSources.TripRefund)]
    [InlineData("Tự động tạo từ ứng công tác #{0}", CashSources.TripAdvance)]
    [InlineData("Ghi chú KT | Tự động tạo từ phiếu thưởng/phạt #{0}", CashSources.Reward)]
    [InlineData("Tự động tạo từ phiếu phạt #{0}", CashSources.Reward)]
    [InlineData("phiếu lương #{0}", CashSources.Payslip)]
    public void Doc_chuoi_lien_ket_cu(string template, string expected)
    {
        var id = Guid.NewGuid();
        var r = CashSources.ParseNote(string.Format(template, id));
        Assert.Equal((expected, id), r);
    }

    [Fact]
    public void Phieu_lap_tay_khong_suy_nguon_tu_ghi_chu()
    {
        Assert.Null(CashSources.Resolve(CashSources.Manual, null, $"pos bán hàng #{Guid.NewGuid()}|0"));
        Assert.True(CashSources.IsPos(CashSources.PosContract));
        Assert.False(CashSources.IsLinked(CashSources.Manual));
    }

    [Fact]
    public async Task Phieu_thu_ban_hang_moi_lay_chi_nhanh_cua_don()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var branchB = Guid.NewGuid();
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = store, BranchId = branchB, OrderNo = "HD1" };
        db.PosSaleOrders.Add(order);
        await db.SaveChangesAsync();

        var cash = Cash(store, $"{PosFinanceSyncHelper.SaleMarker}{order.Id}|0");
        db.CashTransactions.Add(cash);
        await db.SaveChangesAsync();

        Assert.Equal(CashSources.PosSale, cash.SourceType);
        Assert.Equal(order.Id, cash.SourceId);
        Assert.Equal(branchB, cash.BranchId);
    }

    [Fact]
    public async Task Phieu_ung_luong_lay_nhan_vien_va_chi_nhanh_nhan_vien()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var branch = Guid.NewGuid();
        var emp = new Employee { Id = Guid.NewGuid(), StoreId = store, BranchId = branch, EmployeeCode = "NV1", FirstName = "A", LastName = "B" };
        var adv = new AdvanceRequest { Id = Guid.NewGuid(), StoreId = store, EmployeeId = emp.Id, Amount = 1_000_000 };
        db.AddRange(emp, adv);
        await db.SaveChangesAsync();

        var cash = Cash(store, $"Tự động tạo từ yêu cầu ứng lương #{adv.Id}", CashTransactionType.Expense);
        db.CashTransactions.Add(cash);
        await db.SaveChangesAsync();

        Assert.Equal(CashSources.Advance, cash.SourceType);
        Assert.Equal(emp.Id, cash.EmployeeId);
        Assert.Equal(branch, cash.BranchId);
    }

    [Fact]
    public async Task Bo_thanh_toan_phieu_ung_luong_tra_don_ung_ve_chua_chi()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var adv = new AdvanceRequest { Id = Guid.NewGuid(), StoreId = store, Amount = 500_000, IsPaid = true, PaidDate = DateTime.UtcNow };
        db.AdvanceRequests.Add(adv);
        var cash = Cash(store, null, CashTransactionType.Expense);
        cash.SourceType = CashSources.Advance;
        cash.SourceId = adv.Id;
        db.CashTransactions.Add(cash);
        await db.SaveChangesAsync();

        await CashSourceRevert.RevertPaidAsync(db, cash, store, deleting: false);
        await db.SaveChangesAsync();
        Assert.False((await db.AdvanceRequests.AsNoTracking().FirstAsync(a => a.Id == adv.Id)).IsPaid);
    }

    [Fact]
    public async Task Chuyen_du_lieu_cu_gan_nguon_va_sua_chi_nhanh_phieu_ban_hang()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var hqWrong = Guid.NewGuid();
        var branchB = Guid.NewGuid();
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = store, BranchId = branchB, OrderNo = "HD2" };
        db.PosSaleOrders.Add(order);
        await db.SaveChangesAsync();
        var old = Cash(store, $"{PosFinanceSyncHelper.SaleMarker}{order.Id}|0");
        var manual = Cash(store, "tiền điện tháng 9");
        db.CashTransactions.AddRange(old, manual);
        await db.SaveChangesAsync();
        // Mô phỏng dữ liệu trước khi có chốt: chưa có nguồn, chi nhánh sai (đơn online bị tính về trụ sở).
        old.SourceType = null; old.SourceId = null; old.BranchId = hqWrong;
        await db.SaveChangesAsync();

        var (linked, branched, _) = await CashSourceBackfill.ApplyAsync(db);
        Assert.Equal(1, linked);
        Assert.Equal(1, branched);

        var o = await db.CashTransactions.AsNoTracking().FirstAsync(c => c.Id == old.Id);
        Assert.Equal(CashSources.PosSale, o.SourceType);
        Assert.Equal(branchB, o.BranchId);
        var m = await db.CashTransactions.AsNoTracking().FirstAsync(c => c.Id == manual.Id);
        Assert.Equal(CashSources.Manual, m.SourceType);
    }
    [Fact]
    public async Task Chuyen_du_lieu_cu_khong_gan_trung_chung_tu_nhan_su_nhung_cho_nhieu_phieu_ban_hang()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var adv = new AdvanceRequest { Id = Guid.NewGuid(), StoreId = store, Amount = 500_000 };
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = store, OrderNo = "HD3" };
        db.AddRange(adv, order);
        await db.SaveChangesAsync();
        var a1 = Cash(store, $"Tự động tạo từ yêu cầu ứng lương #{adv.Id}", CashTransactionType.Expense);
        var a2 = Cash(store, $"Tự động tạo từ yêu cầu ứng lương #{adv.Id}", CashTransactionType.Expense);
        var s1 = Cash(store, $"{PosFinanceSyncHelper.SaleMarker}{order.Id}|0");
        var s2 = Cash(store, $"{PosFinanceSyncHelper.SaleMarker}{order.Id}|1");
        db.CashTransactions.AddRange(a1, a2, s1, s2);
        await db.SaveChangesAsync();
        foreach (var c in new[] { a1, a2, s1, s2 }) { c.SourceType = null; c.SourceId = null; }
        await db.SaveChangesAsync();

        await CashSourceBackfill.ApplyAsync(db);

        var all = await db.CashTransactions.AsNoTracking().ToListAsync();
        Assert.Equal(1, all.Count(c => c.SourceType == CashSources.Advance && c.SourceId == adv.Id));
        Assert.Equal(2, all.Count(c => c.SourceType == CashSources.PosSale && c.SourceId == order.Id));
    }
}
