using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>Mức sử dụng của 1 ca mẫu: dữ liệu đã phát sinh (chặn xóa) và cấu hình đang gắn (gỡ khi xóa).</summary>
public sealed class ShiftTemplateUsage
{
    public Guid ShiftId { get; init; }

    // Dữ liệu đã phát sinh
    public int Schedules { get; set; }
    public int UpcomingSchedules { get; set; }
    public int Registrations { get; set; }
    public int Leaves { get; set; }
    public int Swaps { get; set; }
    public int Penalties { get; set; }
    public int Meals { get; set; }
    public int Employees { get; set; }
    public DateTime? LastUsedDate { get; set; }

    // Cấu hình (gỡ khi xóa ca)
    public int SalaryLevels { get; set; }
    public int Allowances { get; set; }
    public int StaffingQuotas { get; set; }
    public int MealSessions { get; set; }

    public bool HasData => Schedules + Registrations + Leaves + Swaps + Penalties + Meals > 0;
    public bool HasConfig => SalaryLevels + Allowances + StaffingQuotas + MealSessions > 0;
}

public static class ShiftTemplateUsageHelper
{
    static DateTime VnToday => DateTime.UtcNow.AddHours(7).Date;

    /// <summary>Phân tích JSON mảng id ca của phụ cấp (bỏ qua giá trị hỏng).</summary>
    public static List<string> ParseShiftIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<JsonElement>>(json)?
                .Select(e => e.ValueKind == JsonValueKind.String ? e.GetString() ?? "" : e.ToString())
                .Where(s => !string.IsNullOrWhiteSpace(s)).ToList() ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <summary>Bỏ 1 ca khỏi JSON mảng id ca; null nếu không còn ca nào. Trả lại nguyên bản nếu không chứa ca đó.</summary>
    public static (bool changed, string? json) RemoveShiftId(string? json, Guid shiftId)
    {
        var ids = ParseShiftIds(json);
        var kept = ids.Where(s => !(Guid.TryParse(s, out var g) && g == shiftId)).ToList();
        if (kept.Count == ids.Count) return (false, json);
        return (true, kept.Count == 0 ? null : JsonSerializer.Serialize(kept));
    }

    /// <summary>Mức sử dụng của mọi ca trong cửa hàng (hoặc 1 ca).</summary>
    public static async Task<Dictionary<Guid, ShiftTemplateUsage>> ComputeAsync(
        ZKTecoDbContext db, Guid storeId, Guid? onlyShiftId = null, CancellationToken ct = default)
    {
        var shiftIds = await db.ShiftTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && (onlyShiftId == null || t.Id == onlyShiftId))
            .Select(t => t.Id).ToListAsync(ct);
        var map = shiftIds.ToDictionary(id => id, id => new ShiftTemplateUsage { ShiftId = id });
        if (map.Count == 0) return map;
        var today = VnToday;

        var sched = await db.WorkSchedules.AsNoTracking()
            .Where(s => s.ShiftId != null && shiftIds.Contains(s.ShiftId.Value))
            .GroupBy(s => s.ShiftId!.Value)
            .Select(g => new
            {
                g.Key,
                Count = g.Count(),
                Upcoming = g.Count(x => x.Date >= today),
                Emps = g.Select(x => x.EmployeeUserId).Distinct().Count(),
                Last = g.Max(x => (DateTime?)x.Date),
            }).ToListAsync(ct);
        foreach (var r in sched)
        {
            var u = map[r.Key];
            u.Schedules = r.Count;
            u.UpcomingSchedules = r.Upcoming;
            u.Employees = r.Emps;
            u.LastUsedDate = r.Last;
        }

        foreach (var r in await db.ScheduleRegistrations.AsNoTracking()
                     .Where(s => s.ShiftId != null && shiftIds.Contains(s.ShiftId.Value))
                     .GroupBy(s => s.ShiftId!.Value).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].Registrations = r.C;

        // Khóa ngoại bắt buộc: tính cả bản ghi đã xóa tạm (vẫn giữ liên kết trong CSDL).
        foreach (var r in await db.Leaves.IgnoreQueryFilters().AsNoTracking()
                     .Where(s => s.StoreId == storeId && shiftIds.Contains(s.ShiftId))
                     .GroupBy(s => s.ShiftId).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].Leaves = r.C;

        var swaps = await db.ShiftSwapRequests.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.StoreId == storeId && (shiftIds.Contains(s.RequesterShiftId) || shiftIds.Contains(s.TargetShiftId)))
            .Select(s => new { s.RequesterShiftId, s.TargetShiftId }).ToListAsync(ct);
        foreach (var s in swaps)
        {
            if (map.TryGetValue(s.RequesterShiftId, out var a)) a.Swaps++;
            if (s.TargetShiftId != s.RequesterShiftId && map.TryGetValue(s.TargetShiftId, out var b)) b.Swaps++;
        }

        foreach (var r in await db.PenaltyTickets.AsNoTracking()
                     .Where(s => s.ShiftId != null && shiftIds.Contains(s.ShiftId.Value))
                     .GroupBy(s => s.ShiftId!.Value).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].Penalties = r.C;

        foreach (var r in await db.MealRecords.AsNoTracking()
                     .Where(s => s.ShiftId != null && shiftIds.Contains(s.ShiftId.Value))
                     .GroupBy(s => s.ShiftId!.Value).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].Meals = r.C;

        // Cấu hình
        foreach (var r in await db.ShiftSalaryLevels.AsNoTracking()
                     .Where(s => shiftIds.Contains(s.ShiftTemplateId))
                     .GroupBy(s => s.ShiftTemplateId).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].SalaryLevels = r.C;

        foreach (var r in await db.ShiftStaffingQuotas.AsNoTracking()
                     .Where(s => shiftIds.Contains(s.ShiftTemplateId))
                     .GroupBy(s => s.ShiftTemplateId).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].StaffingQuotas = r.C;

        foreach (var r in await db.MealSessionShifts.AsNoTracking()
                     .Where(s => shiftIds.Contains(s.ShiftTemplateId))
                     .GroupBy(s => s.ShiftTemplateId).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct))
            map[r.Key].MealSessions = r.C;

        var allowanceJson = await db.Allowances.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.ShiftIds != null && a.ShiftIds != "" && a.ShiftIds != "[]")
            .Select(a => a.ShiftIds).ToListAsync(ct);
        foreach (var json in allowanceJson)
            foreach (var s in ParseShiftIds(json).Distinct())
                if (Guid.TryParse(s, out var g) && map.TryGetValue(g, out var u)) u.Allowances++;

        return map;
    }

    /// <summary>
    /// Xóa ca chưa phát sinh dữ liệu: gỡ ca khỏi thiết lập lương (mức lương ca, phụ cấp theo ca),
    /// định mức nhân sự, suất ăn theo ca rồi xóa. Ca đã có dữ liệu → trả lỗi, gợi ý «Ngừng dùng».
    /// </summary>
    public static async Task<(bool ok, string? error, ShiftTemplateUsage? usage)> DeleteAsync(
        ZKTecoDbContext db, Guid storeId, Guid shiftId, CancellationToken ct = default)
    {
        var tpl = await db.ShiftTemplates.AsTracking().FirstOrDefaultAsync(t => t.Id == shiftId && t.StoreId == storeId, ct);
        if (tpl == null) return (false, "Không tìm thấy ca", null);
        var usage = (await ComputeAsync(db, storeId, shiftId, ct)).GetValueOrDefault(shiftId) ?? new ShiftTemplateUsage { ShiftId = shiftId };
        if (usage.HasData)
            return (false, $"Ca \"{tpl.Name}\" đã phát sinh dữ liệu ({Describe(usage)}). Không xóa được — hãy chuyển sang Ngừng dùng để giữ lịch sử chấm công, lương.", usage);

        var strategy = db.Database.CreateExecutionStrategy();
        await strategy.ExecuteAsync(async () =>
        {
            await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;

            // Phụ cấp theo ca: bỏ id ca khỏi danh sách.
            var allowances = await db.Allowances.AsTracking()
                .Where(a => a.StoreId == storeId && a.ShiftIds != null && a.ShiftIds != "" && a.ShiftIds != "[]")
                .ToListAsync(ct);
            foreach (var a in allowances)
            {
                var (changed, json) = RemoveShiftId(a.ShiftIds, shiftId);
                if (changed) a.ShiftIds = json;
            }

            // Bản ghi đã xóa tạm còn trỏ tới ca (cột cho phép trống) → gỡ liên kết để xóa được ca.
            if (db.Database.IsRelational())
            {
                await db.WorkSchedules.IgnoreQueryFilters().Where(s => s.ShiftId == shiftId)
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.ShiftId, (Guid?)null), ct);
                await db.ScheduleRegistrations.IgnoreQueryFilters().Where(s => s.ShiftId == shiftId)
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.ShiftId, (Guid?)null), ct);
                await db.PenaltyTickets.IgnoreQueryFilters().Where(s => s.ShiftId == shiftId)
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.ShiftId, (Guid?)null), ct);
                await db.MealRecords.IgnoreQueryFilters().Where(s => s.ShiftId == shiftId)
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.ShiftId, (Guid?)null), ct);
                await db.EmployeeLocationPoints.IgnoreQueryFilters().Where(s => s.ShiftId == shiftId)
                    .ExecuteUpdateAsync(s => s.SetProperty(x => x.ShiftId, (Guid?)null), ct);
                // Cấu hình gắn theo ca: xóa hẳn (kể cả bản đã xóa tạm).
                await db.ShiftSalaryLevels.IgnoreQueryFilters().Where(s => s.ShiftTemplateId == shiftId).ExecuteDeleteAsync(ct);
                await db.ShiftStaffingQuotas.IgnoreQueryFilters().Where(s => s.ShiftTemplateId == shiftId).ExecuteDeleteAsync(ct);
                await db.MealSessionShifts.IgnoreQueryFilters().Where(s => s.ShiftTemplateId == shiftId).ExecuteDeleteAsync(ct);
            }
            else
            {
                db.ShiftSalaryLevels.RemoveRange(await db.ShiftSalaryLevels.AsTracking().Where(s => s.ShiftTemplateId == shiftId).ToListAsync(ct));
                db.MealSessionShifts.RemoveRange(await db.MealSessionShifts.AsTracking().Where(s => s.ShiftTemplateId == shiftId).ToListAsync(ct));
                foreach (var q in await db.ShiftStaffingQuotas.AsTracking().Where(s => s.ShiftTemplateId == shiftId).ToListAsync(ct))
                    db.Entry(q).State = EntityState.Deleted;
            }

            db.ShiftTemplates.Remove(tpl);
            await db.SaveChangesAsync(ct);
            if (tx != null) await tx.CommitAsync(ct);
        });
        return (true, null, usage);
    }

    public static string Describe(ShiftTemplateUsage u)
    {
        var parts = new List<string>();
        if (u.Schedules > 0) parts.Add($"{u.Schedules} lịch làm việc");
        if (u.Registrations > 0) parts.Add($"{u.Registrations} đăng ký ca");
        if (u.Leaves > 0) parts.Add($"{u.Leaves} đơn nghỉ");
        if (u.Swaps > 0) parts.Add($"{u.Swaps} yêu cầu đổi ca");
        if (u.Penalties > 0) parts.Add($"{u.Penalties} phiếu phạt");
        if (u.Meals > 0) parts.Add($"{u.Meals} lượt chấm cơm");
        return string.Join(", ", parts);
    }

    /// <summary>Tên bản sao không trùng: "Ca sáng (bản sao)", "Ca sáng (bản sao 2)"...</summary>
    public static string CopyName(string name, IReadOnlyCollection<string> existing)
    {
        var set = new HashSet<string>(existing, StringComparer.OrdinalIgnoreCase);
        var candidate = $"{name} (bản sao)";
        for (var i = 2; set.Contains(candidate); i++) candidate = $"{name} (bản sao {i})";
        return candidate;
    }
}
