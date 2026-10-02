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

/// <summary>Hàng gia công: giá theo m² có tối thiểu / bộ; hợp đồng chia đợt, thu tiền → phiếu thu, hủy thu, công nợ.</summary>
public class MadeToOrderContractTests
{
    readonly Guid _store = Guid.NewGuid();
    readonly ZKTecoDbContext _db;
    readonly IServiceProvider _sp;
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public MadeToOrderContractTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    PosQuotesController Ctl() => new(_db, null!)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypes.Email, "admin@test.vn"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    static JsonElement Body(object? result, bool success = true)
    {
        var obj = result switch
        {
            ObjectResult o => o.Value,
            _ => throw new Xunit.Sdk.XunitException("Không phải ObjectResult: " + result?.GetType().Name),
        };
        var root = JsonDocument.Parse(JsonSerializer.Serialize(obj, Json)).RootElement;
        Assert.Equal(success, root.GetProperty("isSuccess").GetBoolean());
        return root;
    }

    PosQuote Quote(decimal total)
    {
        var q = new PosQuote
        {
            Id = Guid.NewGuid(), StoreId = _store, QuoteNo = "BG01102026" + Random.Shared.Next(1000, 9999),
            Status = PosQuoteStatus.Accepted, CommercialStage = PosQuoteCommercialStage.Accepted,
            CustomerName = "Anh Bình", CustomerPhone = "0900000000", Total = total, SubTotal = total,
            DepositAmount = total / 2, IsActive = true,
        };
        _db.PosQuotes.Add(q);
        _db.SaveChanges();
        return q;
    }

    [Fact]
    public void Area_pricing_uses_mm_and_minimum_per_set()
    {
        // Cửa đi 1800 × 2200 mm, 450.000đ/m² → 3,96 m² → 1.782.000đ / bộ
        var big = PosQuotesController.AreaPricing.Resolve(new PosQuotesController.QuoteLineInput(
            null, null, "Cửa đi", "Bộ", 3, 0, Width: 1800, Height: 2200, PricePerM2: 450_000, MinPricePerSet: 1_500_000));
        Assert.NotNull(big);
        Assert.Equal(3.96m, big!.AreaM2);
        Assert.Equal(1_782_000m, big.SetPrice);

        // Ô thoáng 400 × 500 mm = 0,2 m² → 90.000đ < tối thiểu 500.000đ → 500.000đ
        var small = PosQuotesController.AreaPricing.Resolve(new PosQuotesController.QuoteLineInput(
            null, null, "Ô thoáng", "Bộ", 2, 0, Width: 400, Height: 500, PricePerM2: 450_000, MinPricePerSet: 500_000));
        Assert.Equal(500_000m, small!.SetPrice);

        // Không có giá m² → dòng thường, giữ đơn giá nhập
        Assert.Null(PosQuotesController.AreaPricing.Resolve(new PosQuotesController.QuoteLineInput(
            null, null, "Phụ kiện", "Cái", 1, 120_000)));
    }

    [Fact]
    public async Task Contract_stages_payments_and_receivables()
    {
        var q = Quote(10_000_000);
        var ctl = Ctl();
        var past = DateTime.UtcNow.Date.AddDays(-3);
        var save = await ctl.SaveContract(q.Id, new PosQuotesController.ContractSaveDto(
            "15/2026/HĐ-NK", DateTime.UtcNow.Date, null, DateTime.UtcNow.Date.AddDays(20), null, null,
            [
                new("", "Đặt cọc", 50, 0, past, null),
                new("", "Lắp đặt xong", 40, 0, DateTime.UtcNow.Date.AddDays(20), null),
                new("", "Nghiệm thu", null, 1_000_000, null, null),
            ]));
        var c = Body(save.Result).GetProperty("data");
        var stages = c.GetProperty("stages");
        Assert.Equal(3, stages.GetArrayLength());
        Assert.Equal(5_000_000m, stages[0].GetProperty("amount").GetDecimal());
        Assert.Equal("overdue", stages[0].GetProperty("status").GetString());
        Assert.Equal(5_000_000m, c.GetProperty("overdueAmount").GetDecimal());
        Assert.Equal(nameof(PosQuoteCommercialStage.Contracted), c.GetProperty("commercialStage").GetString());

        // Thu 6 triệu: đủ đợt cọc, đợt 2 thu một phần
        var pay = await ctl.AddContractPayment(q.Id, new PosQuotesController.ContractPaymentInput(
            6_000_000, null, "Chuyển khoản", null, stages[0].GetProperty("id").GetString(), "Cọc + ứng"));
        c = Body(pay.Result).GetProperty("data");
        Assert.Equal(6_000_000m, c.GetProperty("collected").GetDecimal());
        Assert.Equal(4_000_000m, c.GetProperty("remaining").GetDecimal());
        Assert.Equal("paid", c.GetProperty("stages")[0].GetProperty("status").GetString());
        Assert.Equal("partial", c.GetProperty("stages")[1].GetProperty("status").GetString());
        Assert.Equal(0m, c.GetProperty("overdueAmount").GetDecimal());

        var cash = await _db.CashTransactions.SingleAsync();
        Assert.Equal(6_000_000m, cash.Amount);
        Assert.Equal(CashTransactionType.Income, cash.Type);
        Assert.Equal(PaymentMethodType.BankTransfer, cash.PaymentMethod);
        Assert.Equal("PosQuote", cash.SourceType);
        Assert.Equal(q.Id, cash.SourceId);
        Assert.Contains("15/2026/HĐ-NK", cash.Description);
        Assert.False(string.IsNullOrEmpty(c.GetProperty("payments")[0].GetProperty("cashCode").GetString()));

        // Thu vượt số còn lại → từ chối
        var over = await ctl.AddContractPayment(q.Id, new PosQuotesController.ContractPaymentInput(
            5_000_000, null, "Tiền mặt", null, null, null));
        Assert.IsType<BadRequestObjectResult>(over.Result);

        // Công nợ: còn phải thu 4 triệu
        var rec = Body((await ctl.Receivables(null, "owing")).Result).GetProperty("data");
        Assert.Equal(1, rec.GetProperty("totals").GetProperty("count").GetInt32());
        Assert.Equal(4_000_000m, rec.GetProperty("totals").GetProperty("remaining").GetDecimal());
        Assert.Equal(0, Body((await ctl.Receivables(null, "paid")).Result).GetProperty("data")
            .GetProperty("totals").GetProperty("count").GetInt32());

        // Không xóa được báo giá đã thu tiền
        Assert.IsType<BadRequestObjectResult>((await ctl.Delete(q.Id)).Result);

        // Hủy lần thu → phiếu thu «Đã hủy», số đã thu về 0, đợt cọc quá hạn trở lại
        var paymentId = Guid.Parse(c.GetProperty("payments")[0].GetProperty("id").GetString()!);
        c = Body((await ctl.CancelContractPayment(q.Id, paymentId)).Result).GetProperty("data");
        Assert.Equal(0m, c.GetProperty("collected").GetDecimal());
        Assert.Equal("overdue", c.GetProperty("stages")[0].GetProperty("status").GetString());
        Assert.Equal(CashTransactionStatus.Cancelled, (await _db.CashTransactions.SingleAsync()).Status);
    }

    [Fact]
    public async Task Percent_stages_follow_contract_value_after_quote_changes()
    {
        var q = Quote(10_000_000);
        var ctl = Ctl();
        await ctl.SaveContract(q.Id, new PosQuotesController.ContractSaveDto(
            null, null, null, null, null, null, [new("", "Đặt cọc", 30, 0, null, null)]));

        // Báo giá phát sinh thêm → giá trị HĐ 12 triệu → đợt 30% = 3,6 triệu
        var tracked = await _db.PosQuotes.AsTracking().SingleAsync(x => x.Id == q.Id);
        tracked.Total = 12_000_000;
        await _db.SaveChangesAsync();
        var c = Body((await ctl.GetContract(q.Id)).Result).GetProperty("data");
        Assert.Equal(3_600_000m, c.GetProperty("stages")[0].GetProperty("amount").GetDecimal());
    }
}
