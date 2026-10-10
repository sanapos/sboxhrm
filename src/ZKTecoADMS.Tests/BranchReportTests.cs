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
}
