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
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Sổ công nợ khách / NCC: ghi phát sinh, sổ đối chiếu đầu kỳ – cuối kỳ, trả nợ NCC gộp nhiều phiếu.</summary>
public class PosDebtLedgerTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public PosDebtLedgerTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    ControllerContext Ctx() => new()
    {
        HttpContext = new DefaultHttpContext
        {
            RequestServices = _sp,
            User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("id", Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.Role, "Admin"),
                new Claim(ClaimTypes.Email, "admin@test"),
                new Claim(ClaimTypeNames.StoreId, _store.ToString()),
            ], "test")),
        },
    };

    static JsonElement Data(object? result)
    {
        var obj = result is ObjectResult o ? o.Value : result;
        return JsonDocument.Parse(JsonSerializer.Serialize(obj, Json)).RootElement.GetProperty("data");
    }

    PosCustomer NewCustomer()
    {
        var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = _store, CustomerCode = "KH1", Name = "Khách 1", IsActive = true };
        _db.PosCustomers.Add(c);
        return c;
    }

    PosSaleOrder NewOrder(PosCustomer c, decimal total, decimal vat, decimal paid, DateTime saleDate)
    {
        var o = new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = _store, CustomerId = c.Id, OrderNo = "HD" + Guid.NewGuid().ToString()[..4],
            Status = PosSaleOrderStatus.Completed, Total = total, VatAmount = vat, PaidAmount = paid,
            IsActive = true, SaleDate = saleDate,
        };
        _db.PosSaleOrders.Add(o);
        return o;
    }

    [Fact]
    public async Task Ban_thu_no_tra_hang_ghi_so_va_doi_chieu_dung()
    {
        var c = NewCustomer();
        await _db.SaveChangesAsync();
        _db.ChangeTracker.Clear();

        // Tháng trước: bán 1.000.000 + VAT 100.000, chưa trả → đầu kỳ tháng này = 1.100.000.
        var lastMonth = DateTime.UtcNow.AddMonths(-1).AddDays(-2);
        var o1 = NewOrder(c, 1_000_000, 100_000, 0, lastMonth);
        await _db.SaveChangesAsync();
        await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(_db, _store, o1);
        await _db.SaveChangesAsync();
        _db.ChangeTracker.Clear();

        // Tháng này: bán 500.000, trả trước 200.000 → nợ thêm 300.000.
        var o2 = NewOrder(c, 500_000, 0, 200_000, DateTime.UtcNow.AddMinutes(-30));
        await _db.SaveChangesAsync();
        await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(_db, _store, o2);
        await _db.SaveChangesAsync();
        _db.ChangeTracker.Clear();

        // Thu nợ toàn bộ đơn cũ (gồm VAT) → đơn 1 phải hết nợ (trước đây còn treo phần VAT).
        var cust = await _db.PosCustomers.AsTracking().FirstAsync(x => x.Id == c.Id);
        Assert.Equal(1_400_000, cust.CurrentDebt);
        var (pay, err) = await PosCustomerFinanceHelper.CollectDebtAsync(_db, _store, cust, 1_100_000, "Tiền mặt", null, null, null, "test");
        Assert.Null(err);
        await _db.SaveChangesAsync();
        _db.ChangeTracker.Clear();
        var o1After = await _db.PosSaleOrders.FirstAsync(x => x.Id == o1.Id);
        var o2After = await _db.PosSaleOrders.FirstAsync(x => x.Id == o2.Id);
        Assert.Equal(1_100_000, o1After.PaidAmount);
        Assert.Equal(200_000, o2After.PaidAmount);

        var ctl = new PosCustomersController(_db) { ControllerContext = Ctx() };
        var d = Data((await ctl.Statement(c.Id, null, null)).Result);
        Assert.Equal(1_100_000, d.GetProperty("opening").GetDecimal());
        Assert.Equal(300_000, d.GetProperty("increase").GetDecimal());
        Assert.Equal(1_100_000, d.GetProperty("decrease").GetDecimal());
        Assert.Equal(300_000, d.GetProperty("closing").GetDecimal());
        Assert.Equal(300_000, d.GetProperty("currentBalance").GetDecimal());
        var items = d.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(["Sale", "Payment"], items.Select(i => i.GetProperty("docType").GetString()!).ToArray());
        Assert.Equal(1_400_000, items[0].GetProperty("balance").GetDecimal());
        Assert.Equal(300_000, items[1].GetProperty("balance").GetDecimal());
        Assert.Equal(pay!.PaymentNo, items[1].GetProperty("docNo").GetString());

        // Trả hàng 100.000 trên đơn 2 (còn nợ) → giảm nợ, ghi sổ «Return».
        var o2t = await _db.PosSaleOrders.FirstAsync(x => x.Id == o2.Id);
        await PosSaleStockHelper.UpdateCustomerOnReturnAsync(_db, _store, o2t, 100_000);
        await _db.SaveChangesAsync();
        var all = await _db.PosDebtLedgerEntries.Where(e => e.PartyId == c.Id).ToListAsync();
        Assert.Contains(all, e => e.DocType == "Return" && e.Delta == -100_000 && e.BalanceAfter == 200_000);
        Assert.Equal(200_000, (await _db.PosCustomers.FirstAsync(x => x.Id == c.Id)).CurrentDebt);
    }

    [Fact]
    public async Task Doi_chieu_co_so_du_dau_khi_chi_co_dong_Opening()
    {
        var c = NewCustomer();
        c.CurrentDebt = 750_000;
        _db.PosDebtLedgerEntries.Add(new PosDebtLedgerEntry
        {
            Id = Guid.NewGuid(), StoreId = _store, PartyType = PosDebtLedger.Customer, PartyId = c.Id,
            At = DateTime.UtcNow.AddMonths(-3), DocType = "Opening", Delta = 750_000, BalanceAfter = 750_000,
        });
        await _db.SaveChangesAsync();
        var ctl = new PosCustomersController(_db) { ControllerContext = Ctx() };
        var d = Data((await ctl.Statement(c.Id, null, null)).Result);
        Assert.Equal(750_000, d.GetProperty("opening").GetDecimal());
        Assert.Equal(750_000, d.GetProperty("closing").GetDecimal());
        Assert.Empty(d.GetProperty("items").EnumerateArray());
    }

    [Fact]
    public async Task Tra_no_NCC_gop_chia_FIFO_theo_phieu_nhap()
    {
        var s = new PosSupplier { Id = Guid.NewGuid(), StoreId = _store, SupplierCode = "NCC1", Name = "NCC 1", CurrentDebt = 900_000 };
        _db.PosSuppliers.Add(s);
        PosStockReceipt R(string no, int daysAgo, decimal cost, decimal paid) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, SupplierId = s.Id, ReceiptNo = no, Status = PosPurchaseReceiptStatus.Completed,
            ImportDate = DateTime.UtcNow.AddDays(-daysAgo), TotalCost = cost, PaidAmount = paid,
        };
        var old = R("PN1", 10, 500_000, 100_000);   // còn 400.000
        var mid = R("PN2", 5, 300_000, 0);          // còn 300.000
        var paidOff = R("PN0", 20, 200_000, 200_000);
        var newest = R("PN3", 1, 200_000, 0);       // còn 200.000
        _db.PosStockReceipts.AddRange(old, mid, paidOff, newest);
        await _db.SaveChangesAsync();

        var ctl = new PosPurchaseSuppliersController(_db) { ControllerContext = Ctx() };
        var tooMuch = await ctl.PayAll(s.Id, new(1_000_000, null, null, null));
        Assert.IsType<BadRequestObjectResult>(tooMuch.Result);

        var res = Data((await ctl.PayAll(s.Id, new(550_000, "Chuyển khoản", null, null))).Result);
        var paid = res.GetProperty("paid").EnumerateArray().ToList();
        Assert.Equal(["PN1", "PN2"], paid.Select(p => p.GetProperty("receiptNo").GetString()!).ToArray());
        Assert.Equal([400_000m, 150_000m], paid.Select(p => p.GetProperty("amount").GetDecimal()).ToArray());
        Assert.Equal(350_000, res.GetProperty("remainingDebt").GetDecimal());

        _db.ChangeTracker.Clear();
        Assert.Equal(500_000, (await _db.PosStockReceipts.FirstAsync(r => r.Id == old.Id)).PaidAmount);
        Assert.Equal(150_000, (await _db.PosStockReceipts.FirstAsync(r => r.Id == mid.Id)).PaidAmount);
        Assert.Equal(0, (await _db.PosStockReceipts.FirstAsync(r => r.Id == newest.Id)).PaidAmount);
        Assert.Equal(2, await _db.PosSupplierPayments.CountAsync());
        // Hai phiếu chi quỹ, mã khác nhau, chung một danh mục «Nhập hàng».
        var cash = await _db.CashTransactions.ToListAsync();
        Assert.Equal(2, cash.Count);
        Assert.Equal(2, cash.Select(x => x.TransactionCode).Distinct().Count());
        Assert.Equal(1, await _db.TransactionCategories.CountAsync());

        var st = Data((await ctl.Statement(s.Id, null, null)).Result);
        var items = st.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(2, items.Count);
        Assert.All(items, i => Assert.Equal("Payment", i.GetProperty("docType").GetString()));
        Assert.Equal(350_000, st.GetProperty("closing").GetDecimal());
        Assert.Equal(550_000, st.GetProperty("decrease").GetDecimal());
    }
}
