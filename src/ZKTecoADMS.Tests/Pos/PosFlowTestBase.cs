using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Tiện ích dựng luồng bán – trả – hủy qua chính controller (CSDL PostgreSQL tạm).</summary>
public abstract class PosFlowTestBase(PosPgFixture fx)
{
    protected readonly PosPgFixture Fx = fx;
    protected bool NoDb => Fx.ConnectionString == null;

    protected PosSalesController Sales(ZKTecoDbContext db, Guid storeId) =>
        PosPgFixture.As(new PosSalesController(db, null!, null!, null!, null!), storeId);

    protected PosReportsController Reports(ZKTecoDbContext db, Guid storeId) =>
        PosPgFixture.As(new PosReportsController(db, null!), storeId);

    protected static T Data<T>(ActionResult<AppResponse<T>> r)
    {
        var ok = r.Result as OkObjectResult;
        if (ok == null)
        {
            var msg = (r.Result as ObjectResult)?.Value is AppResponse<T> fail ? string.Join("; ", fail.Errors) + fail.Message : r.Result?.ToString();
            throw new Xunit.Sdk.XunitException("API lỗi: " + msg);
        }
        return ((AppResponse<T>)ok.Value!).Data!;
    }

    protected static string? Error<T>(ActionResult<AppResponse<T>> r) =>
        r.Result is ObjectResult { Value: AppResponse<T> a } o && o.StatusCode is >= 400
            ? (a.Message is { Length: > 0 } ? a.Message : string.Join("; ", a.Errors))
            : null;

    /// <summary>Bán và hoàn thành đơn ngay (tiền mặt, trả đủ).</summary>
    protected async Task<PosSalesController.SaleOrderDto> SellAsync(Guid storeId,
        params (Guid ProductId, decimal Qty, decimal Price, Guid? UnitId)[] lines) =>
        await SellAsync(storeId, 0, 0, lines);

    protected async Task<PosSalesController.SaleOrderDto> SellAsync(Guid storeId, decimal discount, decimal vat,
        params (Guid ProductId, decimal Qty, decimal Price, Guid? UnitId)[] lines)
    {
        await using var db = Fx.NewDb();
        var total = lines.Sum(l => l.Qty * l.Price) - discount + vat;
        var dto = new PosSalesController.CreateSaleDto(
            [.. lines.Select(l => new PosSalesController.SaleLineDto(l.ProductId, l.Qty, l.UnitId, l.Price, null))],
            discount, total, "Tiền mặt", null, null, null, VatAmount: vat);
        return Data(await Sales(db, storeId).CreateSale(dto));
    }

    protected async Task<ActionResult<AppResponse<object>>> ReturnAsync(Guid storeId, Guid orderId,
        params (Guid ProductId, decimal Qty)[] lines)
    {
        await using var db = Fx.NewDb();
        return await Sales(db, storeId).ReturnSale(orderId, new PosSalesController.ReturnSaleDto(
            [.. lines.Select(l => new PosSalesController.ReturnLineDto(l.ProductId, l.Qty, null))], null, "Tiền mặt"));
    }

    protected async Task<decimal> OnHandAsync(Guid productId)
    {
        await using var db = Fx.NewDb();
        return (await db.PosProducts.FirstAsync(p => p.Id == productId)).OnHandQty;
    }

    protected async Task<PosSaleOrder> OrderAsync(Guid orderId)
    {
        await using var db = Fx.NewDb();
        return await db.PosSaleOrders.FirstAsync(o => o.Id == orderId);
    }

    protected async Task<Guid> AddUnitAsync(Guid storeId, Guid productId, string name, decimal rate)
    {
        await using var db = Fx.NewDb();
        var u = new PosProductUnit { Id = Guid.NewGuid(), StoreId = storeId, ProductId = productId, UnitName = name, ConversionRate = rate, IsActive = true };
        db.PosProductUnits.Add(u);
        await db.SaveChangesAsync();
        return u.Id;
    }

    protected async Task AddComboLineAsync(Guid storeId, Guid comboId, Guid componentId, decimal qty)
    {
        await using var db = Fx.NewDb();
        db.PosProductComboLines.Add(new PosProductComboLine { Id = Guid.NewGuid(), StoreId = storeId, ComboProductId = comboId, ComponentProductId = componentId, Qty = qty, IsActive = true });
        await db.SaveChangesAsync();
    }

    protected async Task AddRecipeLineAsync(Guid storeId, Guid parentId, Guid componentId, decimal qty)
    {
        await using var db = Fx.NewDb();
        db.PosProductRecipeLines.Add(new PosProductRecipeLine { Id = Guid.NewGuid(), StoreId = storeId, ParentProductId = parentId, ComponentProductId = componentId, Qty = qty, IsActive = true });
        await db.SaveChangesAsync();
    }
}
