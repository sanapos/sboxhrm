using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tài khoản PT (quyền «PT · Khách của tôi & lịch tập» — PosGymTrainer): danh sách hội viên mình phụ trách,
/// lịch tập hẹn với hội viên. Lễ tân / quản lý (quyền Check-in gym) xem được mọi PT và chọn PT.
/// </summary>
public partial class PosGymController
{
    /// <summary>
    /// Có quyền màn Check-in gym (lễ tân / quản lý) — thấy mọi hội viên, mọi PT. Khi chạy thật dịch vụ phân quyền
    /// luôn có (filter quyền đã chặn ở cửa); controller dựng tay trong test không có → coi như lễ tân.
    /// </summary>
    async Task<bool> HasGymDeskAsync(ModulePermissionAction action) =>
        HttpContext?.RequestServices.GetService<IModulePermissionService>() is not { } svc
        || await svc.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId, "PosGymCheckIn", action);

    /// <summary>
    /// null = được thao tác hội viên này. PT (chỉ có quyền «Khách của tôi») chỉ được hội viên mình phụ trách.
    /// </summary>
    async Task<string?> TrainerScopeErrorAsync(Guid customerId, ModulePermissionAction action)
    {
        if (await HasGymDeskAsync(action)) return null;
        if (EmployeeId is not Guid me) return "Tài khoản chưa gắn hồ sơ nhân viên — nhờ chủ cửa hàng gắn tài khoản với hồ sơ PT";
        var trainer = await db.PosCustomers.AsNoTracking()
            .Where(c => c.Id == customerId && c.StoreId == RequiredStoreId && c.Deleted == null)
            .Select(c => c.GymTrainerEmployeeId)
            .FirstOrDefaultAsync();
        return trainer == me ? null : "Hội viên này không do bạn phụ trách";
    }

    /// <summary>PT đang xem: lễ tân / quản lý chọn được (null = mọi PT); PT chỉ chính mình.</summary>
    async Task<(Guid? Trainer, bool ManageAll, string? Error)> ResolveTrainerAsync(Guid? requested, ModulePermissionAction action)
    {
        if (await HasGymDeskAsync(action)) return (requested, true, null);
        if (EmployeeId is not Guid me)
            return (null, false, "Tài khoản chưa gắn hồ sơ nhân viên — nhờ chủ cửa hàng gắn tài khoản với hồ sơ PT");
        return (me, false, null);
    }

    async Task<string?> EmployeeNameAsync(Guid employeeId) =>
        await db.Employees.AsNoTracking()
            .Where(e => e.Id == employeeId && e.StoreId == RequiredStoreId)
            .Select(e => (e.LastName + " " + e.FirstName).Trim())
            .FirstOrDefaultAsync();

    /// <summary>Tài khoản đang dùng: là PT nào, có xem được mọi PT không, danh sách PT đang phụ trách hội viên.</summary>
    [HttpGet("pt/me")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<object>>> PtMe()
    {
        var storeId = RequiredStoreId;
        var manageAll = await HasGymDeskAsync(ModulePermissionAction.View);
        var trainers = await db.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.GymTrainerEmployeeId != null)
            .GroupBy(c => new { c.GymTrainerEmployeeId, c.GymTrainerName })
            .Select(g => new { employeeId = g.Key.GymTrainerEmployeeId, name = g.Key.GymTrainerName, clients = g.Count() })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            employeeId = EmployeeId,
            name = EmployeeId is Guid me ? await EmployeeNameAsync(me) : null,
            manageAll,
            trainers = manageAll ? trainers.OrderBy(t => t.name).Cast<object>().ToList() : [],
        }));
    }

    /// <summary>Hội viên PT phụ trách: thẻ / gói, buổi tập gần nhất, lần đo gần nhất, lịch hẹn tới.</summary>
    [HttpGet("pt/clients")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<object>>> PtClients([FromQuery] Guid? trainerId = null)
    {
        var storeId = RequiredStoreId;
        var (trainer, _, error) = await ResolveTrainerAsync(trainerId, ModulePermissionAction.View);
        if (error != null) return StatusCode(403, AppResponse<object>.Fail(error));
        var customers = await db.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.GymTrainerEmployeeId != null
                && (trainer == null || c.GymTrainerEmployeeId == trainer))
            .Select(c => new { c.Id, c.Name, c.Phone, c.GymTrainerEmployeeId, c.GymTrainerName })
            .OrderBy(c => c.Name)
            .Take(1000)
            .ToListAsync();
        var ids = customers.Select(c => c.Id).ToList();
        var now = DateTime.UtcNow;
        var packs = await BestPackagesAsync(storeId, ids);
        var visits = await db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && ids.Contains(v.CustomerId) && v.Deleted == null && v.CheckInAt >= now.AddDays(-90))
            .Select(v => new { v.CustomerId, v.CheckInAt, v.CheckOutAt, v.Status })
            .ToListAsync();
        var entered = visits.Where(v => !GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt))
            .GroupBy(v => v.CustomerId)
            .ToDictionary(g => g.Key, g => (Last: g.Max(v => v.CheckInAt), Month: g.Count(v => v.CheckInAt >= now.AddDays(-30))));
        var lastBody = (await db.PosGymAssessments.AsNoTracking()
                .Where(a => a.StoreId == storeId && ids.Contains(a.CustomerId) && a.Deleted == null && a.Kind == 0)
                .Select(a => new { a.CustomerId, a.AssessedAt, a.WeightKg })
                .ToListAsync())
            .GroupBy(a => a.CustomerId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(a => a.AssessedAt).First());
        var next = (await db.PosGymPtSessions.AsNoTracking()
                .Where(s => s.StoreId == storeId && ids.Contains(s.CustomerId) && s.Deleted == null && s.Status == 0
                    && s.StartAt >= now.AddMinutes(-90))
                .Select(s => new { s.CustomerId, s.StartAt })
                .ToListAsync())
            .GroupBy(s => s.CustomerId)
            .ToDictionary(g => g.Key, g => g.Min(s => s.StartAt));

        return Ok(AppResponse<object>.Success(customers.Select(c =>
        {
            packs.TryGetValue(c.Id, out var p);
            entered.TryGetValue(c.Id, out var v);
            lastBody.TryGetValue(c.Id, out var body);
            var hasNext = next.TryGetValue(c.Id, out var nextAt);
            return new
            {
                customerId = c.Id,
                name = c.Name,
                phone = c.Phone,
                trainerEmployeeId = c.GymTrainerEmployeeId,
                trainerName = c.GymTrainerName,
                packageName = p?.PackageName,
                unlimited = p != null && PosCustomerSessionBalance.IsUnlimitedCount(p.TotalSessions),
                remainingSessions = p?.RemainingSessions,
                expiresAt = p?.ExpiresAt,
                packageActive = p != null && p.RemainingSessions > 0 && (p.ExpiresAt == null || p.ExpiresAt > now),
                lastVisitAt = v.Last == default ? (DateTime?)null : v.Last,
                visits30 = v.Month,
                lastAssessedAt = body?.AssessedAt,
                lastWeightKg = body?.WeightKg,
                nextSessionAt = hasNext ? nextAt : (DateTime?)null,
            };
        }).ToList()));
    }

    public record PtSessionDto(
        Guid Id, Guid CustomerId, string CustomerName, string? Phone, Guid TrainerEmployeeId, string? TrainerName,
        DateTime StartAt, int DurationMinutes, int Status, string? Note, Guid? SeriesId, Guid? VisitId, bool Reviewed);

    async Task<List<PtSessionDto>> LoadPtSessionsAsync(Guid storeId, IQueryable<PosGymPtSession> q)
    {
        var rows = await q.OrderBy(s => s.StartAt).Take(2000)
            .Select(s => new
            {
                s.Id, s.CustomerId, CustomerName = s.Customer != null ? s.Customer.Name : "",
                Phone = s.Customer != null ? s.Customer.Phone : null,
                s.TrainerEmployeeId, s.TrainerName, s.StartAt, s.DurationMinutes, s.Status, s.Note, s.SeriesId,
            })
            .ToListAsync();
        if (rows.Count == 0) return [];
        // Lượt tập cùng ngày của hội viên (để «Hoàn thành» gắn đánh giá vào đúng lượt) + đã đánh giá chưa.
        var ids = rows.Select(r => r.CustomerId).Distinct().ToList();
        var from = rows.Min(r => r.StartAt).AddDays(-1);
        var to = rows.Max(r => r.StartAt).AddDays(1);
        var visits = await db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && ids.Contains(v.CustomerId) && v.Deleted == null
                && v.CheckInAt >= from && v.CheckInAt < to)
            .Select(v => new { v.Id, v.CustomerId, v.CheckInAt, v.CheckOutAt, v.Status })
            .ToListAsync();
        var visitIds = visits.Select(v => (Guid?)v.Id).ToList();
        var reviewed = (await db.PosGymAssessments.AsNoTracking()
                .Where(a => a.StoreId == storeId && a.Kind == 1 && a.Deleted == null && visitIds.Contains(a.VisitId))
                .Select(a => a.VisitId!.Value)
                .ToListAsync())
            .ToHashSet();
        return rows.Select(r =>
        {
            var day = GymVisitRules.VnDayUtc(r.StartAt);
            var visit = visits
                .Where(v => v.CustomerId == r.CustomerId && v.CheckInAt >= day.FromUtc && v.CheckInAt < day.ToUtc
                    && !GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt))
                .OrderBy(v => (v.CheckInAt - r.StartAt).Duration())
                .FirstOrDefault();
            return new PtSessionDto(r.Id, r.CustomerId, r.CustomerName, r.Phone, r.TrainerEmployeeId, r.TrainerName,
                r.StartAt, r.DurationMinutes, r.Status, r.Note, r.SeriesId, visit?.Id,
                visit != null && reviewed.Contains(visit.Id));
        }).ToList();
    }

    /// <summary>Lịch tập PT trong khoảng ngày (giờ VN). Mặc định tuần này.</summary>
    [HttpGet("pt/sessions")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<List<PtSessionDto>>>> PtSessions(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null,
        [FromQuery] Guid? trainerId = null, [FromQuery] Guid? customerId = null)
    {
        var storeId = RequiredStoreId;
        var (trainer, _, error) = await ResolveTrainerAsync(trainerId, ModulePermissionAction.View);
        if (error != null) return StatusCode(403, AppResponse<List<PtSessionDto>>.Fail(error));
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var (fromUtc, toUtc) = RangeUtc(from, to, todayVn.AddDays(-(((int)todayVn.DayOfWeek + 6) % 7)));
        var q = db.PosGymPtSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.StartAt >= fromUtc && s.StartAt < toUtc);
        if (trainer is Guid t) q = q.Where(s => s.TrainerEmployeeId == t);
        if (customerId is Guid cid) q = q.Where(s => s.CustomerId == cid);
        return Ok(AppResponse<List<PtSessionDto>>.Success(await LoadPtSessionsAsync(storeId, q)));
    }

    /// <param name="RepeatWeeks">Lặp thêm N tuần cùng thứ / giờ (0 = chỉ buổi này, tối đa 26).</param>
    public record SavePtSessionDto(
        Guid CustomerId, DateTime StartAt, int DurationMinutes = 60, string? Note = null, int RepeatWeeks = 0,
        Guid? TrainerEmployeeId = null);

    /// <summary>
    /// Đặt lịch tập PT (lặp hàng tuần nếu cần). Bỏ qua buổi trùng giờ với lịch đã có của PT và báo lại.
    /// </summary>
    [HttpPost("pt/sessions")]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<object>>> AddPtSession([FromBody] SavePtSessionDto dto)
    {
        var storeId = RequiredStoreId;
        if (await TrainerScopeErrorAsync(dto.CustomerId, ModulePermissionAction.Create) is string deny)
            return StatusCode(403, AppResponse<object>.Fail(deny));
        var c = await db.PosCustomers.AsNoTracking()
            .Where(x => x.Id == dto.CustomerId && x.StoreId == storeId && x.Deleted == null)
            .Select(x => new { x.GymTrainerEmployeeId, x.GymTrainerName })
            .FirstOrDefaultAsync();
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy hội viên"));
        var desk = await HasGymDeskAsync(ModulePermissionAction.Create);
        var trainerId = desk ? dto.TrainerEmployeeId ?? c.GymTrainerEmployeeId ?? EmployeeId : EmployeeId;
        if (trainerId is not Guid tid)
            return BadRequest(AppResponse<object>.Fail("Hội viên chưa có PT phụ trách — gán PT trước khi đặt lịch"));
        var trainerName = tid == c.GymTrainerEmployeeId ? c.GymTrainerName : await EmployeeNameAsync(tid);
        var duration = Math.Clamp(dto.DurationMinutes, 15, 240);
        var start = dto.StartAt.Kind == DateTimeKind.Unspecified ? dto.StartAt.AddHours(-7) : dto.StartAt.ToUniversalTime();
        var repeat = Math.Clamp(dto.RepeatWeeks, 0, 26);
        var seriesId = repeat > 0 ? Guid.NewGuid() : (Guid?)null;
        var note = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim()[..Math.Min(500, dto.Note.Trim().Length)];

        var lastEnd = start.AddDays(7 * repeat).AddMinutes(duration);
        var busy = await db.PosGymPtSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.TrainerEmployeeId == tid && s.Deleted == null && s.Status != 2
                && s.StartAt < lastEnd && s.StartAt >= start.AddHours(-5))
            .Select(s => new { s.StartAt, s.DurationMinutes })
            .ToListAsync();
        var created = new List<DateTime>();
        var skipped = new List<DateTime>();
        for (var i = 0; i <= repeat; i++)
        {
            var at = start.AddDays(7 * i);
            var end = at.AddMinutes(duration);
            if (busy.Any(b => b.StartAt < end && b.StartAt.AddMinutes(b.DurationMinutes) > at))
            {
                skipped.Add(at);
                continue;
            }
            db.PosGymPtSessions.Add(new PosGymPtSession
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = dto.CustomerId,
                TrainerEmployeeId = tid,
                TrainerName = trainerName,
                StartAt = at,
                DurationMinutes = duration,
                Note = note,
                SeriesId = seriesId,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            created.Add(at);
        }
        if (created.Count == 0)
            return Conflict(AppResponse<object>.Fail("PT đã có lịch trùng giờ này — chọn giờ khác"));
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            created = created.Count,
            skipped = skipped.Select(s => s.AddHours(7).ToString("dd/MM HH:mm")).ToList(),
        }));
    }

    /// <param name="Status">0 hẹn, 1 đã tập, 2 hủy, 3 khách vắng.</param>
    public record UpdatePtSessionDto(int? Status = null, string? Note = null, DateTime? StartAt = null, int? DurationMinutes = null);

    [HttpPut("pt/sessions/{id:guid}")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<object>>> UpdatePtSession(Guid id, [FromBody] UpdatePtSessionDto dto)
    {
        var storeId = RequiredStoreId;
        var s = await db.PosGymPtSessions.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (s == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy lịch tập"));
        if (!await HasGymDeskAsync(ModulePermissionAction.Edit) && s.TrainerEmployeeId != EmployeeId)
            return StatusCode(403, AppResponse<object>.Fail("Lịch này không phải của bạn"));
        if (dto.Status is int st)
        {
            if (st is < 0 or > 3) return BadRequest(AppResponse<object>.Fail("Trạng thái không hợp lệ"));
            s.Status = st;
        }
        if (dto.Note != null) s.Note = string.IsNullOrWhiteSpace(dto.Note) ? null : dto.Note.Trim()[..Math.Min(500, dto.Note.Trim().Length)];
        if (dto.StartAt is DateTime at)
            s.StartAt = at.Kind == DateTimeKind.Unspecified ? at.AddHours(-7) : at.ToUniversalTime();
        if (dto.DurationMinutes is int d) s.DurationMinutes = Math.Clamp(d, 15, 240);
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        var row = (await LoadPtSessionsAsync(storeId, db.PosGymPtSessions.AsNoTracking().Where(x => x.Id == id))).First();
        return Ok(AppResponse<object>.Success(row));
    }

    /// <summary>Xóa lịch; <paramref name="series"/> = true xóa luôn các buổi CHƯA TẬP sau đó trong cùng đợt lặp.</summary>
    [HttpDelete("pt/sessions/{id:guid}")]
    [RequireAnyModulePermission(ModulePermissionAction.Delete, "PosGymCheckIn", "PosGymTrainer")]
    public async Task<ActionResult<AppResponse<object>>> DeletePtSession(Guid id, [FromQuery] bool series = false)
    {
        var storeId = RequiredStoreId;
        var s = await db.PosGymPtSessions.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (s == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy lịch tập"));
        if (!await HasGymDeskAsync(ModulePermissionAction.Delete) && s.TrainerEmployeeId != EmployeeId)
            return StatusCode(403, AppResponse<object>.Fail("Lịch này không phải của bạn"));
        var list = new List<PosGymPtSession> { s };
        if (series && s.SeriesId is Guid sid)
            list.AddRange(await db.PosGymPtSessions.AsTracking()
                .Where(x => x.StoreId == storeId && x.SeriesId == sid && x.Id != id && x.Deleted == null
                    && x.Status == 0 && x.StartAt > s.StartAt)
                .ToListAsync());
        foreach (var x in list)
        {
            x.Deleted = DateTime.UtcNow;
            x.DeletedBy = CurrentUserEmail;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { deleted = list.Count }));
    }
}
