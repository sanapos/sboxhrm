using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Báo cáo so sánh chi nhánh khớp báo cáo Lãi lỗ: giờ cắt ngày, không trừ hàng trả hai lần,
/// chi lương / ứng lương không tính vào chi phí, lương chia theo ngày của tháng trong kỳ.
/// </summary>
public class BranchReportTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly Guid _store = Guid.NewGuid(), _hq = Guid.NewGuid(), _a = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public BranchReportTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    BranchOperationsController Ctl() => new(_db, new BranchContext
    {
        StoreUsesBranches = true, HeadquarterBranchId = _hq, CurrentBranchId = _hq,
    })
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    static DateTime Utc(int m, int d, int h) => new(2026, m, d, h, 0, 0); // giờ UTC (cột lưu UTC)

    async Task SeedAsync()
    {
        _db.Branches.AddRange(
            new Branch { Id = _hq, StoreId = _store, Code = "HQ", Name = "Trụ sở", IsHeadquarter = true, IsActive = true },
            new Branch { Id = _a, StoreId = _store, Code = "A", Name = "Chi nhánh A", IsActive = true });
        // Ngày kinh doanh bắt đầu 4h sáng.
        _db.PosStoreSellSettings.Add(new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = _store, ReportDayStartHour = 4 });
        // 1/10 10h VN; 2/10 01h VN (= ngày kinh doanh 1/10 vì trước 4h); 2/10 10h VN (ngoài kỳ).
        PosSaleOrder O(Guid? b, decimal total, DateTime saleUtc) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, BranchId = b, OrderNo = Guid.NewGuid().ToString()[..6],
            Status = PosSaleOrderStatus.Completed, Total = total, SaleDate = saleUtc, IsActive = true,
        };
        _db.PosSaleOrders.AddRange(
            O(_hq, 1_000_000, Utc(10, 1, 3)),
            O(_a, 500_000, Utc(10, 1, 18)),
            O(_a, 999_999, Utc(10, 2, 3)));

        var cat = new TransactionCategory { Id = Guid.NewGuid(), StoreId = _store, Name = "Chi phí khác" };
        _db.Add(cat);
        CashTransaction C(Guid b, CashTransactionType t, decimal amt, string? src, DateTime vn) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, BranchId = b, Type = t, Amount = amt, SourceType = src,
            CategoryId = cat.Id, TransactionCode = Guid.NewGuid().ToString()[..6], TransactionDate = vn,
            Status = CashTransactionStatus.Completed, IsActive = true,
        };
        _db.CashTransactions.AddRange(
            C(_a, CashTransactionType.Expense, 200_000, CashSources.Manual, new DateTime(2026, 10, 1, 12, 0, 0)),    // chi phí
            C(_a, CashTransactionType.Expense, 300_000, CashSources.Payslip, new DateTime(2026, 10, 1, 12, 0, 0)),   // chi lương → không tính
            C(_a, CashTransactionType.Expense, 100_000, CashSources.Advance, new DateTime(2026, 10, 1, 12, 0, 0)),   // chi ứng → không tính
            C(_a, CashTransactionType.Income, 500_000, CashSources.PosSale, new DateTime(2026, 10, 1, 12, 0, 0)),    // tiền bán → không tính
            C(_a, CashTransactionType.Expense, 50_000, CashSources.Manual, new DateTime(2026, 10, 2, 5, 0, 0)));     // ngoài kỳ (sau 4h ngày 2/10)

        var emp = new Employee { Id = Guid.NewGuid(), StoreId = _store, BranchId = _a, FirstName = "A", LastName = "NV", EmployeeCode = "NV1" };
        _db.Employees.Add(emp);
        _db.Payslips.Add(new Payslip
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeId = emp.Id, Year = 2026, Month = 10,
            GrossSalary = 3_100_000, Status = PayslipStatus.Approved,
        });
        await _db.SaveChangesAsync();
    }

    [Fact]
    public async Task So_sanh_chi_nhanh_theo_gio_cat_ngay_va_khop_lai_lo()
    {
        await SeedAsync();
        var res = await Ctl().Compare(new DateTime(2026, 10, 1), new DateTime(2026, 10, 1));
        var root = JsonDocument.Parse(JsonSerializer.Serialize(Assert.IsType<OkObjectResult>(res.Result).Value, Json)).RootElement;
        Assert.True(root.GetProperty("isSuccess").GetBoolean(), root.ToString());
        var rows = root.GetProperty("data").GetProperty("branches").EnumerateArray()
            .ToDictionary(r => r.GetProperty("code").GetString()!);

        Assert.Equal(1_000_000m, rows["HQ"].GetProperty("revenue").GetDecimal());
        var a = rows["A"];
        Assert.Equal(500_000m, a.GetProperty("revenue").GetDecimal());       // đơn 01h sáng 2/10 thuộc ngày 1/10
        Assert.Equal(1, a.GetProperty("orders").GetInt32());
        Assert.Equal(500_000m, a.GetProperty("grossProfit").GetDecimal());   // không trừ hoàn trả lần nữa
        Assert.Equal(200_000m, a.GetProperty("expenses").GetDecimal());      // không gồm chi lương / ứng / bán hàng
        Assert.Equal(0m, a.GetProperty("otherIncome").GetDecimal());
        Assert.Equal(100_000m, a.GetProperty("payroll").GetDecimal());       // 3,1tr × 1/31 ngày
        Assert.Equal(200_000m, a.GetProperty("netProfit").GetDecimal());     // 500k − 200k − 100k
    }

    [Fact]
    public async Task Lai_rong_gom_phu_thu_phi_giao_hang_tru_cuoc_khau_hao_va_coc_khach_bo()
    {
        await SeedAsync();
        var emp = await _db.Employees.FirstAsync();
        PosSaleOrder O(decimal total, PosSaleOrderStatus st) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, BranchId = _a, OrderNo = Guid.NewGuid().ToString()[..6],
            Status = st, Total = total, SaleDate = Utc(10, 1, 5), IsActive = true,
        };
        var shipped = O(100_000, PosSaleOrderStatus.Completed);
        shipped.SurchargeAmount = 30_000; shipped.DeliveryFee = 20_000; shipped.DeliveryFeePayer = "shop";
        shipped.DeliveryCarrierCode = "ghtk"; shipped.DeliveryCarrierFee = 25_000; shipped.DeliveryStatusCode = "delivered";
        // Đơn bị hoàn (đã hủy): không có doanh thu nhưng vẫn mất cước + cước hoàn.
        var returned = O(70_000, PosSaleOrderStatus.Cancelled);
        returned.DeliveryCarrierCode = "ghtk"; returned.DeliveryCarrierFee = 15_000; returned.DeliveryReturnFee = 10_000;
        returned.DeliveryStatusCode = "returned";
        // Khách trả cước thẳng cho hãng: shop không thu, không chi.
        var customerPays = O(0, PosSaleOrderStatus.Completed);
        customerPays.DeliveryFee = 40_000; customerPays.DeliveryFeePayer = "customer";
        customerPays.DeliveryCarrierCode = "ghn"; customerPays.DeliveryCarrierFee = 40_000;
        // Vận đơn hủy trước khi lấy hàng: không tốn cước.
        var shipCancelled = O(0, PosSaleOrderStatus.Cancelled);
        shipCancelled.DeliveryCarrierCode = "ghn"; shipCancelled.DeliveryCarrierFee = 30_000; shipCancelled.DeliveryStatusCode = "cancelled";
        _db.PosSaleOrders.AddRange(shipped, returned, customerPays, shipCancelled);

        var lostDeposit = new TransactionCategory { Id = Guid.NewGuid(), StoreId = _store, Name = "Mất cọc đặt chỗ", Type = CashTransactionType.Income };
        var buyAsset = new TransactionCategory { Id = Guid.NewGuid(), StoreId = _store, Name = "Mua tài sản", Type = CashTransactionType.Expense };
        _db.AddRange(lostDeposit, buyAsset);
        CashTransaction C(TransactionCategory cat, CashTransactionType t, decimal amt, string? note) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, BranchId = _a, Type = t, Amount = amt, CategoryId = cat.Id, InternalNote = note,
            TransactionCode = Guid.NewGuid().ToString()[..6], TransactionDate = new DateTime(2026, 10, 1, 12, 0, 0),
            Status = CashTransactionStatus.Completed, IsActive = true,
        };
        _db.CashTransactions.AddRange(
            C(lostDeposit, CashTransactionType.Income, 100_000,
                ZKTecoADMS.Infrastructure.Services.PosFinanceSyncHelper.ReservationDepositMarker + Guid.NewGuid()),
            C(buyAsset, CashTransactionType.Expense, 5_000_000, null));   // đã vào khấu hao → không tính chi phí
        // Máy giao cho NV chi nhánh A: 36,5 triệu, 100%/năm → 100.000 đ/ngày (kỳ 1 ngày kinh doanh).
        _db.Assets.Add(new Asset
        {
            Id = Guid.NewGuid(), StoreId = _store, AssetCode = "TS1", Name = "Máy pha", PurchasePrice = 36_500_000, Quantity = 1,
            DepreciationRate = 100, PurchaseDate = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc), Status = AssetStatus.Active,
            CurrentAssigneeId = emp.Id, IsActive = true,
        });
        await _db.SaveChangesAsync();

        var res = await Ctl().Compare(new DateTime(2026, 10, 1), new DateTime(2026, 10, 1));
        var root = JsonDocument.Parse(JsonSerializer.Serialize(Assert.IsType<OkObjectResult>(res.Result).Value, Json)).RootElement;
        var a = root.GetProperty("data").GetProperty("branches").EnumerateArray().First(r => r.GetProperty("code").GetString() == "A");
        Assert.Equal(600_000m, a.GetProperty("revenue").GetDecimal());          // doanh thu thuần giữ nguyên (Σ Total)
        Assert.Equal(30_000m, a.GetProperty("surchargeIncome").GetDecimal());
        Assert.Equal(20_000m, a.GetProperty("deliveryFeeIncome").GetDecimal());
        Assert.Equal(50_000m, a.GetProperty("carrierCost").GetDecimal());       // 25k + 15k + 10k cước hoàn
        Assert.Equal(100_000m, a.GetProperty("forfeitedDeposits").GetDecimal());
        Assert.Equal(100_000m, a.GetProperty("depreciation").GetDecimal());
        Assert.Equal(200_000m, a.GetProperty("expenses").GetDecimal());         // không gồm 5 triệu mua tài sản
        Assert.Equal(0m, a.GetProperty("otherIncome").GetDecimal());
        // 600 + 30 + 20 − 50 − 100 (khấu hao) + 100 (cọc) − 200 (chi phí) − 100 (lương)
        Assert.Equal(300_000m, a.GetProperty("netProfit").GetDecimal());
        var totals = root.GetProperty("data").GetProperty("totals");
        Assert.Equal(100_000m, totals.GetProperty("depreciation").GetDecimal());
    }

    [Fact]
    public async Task Tien_COD_hang_chuyen_ve_khong_tinh_la_thu_khac()
    {
        await SeedAsync();
        // Phiếu thu tự sinh khi hãng chuyển tiền COD của đơn (không có SourceType, nhận theo ghi chú / danh mục).
        var cod = new TransactionCategory { Id = Guid.NewGuid(), StoreId = _store, Name = "Thu hộ COD", Type = CashTransactionType.Income };
        _db.Add(cod);
        _db.CashTransactions.Add(new CashTransaction
        {
            Id = Guid.NewGuid(), StoreId = _store, BranchId = _a, Type = CashTransactionType.Income, Amount = 450_000,
            CategoryId = cod.Id, TransactionCode = "PT-COD1", TransactionDate = new DateTime(2026, 10, 1, 15, 0, 0),
            InternalNote = $"{ZKTecoADMS.Infrastructure.Services.PosFinanceSyncHelper.CodReceiptMarker}{Guid.NewGuid()}",
            Status = CashTransactionStatus.Completed, IsActive = true,
        });
        await _db.SaveChangesAsync();

        var res = await Ctl().Compare(new DateTime(2026, 10, 1), new DateTime(2026, 10, 1));
        var root = JsonDocument.Parse(JsonSerializer.Serialize(Assert.IsType<OkObjectResult>(res.Result).Value, Json)).RootElement;
        var a = root.GetProperty("data").GetProperty("branches").EnumerateArray().First(r => r.GetProperty("code").GetString() == "A");
        Assert.Equal(0m, a.GetProperty("otherIncome").GetDecimal());   // trước đây 450.000
        Assert.Equal(200_000m, a.GetProperty("netProfit").GetDecimal());
    }
}
