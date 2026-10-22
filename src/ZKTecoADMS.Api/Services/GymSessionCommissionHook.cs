using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Hoa hồng buổi PT khi hội viên check-in trừ buổi (gói chọn «hoa hồng mỗi buổi»).</summary>
public sealed class GymSessionCommissionHook(ZKTecoDbContext db) : IGymSessionCommissionHook
{
    public async Task OnSessionDeductedAsync(Guid storeId, Guid customerId, PosCustomerSessionBalance balance,
        Guid sessionTransactionId, DateTime performedAtUtc, string? actor)
    {
        if (balance.ProductId is not Guid productId) return;
        var product = await db.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId);
        if (product == null || !PosStaffCommissionHelper.IsPerSessionPack(product)) return;
        var trainer = await db.PosCustomers.AsNoTracking()
            .Where(c => c.Id == customerId && c.StoreId == storeId)
            .Select(c => new { c.GymTrainerEmployeeId, c.GymTrainerName })
            .FirstOrDefaultAsync();
        if (trainer?.GymTrainerEmployeeId is not Guid employeeId) return;
        await PosStaffCommissionHelper.AddSessionCommissionAsync(db, storeId, balance, sessionTransactionId, 1,
            employeeId, trainer.GymTrainerName, performedAtUtc, actor);
    }
}
