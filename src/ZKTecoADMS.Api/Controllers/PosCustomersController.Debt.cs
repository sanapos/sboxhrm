using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosCustomersController
{
    public record CustomerPaymentDto(
        Guid Id, string PaymentNo, decimal Amount, string PaymentMethod,
        DateTime PaidAt, string? Note, Guid? SaleOrderId, string? CreatedBy);

    public record CreateCustomerPaymentDto(
        decimal Amount,
        string? PaymentMethod,
        DateTime? PaidAt,
        string? Note,
        Guid? SaleOrderId = null,
        Guid? BankAccountId = null);

    [HttpGet("{id:guid}/payments")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<CustomerPaymentDto>>>> GetPayments(Guid id)
    {
        var storeId = RequiredStoreId;
        var items = await dbContext.PosCustomerPayments.AsNoTracking()
            .Where(p => p.CustomerId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Select(p => new CustomerPaymentDto(
                p.Id, p.PaymentNo, p.Amount, p.PaymentMethod, p.PaidAt, p.Note, p.SaleOrderId, p.CreatedBy))
            .ToListAsync();
        return Ok(AppResponse<List<CustomerPaymentDto>>.Success(items));
    }

    [HttpPost("{id:guid}/payments")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CustomerPaymentDto>>> AddPayment(
        Guid id, [FromBody] CreateCustomerPaymentDto dto)
    {
        var storeId = RequiredStoreId;
        var customer = await dbContext.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (customer == null)
            return NotFound(AppResponse<CustomerPaymentDto>.Fail("Không tìm thấy khách hàng"));

        var (pay, err) = await PosCustomerFinanceHelper.CollectDebtAsync(
            dbContext, storeId, customer, dto.Amount,
            dto.PaymentMethod ?? "Tiền mặt", dto.PaidAt, dto.Note, dto.SaleOrderId, CurrentUserEmail);
        if (err != null) return BadRequest(AppResponse<CustomerPaymentDto>.Fail(err));
        await PosFinanceSyncHelper.SyncCustomerPaymentAsync(
            dbContext, pay!, customer, CurrentUserId, dto.BankAccountId);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerPaymentDto>.Success(new CustomerPaymentDto(
            pay!.Id, pay.PaymentNo, pay.Amount, pay.PaymentMethod, pay.PaidAt, pay.Note,
            pay.SaleOrderId, pay.CreatedBy)));
    }

    [HttpGet("{id:guid}/points")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPointHistory(
        Guid id, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var customer = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (customer == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));

        var q = dbContext.PosCustomerPointTransactions.AsNoTracking()
            .Where(t => t.CustomerId == id && t.StoreId == storeId && t.Deleted == null);
        var total = await q.CountAsync();
        var items = await q.OrderByDescending(t => t.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(t => new
            {
                t.Id,
                Type = t.TransactionType.ToString(),
                t.Points,
                t.BalanceAfter,
                t.Note,
                t.SaleOrderId,
                t.CreatedAt,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            pointBalance = customer.PointBalance,
            total,
            page,
            pageSize,
            items,
        }));
    }

    [HttpGet("{id:guid}/history")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetHistory(Guid id, [FromQuery] int take = 30)
    {
        var storeId = RequiredStoreId;
        take = Math.Clamp(take, 5, 100);
        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.CustomerId == id && o.StoreId == storeId && o.Deleted == null)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Take(take)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                o.Status,
                o.Total,
                o.PaidAmount,
                BalanceDue = o.Total - o.PaidAmount,
                o.SaleDate,
                o.CreatedAt,
            })
            .ToListAsync();
        var payments = await dbContext.PosCustomerPayments.AsNoTracking()
            .Where(p => p.CustomerId == id && p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .Take(take)
            .Select(p => new
            {
                p.Id,
                p.PaymentNo,
                p.Amount,
                p.PaymentMethod,
                p.PaidAt,
                p.Note,
                p.SaleOrderId,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { orders, payments }));
    }
}
