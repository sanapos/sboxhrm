using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosCustomersController
{
    public sealed record TiersSaveDto(List<PosCustomerTiers.Tier?>? Tiers);

    async Task<List<PosCustomerTiers.Tier>> LoadTiersAsync(Guid storeId) =>
        PosCustomerTiers.Parse(await dbContext.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.LoyaltyTiersJson)
            .FirstOrDefaultAsync());

    /// <summary>Hạng thành viên + số khách (đang hoạt động) mỗi hạng.</summary>
    [HttpGet("tiers")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetTiers()
    {
        var storeId = RequiredStoreId;
        var tiers = await LoadTiersAsync(storeId);
        var active = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive);
        var items = new List<object>();
        for (var i = 0; i < tiers.Count; i++)
        {
            var (from, to) = PosCustomerTiers.Range(tiers, i);
            var count = await active.CountAsync(c => c.TotalPurchase >= from && (to == null || c.TotalPurchase < to));
            items.Add(new { tiers[i].Name, tiers[i].MinSpend, tiers[i].Color, tiers[i].Benefit, customerCount = count });
        }
        var noTier = tiers.Count == 0 ? 0 : await active.CountAsync(c => c.TotalPurchase < tiers[0].MinSpend);
        return Ok(AppResponse<object>.Success(new { tiers = items, noTierCount = noTier }));
    }

    /// <summary>Lưu hạng thành viên (cùng quyền với thiết lập tích điểm).</summary>
    [HttpPut("tiers")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosSell", "SettingsHub")]
    public async Task<ActionResult<AppResponse<object>>> SaveTiers([FromBody] TiersSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var tiers = PosCustomerTiers.Normalize(dto.Tiers ?? []);
        var err = PosCustomerTiers.Validate(tiers);
        if (err != null) return BadRequest(AppResponse<object>.Fail(err));

        var s = await dbContext.PosStoreSellSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = storeId, CreatedBy = CurrentUserEmail };
            dbContext.PosStoreSellSettings.Add(s);
        }
        s.LoyaltyTiersJson = tiers.Count == 0 ? null : PosCustomerTiers.Serialize(tiers);
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return await GetTiers();
    }
}
