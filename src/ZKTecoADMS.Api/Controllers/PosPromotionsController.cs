using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Helpers;
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
        List<Guid>? ResolvedProductIds = null, List<Guid>? BranchIds = null);

    public record PromotionSaveDto(
        string Name, string Type, int Priority, bool Stackable,
        DateTime? ValidFrom, DateTime? ValidTo, int DaysOfWeekMask,
        int? TimeFromMinutes, int? TimeToMinutes, bool MembersOnly,
        string? ConfigJson, string? Note, bool IsActive = true, List<Guid>? BranchIds = null);

    static PromotionDto Map(PosPromotion p, List<Guid>? resolved = null) => new(
        p.Id, p.Name, p.Type, p.Priority, p.Stackable, p.ValidFrom, p.ValidTo, p.DaysOfWeekMask,
        p.TimeFromMinutes, p.TimeToMinutes, p.MembersOnly, p.ConfigJson, p.Note, p.IsActive, p.CreatedAt, resolved,
        ParseBranchIds(p.BranchIdsJson));

    internal static List<Guid>? ParseBranchIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            var list = JsonNode.Parse(json) is JsonArray arr
                ? arr.Select(n => Guid.TryParse(n?.ToString(), out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).Distinct().ToList()
                : [];
            return list.Count == 0 ? null : list;
        }
        catch (JsonException) { return null; }
    }

    /// <summary>Chương trình áp ở chi nhánh này không (null / rỗng = mọi chi nhánh).</summary>
    internal static bool AppliesToBranch(PosPromotion p, Guid? branchId)
    {
        var ids = ParseBranchIds(p.BranchIdsJson);
        return ids == null || (branchId.HasValue && ids.Contains(branchId.Value));
    }

    [HttpGet]
    [RequireModulePermission("PosPromotions", ModulePermissionAction.View)]
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
        // Cửa hàng có chi nhánh: chỉ chương trình áp cho chi nhánh đang bán (rỗng = mọi chi nhánh).
        var bctx = HttpContext.BranchContext();
        if (bctx is { StoreUsesBranches: true })
            rows = rows.Where(p => AppliesToBranch(p, bctx.CurrentBranchId)).ToList();
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
            if (JsonNode.Parse(string.IsNullOrWhiteSpace(dto.ConfigJson) ? "{}" : dto.ConfigJson) is not JsonObject cfg)
                return "Cấu hình khuyến mãi không hợp lệ";
            if (PercentOutOfRange(cfg)) return "Mức giảm % không được quá 100%";
        }
        catch (JsonException) { return "Cấu hình khuyến mãi không hợp lệ"; }
        return null;
    }

    /// <summary>
    /// % giảm &gt; 100 (gõ nhầm 150) — bộ máy khuyến mãi cắt còn 100% = cho không mọi mặt hàng khớp.
    /// Xét các khóa % ở cấp gốc và trong bậc «tiers».
    /// </summary>
    internal static bool PercentOutOfRange(JsonObject cfg)
    {
        static bool Bad(JsonNode? n) =>
            n is JsonValue v && v.TryGetValue<decimal>(out var d) && (d < 0 || d > 100);
        foreach (var k in new[] { "percent", "giftPercent", "billPercent" })
            if (Bad(cfg[k])) return true;
        return cfg["tiers"] is JsonArray tiers
               && tiers.Any(t => t is JsonObject o && Bad(o["percent"]));
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
        p.BranchIdsJson = dto.BranchIds is { Count: > 0 }
            ? JsonSerializer.Serialize(dto.BranchIds.Where(g => g != Guid.Empty).Distinct().Select(g => g.ToString()))
            : null;
    }

    [HttpPost]
    [RequireModulePermission("PosPromotions", ModulePermissionAction.Create)]
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
    [RequireModulePermission("PosPromotions", ModulePermissionAction.Edit)]
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
    [RequireModulePermission("PosPromotions", ModulePermissionAction.Delete)]
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

    /// <summary>
    /// Hiệu quả khuyến mãi theo kỳ (hóa đơn hoàn thành, ngày bán giờ VN, chỉ chi nhánh được xem):
    /// từng chương trình (hóa đơn, tiền giảm, doanh thu, tỷ lệ giảm), tỷ lệ hóa đơn có KM, hóa đơn bình quân
    /// có / không KM, diễn biến theo ngày, so với kỳ trước liền kề, và chương trình chưa phát sinh trong kỳ.
    /// </summary>
    [HttpGet("report")]
    [RequireModulePermission("PosPromotions", ModulePermissionAction.View)]
    // Người không có quyền «Xem giá vốn & lợi nhuận» không thấy giá vốn / lãi của chương trình.
    [MaskCostData("promoCogs", "promoProfit", "promoMarginPct", "normalMarginPct")]
    public async Task<ActionResult<AppResponse<object>>> Report([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var fromVn = (from ?? todayVn.AddDays(-29)).Date;
        var toVn = (to ?? todayVn).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        if ((toVn - fromVn).TotalDays > 366) fromVn = toVn.AddDays(-366);
        var days = (int)(toVn - fromVn).TotalDays + 1;

        async Task<List<(Guid Id, DateTime At, decimal Total, string? Json)>> LoadAsync(DateTime fVn, DateTime tVn)
        {
            var fUtc = fVn.AddHours(-7);
            var tUtc = tVn.AddDays(1).AddHours(-7);
            var rows = await dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= fUtc && (o.SaleDate ?? o.CreatedAt) < tUtc)
                .ApplyBranchScope(HttpContext.BranchContext())
                .Select(o => new { o.Id, At = o.SaleDate ?? o.CreatedAt, o.Total, o.PromotionsJson })
                .ToListAsync();
            return rows.Select(o => (o.Id, o.At, o.Total, o.PromotionsJson)).ToList();
        }

        var orders = await LoadAsync(fromVn, toVn);
        var prevOrders = await LoadAsync(fromVn.AddDays(-days), fromVn.AddDays(-1));

        var promoOrderIds = orders.Where(o => ParseApplied(o.Json).Count > 0).Select(o => o.Id).ToList();
        var cogsByOrder = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, promoOrderIds);
        var allCogsByOrder = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, orders.Select(o => o.Id).ToList());

        var agg = new Dictionary<string, (string Name, int Orders, decimal Discount, decimal Revenue, decimal Cogs)>();
        var byDay = new SortedDictionary<DateTime, (int Orders, decimal Discount)>();
        decimal promoRevenue = 0, promoDiscount = 0, promoCogs = 0;
        var promoOrders = 0;
        foreach (var o in orders)
        {
            var applied = ParseApplied(o.Json);
            if (applied.Count == 0) continue;
            promoOrders++;
            promoRevenue += o.Total;
            var orderCogs = cogsByOrder.GetValueOrDefault(o.Id);
            promoCogs += orderCogs;
            var orderDiscount = applied.Sum(a => Math.Max(0, a.Amount));
            promoDiscount += orderDiscount;
            var day = VnTimeHelper.UtcToVn(o.At).Date;
            byDay[day] = byDay.TryGetValue(day, out var d) ? (d.Orders + 1, d.Discount + orderDiscount) : (1, orderDiscount);
            foreach (var (id, name, amount) in applied)
            {
                var cur = agg.TryGetValue(id, out var v) ? v : (Name: name, Orders: 0, Discount: 0m, Revenue: 0m, Cogs: 0m);
                agg[id] = (string.IsNullOrEmpty(cur.Name) ? name : cur.Name, cur.Orders + 1, cur.Discount + amount, cur.Revenue + o.Total, cur.Cogs + orderCogs);
            }
        }

        var prevPromo = prevOrders.Select(o => (o, applied: ParseApplied(o.Json))).Where(x => x.applied.Count > 0).ToList();

        var items = agg.Select(kv => new
            {
                promotionId = kv.Key, name = kv.Value.Name, orders = kv.Value.Orders,
                discount = kv.Value.Discount, revenue = kv.Value.Revenue,
                // Tỷ lệ giảm trên giá trị hàng trước khuyến mãi của các hóa đơn có áp chương trình.
                discountRate = kv.Value.Revenue + kv.Value.Discount > 0
                    ? Math.Round(kv.Value.Discount / (kv.Value.Revenue + kv.Value.Discount) * 100, 1) : 0m,
                avgBill = kv.Value.Orders > 0 ? Math.Round(kv.Value.Revenue / kv.Value.Orders) : 0m,
                cogs = kv.Value.Cogs,
                profit = kv.Value.Revenue - kv.Value.Cogs,
                marginPct = kv.Value.Revenue > 0 ? Math.Round((kv.Value.Revenue - kv.Value.Cogs) / kv.Value.Revenue * 100, 1) : 0m,
            })
            .OrderByDescending(x => x.discount)
            .ToList();

        // Chương trình chưa phát sinh hóa đơn nào trong kỳ (để biết chương trình nào không hiệu quả / chưa ai dùng).
        var usedIds = agg.Keys.Select(k => Guid.TryParse(k, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).ToHashSet();
        var unused = (await dbContext.PosPromotions.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => new { p.Id, p.Name, p.Type, p.IsActive, p.ValidFrom, p.ValidTo })
                .ToListAsync())
            .Where(p => !usedIds.Contains(p.Id))
            .OrderByDescending(p => p.IsActive).ThenBy(p => p.Name)
            .Select(p => new { promotionId = p.Id, name = p.Name, type = p.Type, isActive = p.IsActive, validFrom = p.ValidFrom, validTo = p.ValidTo })
            .ToList();

        var allRevenue = orders.Sum(o => o.Total);
        var normalOrders = orders.Count - promoOrders;
        var normalRevenue = allRevenue - promoRevenue;
        object Daily() => Enumerable.Range(0, days).Select(i =>
        {
            var d = fromVn.AddDays(i);
            var v = byDay.TryGetValue(d, out var x) ? x : (Orders: 0, Discount: 0m);
            return new { date = d, orders = v.Orders, discount = v.Discount };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn, to = toVn, items,
            totalDiscount = promoDiscount,
            orders = promoOrders,
            allOrders = orders.Count,
            allRevenue,
            promoRevenue,
            // % hóa đơn có áp khuyến mãi / % tiền giảm trên giá trị hàng trước giảm.
            promoOrderRate = orders.Count > 0 ? Math.Round(promoOrders * 100m / orders.Count, 1) : 0m,
            discountRate = promoRevenue + promoDiscount > 0 ? Math.Round(promoDiscount / (promoRevenue + promoDiscount) * 100, 1) : 0m,
            avgBillPromo = promoOrders > 0 ? Math.Round(promoRevenue / promoOrders) : 0m,
            // Lãi gộp (sau khi đã trừ khuyến mãi) của hóa đơn có KM so với hóa đơn không KM.
            promoCogs,
            promoProfit = promoRevenue - promoCogs,
            promoMarginPct = promoRevenue > 0 ? Math.Round((promoRevenue - promoCogs) / promoRevenue * 100, 1) : 0m,
            normalMarginPct = normalRevenue > 0
                ? Math.Round((normalRevenue - (allCogsByOrder.Values.Sum() - promoCogs)) / normalRevenue * 100, 1) : 0m,
            avgBillNormal = normalOrders > 0 ? Math.Round(normalRevenue / normalOrders) : 0m,
            previous = new
            {
                orders = prevPromo.Count,
                totalDiscount = prevPromo.Sum(x => x.applied.Sum(a => Math.Max(0, a.Amount))),
                allOrders = prevOrders.Count,
            },
            byDay = Daily(),
            unused,
        }));
    }

    /// <summary>Hóa đơn đã áp một chương trình trong kỳ (bấm từ báo cáo hiệu quả để xem từng hóa đơn).</summary>
    [HttpGet("report/orders")]
    [RequireModulePermission("PosPromotions", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ReportOrders(
        [FromQuery] Guid promotionId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var fromVn = (from ?? todayVn.AddDays(-29)).Date;
        var toVn = (to ?? todayVn).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        if ((toVn - fromVn).TotalDays > 366) fromVn = toVn.AddDays(-366);
        var fromUtc = fromVn.AddHours(-7);
        var toUtc = toVn.AddDays(1).AddHours(-7);
        var idText = promotionId.ToString();
        var rows = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed &&
                        o.PromotionsJson != null && o.PromotionsJson.Contains(idText) &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc)
            .ApplyBranchScope(HttpContext.BranchContext())
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Select(o => new { o.Id, o.OrderNo, At = o.SaleDate ?? o.CreatedAt, o.Total, o.CustomerName, o.PaymentMethod, o.PromotionsJson })
            .Take(500)
            .ToListAsync();
        var items = rows
            .Select(o => new
            {
                id = o.Id, orderNo = o.OrderNo, at = VnTimeHelper.UtcToVn(o.At), total = o.Total,
                customerName = o.CustomerName, paymentMethod = o.PaymentMethod,
                discount = ParseApplied(o.PromotionsJson).Where(a => a.Id == idText).Sum(a => Math.Max(0, a.Amount)),
            })
            .Where(o => o.discount > 0)
            .ToList();
        return Ok(AppResponse<object>.Success(new { items, totalDiscount = items.Sum(i => i.discount), count = items.Count }));
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

    /// <summary>
    /// Như [Sanitize] nhưng chỉ giữ chương trình có thật của cửa hàng này (máy bán gửi id lạ / của cửa hàng khác
    /// sẽ làm sai báo cáo hiệu quả) — tên lấy theo chương trình trên máy chủ.
    /// </summary>
    static readonly JsonSerializerOptions Plain = new() { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    internal static async Task<(string? Json, decimal Total)> SanitizeForStoreAsync(
        ZKTecoDbContext db, Guid storeId, string? json)
    {
        var applied = ParseApplied(json);
        if (applied.Count == 0) return (null, 0);
        var ids = applied.Select(a => Guid.TryParse(a.Id, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).Distinct().ToList();
        var known = ids.Count == 0
            ? new Dictionary<Guid, string>()
            : await db.PosPromotions.AsNoTracking()
                .Where(p => p.StoreId == storeId && ids.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.Name);
        var valid = applied
            .Where(a => Guid.TryParse(a.Id, out var g) && known.ContainsKey(g) && a.Amount > 0)
            .Select(a => new JsonObject { ["id"] = a.Id, ["name"] = known[Guid.Parse(a.Id)], ["amount"] = a.Amount })
            .ToList();
        if (valid.Count == 0) return (null, 0);
        // Giữ nguyên các phần khác (chi tiết theo dòng, giảm hóa đơn) nếu còn hợp lệ và không quá dài.
        JsonNode? root;
        try { root = JsonNode.Parse(json!); } catch (JsonException) { root = null; }
        if (root is JsonObject obj && json!.Length <= 20000)
        {
            obj["applied"] = new JsonArray(valid.Select(v => (JsonNode)v).ToArray());
            return (obj.ToJsonString(Plain), valid.Sum(v => v["amount"]!.GetValue<decimal>()));
        }
        var slim = new JsonObject { ["applied"] = new JsonArray(valid.Select(v => (JsonNode)v).ToArray()) };
        return (slim.ToJsonString(Plain), valid.Sum(v => v["amount"]!.GetValue<decimal>()));
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
