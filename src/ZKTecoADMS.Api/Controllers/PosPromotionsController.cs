using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Chương trình khuyến mãi tự áp ở màn bán. Engine tính tiền giảm chạy trên máy bán
/// (pos_promotion_engine.dart); server lưu cấu hình, trả danh sách đang hiệu lực
/// (kèm danh sách hàng cận hạn đã tính sẵn) và tổng hợp hiệu quả từ PosSaleOrders.PromotionsJson.
/// </summary>
[ApiController]
[Route("api/pos/promotions")]
[Authorize]
public class PosPromotionsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    internal static readonly string[] Types =
        ["time_discount", "qty_discount", "buy_x_get_y", "combo_price", "bill_discount", "addon_price", "near_expiry"];

    public record PromotionDto(
        Guid Id, string Name, string Type, int Priority, bool Stackable,
        DateTime? ValidFrom, DateTime? ValidTo, int DaysOfWeekMask,
        int? TimeFromMinutes, int? TimeToMinutes, bool MembersOnly,
        string ConfigJson, string? Note, bool IsActive, DateTime CreatedAt,
        List<Guid>? ResolvedProductIds = null);

    public record PromotionSaveDto(
        string Name, string Type, int Priority, bool Stackable,
        DateTime? ValidFrom, DateTime? ValidTo, int DaysOfWeekMask,
        int? TimeFromMinutes, int? TimeToMinutes, bool MembersOnly,
        string? ConfigJson, string? Note, bool IsActive = true);

    static PromotionDto Map(PosPromotion p, List<Guid>? resolved = null) => new(
        p.Id, p.Name, p.Type, p.Priority, p.Stackable, p.ValidFrom, p.ValidTo, p.DaysOfWeekMask,
        p.TimeFromMinutes, p.TimeToMinutes, p.MembersOnly, p.ConfigJson, p.Note, p.IsActive, p.CreatedAt, resolved);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PromotionDto>>>> List()
    {
        var storeId = RequiredStoreId;
        var rows = await dbContext.PosPromotions.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .OrderByDescending(p => p.IsActive).ThenByDescending(p => p.Priority).ThenByDescending(p => p.CreatedAt)
            .ToListAsync();
        return Ok(AppResponse<List<PromotionDto>>.Success(rows.Select(p => Map(p)).ToList()));
    }

    /// <summary>Khuyến mãi đang hiệu lực hôm nay (giờ VN) cho màn bán — khung giờ / thứ do máy bán xét theo giờ hiện tại.</summary>
    [HttpGet("active")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PromotionDto>>>> Active()
    {
        var storeId = RequiredStoreId;
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        var rows = await dbContext.PosPromotions.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        (p.ValidFrom == null || p.ValidFrom <= today) &&
                        (p.ValidTo == null || p.ValidTo >= today))
            .OrderByDescending(p => p.Priority)
            .ToListAsync();
        var result = new List<PromotionDto>();
        foreach (var p in rows)
        {
            List<Guid>? resolved = null;
            if (p.Type == "near_expiry")
                resolved = await NearExpiryProductIdsAsync(storeId, ReadInt(p.ConfigJson, "nearExpiryDays", 3));
            result.Add(Map(p, resolved));
        }
        return Ok(AppResponse<List<PromotionDto>>.Success(result));
    }

    /// <summary>Hàng có lô còn hạn gần nhất (lô sẽ bán trước theo FEFO) hết hạn trong vòng N ngày.</summary>
    internal async Task<List<Guid>> NearExpiryProductIdsAsync(Guid storeId, int days)
    {
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        var until = today.AddDays(Math.Clamp(days, 0, 365));
        return await dbContext.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        l.ExpiryDate != null && l.ExpiryDate >= today)
            .GroupBy(l => l.ProductId)
            .Where(g => g.Min(l => l.ExpiryDate) <= until)
            .Select(g => g.Key)
            .ToListAsync();
    }

    static int ReadInt(string json, string key, int fallback)
    {
        try
        {
            var node = JsonNode.Parse(json);
            return node?[key]?.GetValue<int>() ?? fallback;
        }
        catch { return fallback; }
    }

    string? Validate(PromotionSaveDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name)) return "Nhập tên chương trình";
        if (!Types.Contains(dto.Type)) return "Loại khuyến mãi không hợp lệ";
        if (dto.ValidFrom.HasValue && dto.ValidTo.HasValue && dto.ValidTo < dto.ValidFrom) return "Ngày kết thúc trước ngày bắt đầu";
        if (dto.TimeFromMinutes is < 0 or > 1440 || dto.TimeToMinutes is < 0 or > 1440) return "Khung giờ không hợp lệ";
        try
        {
            if (JsonNode.Parse(string.IsNullOrWhiteSpace(dto.ConfigJson) ? "{}" : dto.ConfigJson) is not JsonObject)
                return "Cấu hình khuyến mãi không hợp lệ";
        }
        catch (JsonException) { return "Cấu hình khuyến mãi không hợp lệ"; }
        return null;
    }

    static void Apply(PosPromotion p, PromotionSaveDto dto)
    {
        p.Name = dto.Name.Trim();
        p.Type = dto.Type;
        p.Priority = dto.Priority;
        p.Stackable = dto.Stackable;
        p.ValidFrom = dto.ValidFrom?.Date;
        p.ValidTo = dto.ValidTo?.Date;
        p.DaysOfWeekMask = dto.DaysOfWeekMask & 0x7F;
        p.TimeFromMinutes = dto.TimeFromMinutes;
        p.TimeToMinutes = dto.TimeToMinutes;
        p.MembersOnly = dto.MembersOnly;
        p.ConfigJson = string.IsNullOrWhiteSpace(dto.ConfigJson) ? "{}" : dto.ConfigJson;
        p.Note = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim();
        p.IsActive = dto.IsActive;
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PromotionDto>>> Create([FromBody] PromotionSaveDto dto)
    {
        var err = Validate(dto);
        if (err != null) return BadRequest(AppResponse<PromotionDto>.Fail(err));
        var p = new PosPromotion { Id = Guid.NewGuid(), StoreId = RequiredStoreId, CreatedBy = CurrentUserEmail };
        Apply(p, dto);
        dbContext.PosPromotions.Add(p);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<PromotionDto>.Success(Map(p)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PromotionDto>>> Update(Guid id, [FromBody] PromotionSaveDto dto)
    {
        var err = Validate(dto);
        if (err != null) return BadRequest(AppResponse<PromotionDto>.Fail(err));
        var storeId = RequiredStoreId;
        var p = await dbContext.PosPromotions.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return NotFound(AppResponse<PromotionDto>.Fail("Không tìm thấy chương trình"));
        Apply(p, dto);
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<PromotionDto>.Success(Map(p)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var p = await dbContext.PosPromotions.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy chương trình"));
        p.Deleted = DateTime.UtcNow;
        p.DeletedBy = CurrentUserEmail;
        p.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Hiệu quả: số hóa đơn, tiền giảm, doanh thu các hóa đơn có áp từng chương trình (hóa đơn hoàn thành, theo ngày bán VN).</summary>
    [HttpGet("report")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Report([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var fromVn = (from ?? todayVn.AddDays(-29)).Date;
        var toVn = (to ?? todayVn).Date;
        if ((toVn - fromVn).TotalDays > 366) fromVn = toVn.AddDays(-366);
        var fromUtc = fromVn.AddHours(-7);
        var toUtc = toVn.AddDays(1).AddHours(-7);

        var orders = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed &&
                        o.PromotionsJson != null &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc)
            .Select(o => new { o.PromotionsJson, o.Total })
            .ToListAsync();

        var agg = new Dictionary<string, (string Name, int Orders, decimal Discount, decimal Revenue)>();
        foreach (var o in orders)
        {
            foreach (var (id, name, amount) in ParseApplied(o.PromotionsJson))
            {
                var cur = agg.TryGetValue(id, out var v) ? v : (Name: name, Orders: 0, Discount: 0m, Revenue: 0m);
                agg[id] = (string.IsNullOrEmpty(cur.Name) ? name : cur.Name, cur.Orders + 1, cur.Discount + amount, cur.Revenue + o.Total);
            }
        }
        var items = agg.Select(kv => new
            {
                promotionId = kv.Key, name = kv.Value.Name, orders = kv.Value.Orders,
                discount = kv.Value.Discount, revenue = kv.Value.Revenue,
            })
            .OrderByDescending(x => x.discount)
            .ToList();
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn, to = toVn, items,
            totalDiscount = items.Sum(i => i.discount),
            orders = orders.Count,
        }));
    }

    /// <summary>Đọc {"applied":[{"id","name","amount"}],...} — bỏ qua JSON hỏng.</summary>
    internal static List<(string Id, string Name, decimal Amount)> ParseApplied(string? json)
    {
        var list = new List<(string, string, decimal)>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            if (JsonNode.Parse(json)?["applied"] is not JsonArray arr) return list;
            foreach (var n in arr)
            {
                var id = n?["id"]?.ToString();
                if (string.IsNullOrEmpty(id)) continue;
                decimal amount = 0;
                try { amount = n!["amount"]?.GetValue<decimal>() ?? 0; } catch { }
                list.Add((id, n!["name"]?.ToString() ?? "", amount));
            }
        }
        catch (JsonException) { }
        return list;
    }

    /// <summary>Chuẩn hóa JSON khuyến mãi gửi từ máy bán; trả (json, tổng tiền giảm) hoặc (null, 0).</summary>
    internal static (string? Json, decimal Total) Sanitize(string? json)
    {
        var applied = ParseApplied(json);
        if (applied.Count == 0) return (null, 0);
        var total = applied.Sum(a => Math.Max(0, a.Amount));
        if (json!.Length <= 20000) return (json, total);
        // Quá dài → chỉ giữ danh sách chương trình đã áp (đủ cho báo cáo).
        var slim = new JsonObject
        {
            ["applied"] = new JsonArray(applied.Select(a => (JsonNode)new JsonObject
            {
                ["id"] = a.Id, ["name"] = a.Name, ["amount"] = a.Amount,
            }).ToArray()),
        };
        return (slim.ToJsonString(), total);
    }
}
