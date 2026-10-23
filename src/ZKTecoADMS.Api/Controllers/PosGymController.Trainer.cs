using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Gym: PT phụ trách hội viên, phiếu đánh giá thể trạng, báo cáo giờ cao điểm và hội viên.</summary>
public partial class PosGymController
{
    public record TrainerDto(Guid? EmployeeId);

    /// <summary>Gán / bỏ PT phụ trách — PT nhận hoa hồng buổi khi hội viên check-in trừ buổi gói PT.</summary>
    [HttpPut("customers/{customerId:guid}/trainer")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetTrainer(Guid customerId, [FromBody] TrainerDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == customerId && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        string? name = null;
        if (dto.EmployeeId is Guid eid)
        {
            var e = await db.Employees.AsNoTracking()
                .Where(x => x.Id == eid && x.StoreId == storeId && x.Deleted == null)
                .Select(x => new { x.LastName, x.FirstName })
                .FirstOrDefaultAsync();
            if (e == null) return BadRequest(AppResponse<object>.Fail("Không tìm thấy nhân viên"));
            name = $"{e.LastName} {e.FirstName}".Trim();
        }
        c.GymTrainerEmployeeId = dto.EmployeeId;
        c.GymTrainerName = name;
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { employeeId = dto.EmployeeId, name }));
    }

    public record AssessmentDto(
        Guid Id, DateTime AssessedAt, Guid? TrainerEmployeeId, string? TrainerName,
        decimal? WeightKg, decimal? HeightCm, decimal? BodyFatPercent, decimal? MuscleKg, decimal? WaistCm,
        decimal? Bmi, string? Condition, string? Goal,
        decimal? ChestCm, decimal? HipCm, decimal? ArmCm, decimal? ThighCm, int Kind, int? Rating, Guid? VisitId);

    /// <param name="Kind">0 = đo thể trạng; 1 = đánh giá sau buổi tập (Rating 1–5, VisitId).</param>
    public record SaveAssessmentDto(
        DateTime? AssessedAt, Guid? TrainerEmployeeId,
        decimal? WeightKg, decimal? HeightCm, decimal? BodyFatPercent, decimal? MuscleKg, decimal? WaistCm,
        string? Condition, string? Goal,
        decimal? ChestCm = null, decimal? HipCm = null, decimal? ArmCm = null, decimal? ThighCm = null,
        int Kind = 0, int? Rating = null, Guid? VisitId = null);

    static decimal? Bmi(decimal? w, decimal? h) =>
        w is > 0 && h is > 50 ? Math.Round(w.Value / (h.Value / 100m * (h.Value / 100m)), 1) : null;

    static AssessmentDto ToDto(PosGymAssessment a) => new(
        a.Id, a.AssessedAt, a.TrainerEmployeeId, a.TrainerName, a.WeightKg, a.HeightCm, a.BodyFatPercent,
        a.MuscleKg, a.WaistCm, Bmi(a.WeightKg, a.HeightCm), a.Condition, a.Goal,
        a.ChestCm, a.HipCm, a.ArmCm, a.ThighCm, a.Kind, a.Rating, a.VisitId);

    /// <summary>Lịch sử đánh giá thể trạng (mới nhất trước) + PT phụ trách.</summary>
    [HttpGet("customers/{customerId:guid}/assessments")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Assessments(Guid customerId)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosCustomers.AsNoTracking()
            .Where(x => x.Id == customerId && x.StoreId == storeId && x.Deleted == null)
            .Select(x => new { x.Id, x.Name, x.GymTrainerEmployeeId, x.GymTrainerName })
            .FirstOrDefaultAsync();
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        var rows = await db.PosGymAssessments.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.CustomerId == customerId && a.Deleted == null)
            .OrderByDescending(a => a.AssessedAt)
            .Take(200)
            .ToListAsync();
        var plans = await db.PosGymWorkoutPlans.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.CustomerId == customerId && x.Deleted == null)
            .OrderByDescending(x => x.StartDate ?? x.CreatedAt)
            .Take(100)
            .Select(x => new { x.Id, x.Title, x.Content, x.StartDate, x.TrainerName, x.CreatedAt })
            .ToListAsync();
        var shareToken = await db.PosCustomers.AsNoTracking()
            .Where(x => x.Id == customerId).Select(x => x.GymShareToken).FirstOrDefaultAsync();
        return Ok(AppResponse<object>.Success(new
        {
            customerId = c.Id,
            customerName = c.Name,
            trainerEmployeeId = c.GymTrainerEmployeeId,
            trainerName = c.GymTrainerName,
            items = rows.Select(ToDto).ToList(),
            plans,
            sharePath = shareToken == null ? null : $"/o/hv/{shareToken}",
        }));
    }

    [HttpPost("customers/{customerId:guid}/assessments")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AssessmentDto>>> AddAssessment(Guid customerId, [FromBody] SaveAssessmentDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosCustomers.AsNoTracking()
            .Where(x => x.Id == customerId && x.StoreId == storeId && x.Deleted == null)
            .Select(x => new { x.GymTrainerEmployeeId, x.GymTrainerName })
            .FirstOrDefaultAsync();
        if (c == null) return NotFound(AppResponse<AssessmentDto>.Fail("Không tìm thấy khách hàng"));
        if (dto.WeightKg == null && dto.BodyFatPercent == null && dto.MuscleKg == null && dto.WaistCm == null
            && dto.ChestCm == null && dto.HipCm == null && dto.ArmCm == null && dto.ThighCm == null && dto.Rating == null
            && string.IsNullOrWhiteSpace(dto.Condition) && string.IsNullOrWhiteSpace(dto.Goal))
            return BadRequest(AppResponse<AssessmentDto>.Fail("Nhập ít nhất một chỉ số hoặc nhận xét"));
        var trainerId = dto.TrainerEmployeeId ?? c.GymTrainerEmployeeId;
        var trainerName = trainerId == c.GymTrainerEmployeeId ? c.GymTrainerName : null;
        if (trainerId is Guid tid && trainerName == null)
        {
            trainerName = await db.Employees.AsNoTracking()
                .Where(x => x.Id == tid && x.StoreId == storeId)
                .Select(x => (x.LastName + " " + x.FirstName).Trim())
                .FirstOrDefaultAsync();
        }
        static string? Cut(string? s, int n)
        {
            var t = s?.Trim();
            return string.IsNullOrEmpty(t) ? null : t.Length > n ? t[..n] : t;
        }
        var a = new PosGymAssessment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customerId,
            TrainerEmployeeId = trainerId,
            TrainerName = trainerName,
            AssessedAt = dto.AssessedAt?.ToUniversalTime() ?? DateTime.UtcNow,
            WeightKg = dto.WeightKg,
            HeightCm = dto.HeightCm,
            BodyFatPercent = dto.BodyFatPercent,
            MuscleKg = dto.MuscleKg,
            WaistCm = dto.WaistCm,
            ChestCm = dto.ChestCm,
            HipCm = dto.HipCm,
            ArmCm = dto.ArmCm,
            ThighCm = dto.ThighCm,
            Kind = dto.Kind == 1 ? 1 : 0,
            Rating = dto.Rating is int r ? Math.Clamp(r, 1, 5) : null,
            VisitId = dto.VisitId,
            Condition = Cut(dto.Condition, 1000),
            Goal = Cut(dto.Goal, 500),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.PosGymAssessments.Add(a);
        await db.SaveChangesAsync();
        return Ok(AppResponse<AssessmentDto>.Success(ToDto(a)));
    }

    [HttpDelete("assessments/{id:guid}")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> DeleteAssessment(Guid id)
    {
        var storeId = RequiredStoreId;
        var a = await db.PosGymAssessments.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (a == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu đánh giá"));
        a.Deleted = DateTime.UtcNow;
        a.DeletedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    /// <summary>
    /// Giờ cao điểm: lượt vào theo giờ trong ngày (TB / ngày) và theo thứ, số người tập cùng lúc cao nhất
    /// mỗi giờ — để biết cần thêm PT / lễ tân / máy tập khung nào. Kèm tổng quan hội viên.
    /// </summary>
    [HttpGet("traffic")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Traffic([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var nowVn = DateTime.UtcNow.AddHours(7);
        var fromVn = (from ?? nowVn.Date.AddDays(-29)).Date;
        var toVn = (to ?? nowVn.Date).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        var fromUtc = fromVn.AddHours(-7);
        var toUtc = toVn.AddDays(1).AddHours(-7);
        var days = Math.Max(1, (int)(toVn - fromVn).TotalDays + 1);

        var visits = await db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.CheckInAt >= fromUtc && v.CheckInAt < toUtc)
            .Select(v => new { v.CustomerId, v.CheckInAt, v.CheckOutAt, v.DurationMinutes, v.Status })
            .ToListAsync();
        var entered = visits.Where(v => !GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt)).ToList();

        var byHour = new int[24];
        var byWeekday = new int[7]; // 0 = Thứ 2 … 6 = CN
        var weekdayDays = new int[7];
        for (var d = fromVn; d <= toVn; d = d.AddDays(1)) weekdayDays[((int)d.DayOfWeek + 6) % 7]++;
        // Số người có mặt cùng lúc: mỗi lượt chiếm các giờ từ vào đến ra (chưa ra / quên ra → tính 60 phút).
        var presentByDayHour = new Dictionary<(DateTime Day, int Hour), int>();
        foreach (var v in entered)
        {
            var inVn = v.CheckInAt.AddHours(7);
            byHour[inVn.Hour]++;
            byWeekday[((int)inVn.DayOfWeek + 6) % 7]++;
            var mins = v.DurationMinutes is > 0 and < 600 ? v.DurationMinutes.Value
                : v.CheckOutAt is DateTime o && o > v.CheckInAt && (o - v.CheckInAt).TotalMinutes < 600
                    ? Math.Max(1, (int)(o - v.CheckInAt).TotalMinutes) : 60;
            var outVn = inVn.AddMinutes(mins);
            for (var t = new DateTime(inVn.Year, inVn.Month, inVn.Day, inVn.Hour, 0, 0); t < outVn; t = t.AddHours(1))
            {
                var key = (t.Date, t.Hour);
                presentByDayHour[key] = presentByDayHour.GetValueOrDefault(key) + 1;
            }
        }
        var hours = Enumerable.Range(0, 24).Select(h =>
        {
            var present = presentByDayHour.Where(k => k.Key.Hour == h).Select(k => k.Value).ToList();
            return new
            {
                hour = h,
                checkIns = byHour[h],
                avgCheckInsPerDay = Math.Round(byHour[h] / (double)days, 1),
                peakPresent = present.Count == 0 ? 0 : present.Max(),
                avgPresent = Math.Round(present.Sum() / (double)days, 1),
            };
        }).ToList();
        var busiest = hours.OrderByDescending(h => h.peakPresent).ThenByDescending(h => h.checkIns).First();

        // Tổng quan hội viên (theo thẻ / gói còn hạn).
        var now = DateTime.UtcNow;
        var balances = await db.PosCustomerSessionBalances.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.Deleted == null)
            .Select(b => new { b.CustomerId, b.RemainingSessions, b.ExpiresAt, b.CreatedAt, b.PackageName })
            .ToListAsync();
        var live = balances.Where(b => b.RemainingSessions > 0 && (b.ExpiresAt == null || b.ExpiresAt > now)).ToList();
        var activeIds = live.Select(b => b.CustomerId).ToHashSet();
        var firstBuy = balances.GroupBy(b => b.CustomerId).ToDictionary(g => g.Key, g => g.Min(b => b.CreatedAt));
        var lastEnd = balances.GroupBy(b => b.CustomerId)
            .ToDictionary(g => g.Key, g => g.Max(b => b.ExpiresAt ?? DateTime.MaxValue));
        var expiring7 = activeIds.Count(id => lastEnd[id] != DateTime.MaxValue && lastEnd[id] <= now.AddDays(7));
        var lapsed30 = lastEnd.Count(kv => !activeIds.Contains(kv.Key) && kv.Value != DateTime.MaxValue
            && kv.Value > now.AddDays(-30) && kv.Value <= now);
        var byPackage = live
            .GroupBy(b => b.PackageName ?? "")
            .Select(g => new { package = g.Key, members = g.Select(b => b.CustomerId).Distinct().Count() })
            .OrderByDescending(x => x.members).ToList();
        var visitedIds = entered.Select(v => v.CustomerId).ToHashSet();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.ToString("yyyy-MM-dd"),
            to = toVn.ToString("yyyy-MM-dd"),
            days,
            totalCheckIns = entered.Count,
            avgCheckInsPerDay = Math.Round(entered.Count / (double)days, 1),
            busiestHour = busiest.peakPresent == 0 ? (int?)null : busiest.hour,
            busiestPeakPresent = busiest.peakPresent,
            hours,
            weekdays = Enumerable.Range(0, 7).Select(i => new
            {
                weekday = i,
                checkIns = byWeekday[i],
                avgPerDay = weekdayDays[i] == 0 ? 0 : Math.Round(byWeekday[i] / (double)weekdayDays[i], 1),
            }).ToList(),
            members = new
            {
                active = activeIds.Count,
                newInPeriod = firstBuy.Count(kv => kv.Value >= fromUtc && kv.Value < toUtc),
                expiringIn7Days = expiring7,
                lapsedLast30Days = lapsed30,
                visitedInPeriod = visitedIds.Count,
                activeNotVisited = activeIds.Count(id => !visitedIds.Contains(id)),
                byPackage,
            },
        }));
    }

    public record SavePlanDto(string? Title, string? Content, DateTime? StartDate);

    /// <summary>PT giao phác đồ / giáo án tập cho hội viên (hiện trên link chia sẻ).</summary>
    [HttpPost("customers/{customerId:guid}/plans")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> AddPlan(Guid customerId, [FromBody] SavePlanDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosCustomers.AsNoTracking()
            .Where(x => x.Id == customerId && x.StoreId == storeId && x.Deleted == null)
            .Select(x => new { x.GymTrainerEmployeeId, x.GymTrainerName })
            .FirstOrDefaultAsync();
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        var title = dto.Title?.Trim() ?? "";
        if (title.Length == 0) return BadRequest(AppResponse<object>.Fail("Nhập tên phác đồ"));
        var content = dto.Content?.Trim();
        var plan = new PosGymWorkoutPlan
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerId = customerId,
            TrainerEmployeeId = c.GymTrainerEmployeeId,
            TrainerName = c.GymTrainerName,
            Title = title.Length > 200 ? title[..200] : title,
            Content = string.IsNullOrEmpty(content) ? null : content.Length > 8000 ? content[..8000] : content,
            StartDate = dto.StartDate?.Date,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.PosGymWorkoutPlans.Add(plan);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { plan.Id }));
    }

    [HttpDelete("plans/{id:guid}")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> DeletePlan(Guid id)
    {
        var storeId = RequiredStoreId;
        var p = await db.PosGymWorkoutPlans.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phác đồ"));
        p.Deleted = DateTime.UtcNow;
        p.DeletedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    /// <summary>
    /// Link công khai của hội viên (không cần đăng nhập): gói / buổi còn, lượt tập, thể trạng, phác đồ.
    /// [renew] = true đổi mã mới (link cũ hết hiệu lực — khi lỡ gửi nhầm người).
    /// </summary>
    [HttpPost("customers/{customerId:guid}/share-link")]
    [RequireModulePermission("PosGymCheckIn", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ShareLink(Guid customerId, [FromQuery] bool renew = false)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == customerId && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy khách hàng"));
        if (renew || string.IsNullOrEmpty(c.GymShareToken))
        {
            c.GymShareToken = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(15))
                .Replace('+', '-').Replace('/', '_').TrimEnd('=');
            c.UpdatedAt = DateTime.UtcNow;
            c.UpdatedBy = CurrentUserEmail;
            await db.SaveChangesAsync();
        }
        return Ok(AppResponse<object>.Success(new { path = $"/o/hv/{c.GymShareToken}", token = c.GymShareToken }));
    }
}
