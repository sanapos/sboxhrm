using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Leaves;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Phép năm: chính sách, theo dõi / báo cáo theo năm, điều chỉnh, chốt năm (chuyển phép / trả tiền),
/// tiền phép đưa vào bảng lương.
/// </summary>
[ApiController]
[Route("api/annual-leave")]
[Authorize]
public class AnnualLeaveController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    // ─── DTO ───────────────────────────────────────────────────────

    public sealed record PolicyDto(
        decimal DefaultDays, string ApplyTo, int SeniorityEveryYears, decimal SeniorityDays,
        bool ProrateByMonths, int ProrateCutoffDay, string YearEndMode, decimal? CarryMaxDays,
        int CarryExpireMonth, string PayoutBasis, decimal PayoutStandardDays,
        bool CountWorkingDaysOnly, bool AllowNegative);

    public sealed record RowDto(
        Guid EmployeeId, string Code, string Name, string? Department, Guid? BranchId,
        DateTime? JoinDate, DateTime? ResignationDate, bool HasSalaryProfile, bool Eligible,
        decimal BaseDays, decimal SeniorityDays, int Months, decimal Entitled,
        decimal Carry, decimal CarryExpired, DateTime? CarryExpiresOn, decimal Adjust,
        decimal Used, decimal Pending, decimal PaidOutDays, decimal PaidOutAmount,
        decimal Remaining, decimal Available, decimal DailyRate);

    public sealed record LeaveItemDto(Guid Id, DateTime StartDate, DateTime EndDate, bool HalfShift, decimal Days, string Status, string Type, string? Reason);
    public sealed record EntryDto(Guid Id, int Year, string Kind, decimal Days, decimal? Amount, decimal? DailyRate, DateTime? PayrollMonth, string? Note, DateTime CreatedAt, string? CreatedBy);
    public sealed record DetailDto(RowDto Summary, List<LeaveItemDto> Leaves, List<EntryDto> Entries, PolicyDto Policy);

    public sealed record AdjustRequest(Guid EmployeeId, int Year, decimal Days, string? Note);
    public sealed record PayoutItem(Guid EmployeeId, decimal? Days);
    public sealed record PayoutRequest(int Year, List<PayoutItem> Items, DateTime PayrollMonth, string? Note);
    public sealed record CloseRequest(int Year, DateTime? PayrollMonth, bool Apply);
    public sealed record ClosePreviewRow(Guid EmployeeId, string Code, string Name, decimal Remaining, decimal Carry, decimal PayoutDays, decimal PayoutAmount, decimal Lost, string Reason);

    bool LowRank => AccountRolePolicy.RankOf(CurrentUserRole) < AccountRolePolicy.RankOf(nameof(Roles.DepartmentHead));

    static PolicyDto ToDto(AnnualLeavePolicy p) => new(
        p.DefaultDays, p.ApplyTo, p.SeniorityEveryYears, p.SeniorityDays, p.ProrateByMonths, p.ProrateCutoffDay,
        p.YearEndMode, p.CarryMaxDays, p.CarryExpireMonth, p.PayoutBasis, p.PayoutStandardDays,
        p.CountWorkingDaysOnly, p.AllowNegative);

    async Task<AnnualLeavePolicy> PolicyAsync(bool tracking = false)
    {
        var q = tracking ? db.AnnualLeavePolicies.AsTracking() : db.AnnualLeavePolicies.AsNoTracking();
        return await q.FirstOrDefaultAsync(p => p.StoreId == RequiredStoreId)
               ?? new AnnualLeavePolicy { StoreId = RequiredStoreId };
    }

    static bool IsAnnual(Leave l) =>
        !l.CountAsWork && (l.Type == LeaveType.AnnualLeave
                           || (l.Type == LeaveType.SickLeave && l.SickLeaveMode == SickLeaveMode.UseAnnualLeave));

    /// <summary>Dữ liệu tính phép năm của các nhân viên trong năm.</summary>
    async Task<(AnnualLeavePolicy Policy, List<(Employee Emp, Benefit? Benefit, AnnualLeaveYear Year, List<Leave> Leaves)> Rows)> ComputeAsync(
        int year, Guid? onlyEmployee, CancellationToken ct)
    {
        var policy = await PolicyAsync();
        var start = new DateTime(year, 1, 1);
        var next = start.AddYears(1);
        var today = BenefitTimeline.VnToday();

        var empQ = db.Employees.AsNoTracking().Where(e => e.Deleted == null
            && (e.JoinDate == null || e.JoinDate < next)
            && (e.ResignationDate == null || e.ResignationDate >= start));
        if (onlyEmployee.HasValue) empQ = empQ.Where(e => e.Id == onlyEmployee.Value);
        var emps = await empQ.ToListAsync(ct);
        var ids = emps.Select(e => e.Id).ToList();
        var userIds = emps.Where(e => e.ApplicationUserId.HasValue).Select(e => e.ApplicationUserId!.Value).ToList();

        var versions = await db.EmployeeBenefits.AsNoTracking().Include(eb => eb.Benefit)
            .Where(eb => ids.Contains(eb.EmployeeId)).ToListAsync(ct);
        var leaves = (await db.Leaves.AsNoTracking()
            .Where(l => l.StartDate >= start && l.StartDate < next
                        && (l.Status == LeaveStatus.Approved || l.Status == LeaveStatus.Pending)
                        && ((l.EmployeeId != null && ids.Contains(l.EmployeeId.Value)) || (l.EmployeeId == null && userIds.Contains(l.EmployeeUserId))))
            .ToListAsync(ct)).Where(IsAnnual).ToList();
        var entries = await db.AnnualLeaveEntries.AsNoTracking()
            .Where(x => ids.Contains(x.EmployeeId) && x.Year == year).ToListAsync(ct);
        var holidays = policy.CountWorkingDaysOnly ? await db.Holidays.AsNoTracking().ToListAsync(ct) : [];

        var asOf = year == today.Year ? today : new DateTime(year, 12, 31);
        var rows = new List<(Employee, Benefit?, AnnualLeaveYear, List<Leave>)>();
        foreach (var e in emps)
        {
            var mine = versions.Where(v => v.EmployeeId == e.Id).ToList();
            var benefit = BenefitTimeline.PickCurrent(mine, asOf)?.Benefit;
            var myLeaves = leaves.Where(l => l.EmployeeId == e.Id || (l.EmployeeId == null && l.EmployeeUserId == e.ApplicationUserId)).ToList();
            var hset = AnnualLeaveCalculator.HolidaySet(holidays, [year, year + 1], e.Id);
            var uses = myLeaves.Select(l => l.Status == LeaveStatus.Approved
                    ? new AnnualLeaveCalculator.LeaveUse(l.StartDate, l.AnnualBalanceApplied ? l.AnnualLeaveDaysDeducted : 0, true)
                    : new AnnualLeaveCalculator.LeaveUse(l.StartDate, AnnualLeaveCalculator.CountDays(
                        l.StartDate, l.EndDate, l.IsHalfShift, policy.CountWorkingDaysOnly, benefit?.PaidLeaveType, benefit?.WeeklyOffDays, hset), false))
                .ToList();
            var y = AnnualLeaveCalculator.Compute(policy, e, benefit, year,
                uses, entries.Where(x => x.EmployeeId == e.Id), today);
            rows.Add((e, benefit, y, myLeaves));
        }
        return (policy, rows);
    }

    static RowDto ToRow(Employee e, Benefit? b, AnnualLeaveYear y) => new(
        e.Id, e.EmployeeCode, $"{e.LastName} {e.FirstName}".Trim(), e.Department, e.BranchId,
        e.JoinDate, e.ResignationDate, b != null, y.Eligible,
        y.BaseDays, y.SeniorityDays, y.Months, y.Entitled,
        y.Carry, y.CarryExpired, y.CarryExpiresOn, y.Adjust,
        y.Used, y.Pending, y.PaidOutDays, y.PaidOutAmount,
        y.Remaining, y.Available, y.DailyRate);

    // ─── Chính sách ────────────────────────────────────────────────

    [HttpGet("policy")]
    public async Task<ActionResult<AppResponse<PolicyDto>>> GetPolicy() =>
        Ok(AppResponse<PolicyDto>.Success(ToDto(await PolicyAsync())));

    [HttpPut("policy")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Leave", "SalarySettings")]
    public async Task<ActionResult<AppResponse<PolicyDto>>> SavePolicy([FromBody] PolicyDto dto)
    {
        if (dto.DefaultDays is < 0 or > 60) return BadRequest(AppResponse<PolicyDto>.Fail("Số ngày phép năm từ 0 đến 60."));
        if (dto.PayoutStandardDays is <= 0 or > 31) return BadRequest(AppResponse<PolicyDto>.Fail("Số công chia lương từ 1 đến 31."));
        var p = await PolicyAsync(tracking: true);
        var isNew = p.Id == Guid.Empty;
        if (isNew)
        {
            p.Id = Guid.NewGuid();
            p.IsActive = true;
            p.CreatedBy = CurrentUserEmail;
            db.AnnualLeavePolicies.Add(p);
        }
        p.DefaultDays = dto.DefaultDays;
        p.ApplyTo = dto.ApplyTo == "all" ? "all" : "monthly";
        p.SeniorityEveryYears = Math.Clamp(dto.SeniorityEveryYears, 0, 50);
        p.SeniorityDays = Math.Clamp(dto.SeniorityDays, 0, 10);
        p.ProrateByMonths = dto.ProrateByMonths;
        p.ProrateCutoffDay = Math.Clamp(dto.ProrateCutoffDay, 1, 31);
        p.YearEndMode = dto.YearEndMode is "carry" or "payout" or "carry_payout" or "none" ? dto.YearEndMode : "carry";
        p.CarryMaxDays = dto.CarryMaxDays is null ? null : Math.Clamp(dto.CarryMaxDays.Value, 0, 60);
        p.CarryExpireMonth = Math.Clamp(dto.CarryExpireMonth, 0, 12);
        p.PayoutBasis = dto.PayoutBasis == "base_completion" ? "base_completion" : "base";
        p.PayoutStandardDays = dto.PayoutStandardDays;
        p.CountWorkingDaysOnly = dto.CountWorkingDaysOnly;
        p.AllowNegative = dto.AllowNegative;
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<PolicyDto>.Success(ToDto(p)));
    }

    // ─── Theo dõi / báo cáo ────────────────────────────────────────

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Leave", "LeaveReport", "SalarySettings")]
    public async Task<ActionResult<AppResponse<List<RowDto>>>> Summary([FromQuery] int? year, CancellationToken ct)
    {
        var y = year ?? BenefitTimeline.VnToday().Year;
        var (_, rows) = await ComputeAsync(y, null, ct);
        var list = rows.Select(r => ToRow(r.Emp, r.Benefit, r.Year)).OrderBy(r => r.Name).ToList();
        return Ok(AppResponse<List<RowDto>>.Success(list));
    }

    [HttpGet("employees/{employeeId:guid}")]
    public async Task<ActionResult<AppResponse<DetailDto>>> Detail(Guid employeeId, [FromQuery] int? year, CancellationToken ct)
    {
        // Dưới cấp Trưởng phòng chỉ xem phép của chính mình.
        if (LowRank && EmployeeId != employeeId)
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<DetailDto>.Fail("Chỉ xem được phép năm của bạn."));
        var y = year ?? BenefitTimeline.VnToday().Year;
        var (policy, rows) = await ComputeAsync(y, employeeId, ct);
        if (rows.Count == 0) return NotFound(AppResponse<DetailDto>.Fail("Không tìm thấy nhân viên trong năm này."));
        var (emp, benefit, yr, leaves) = rows[0];
        var hset = AnnualLeaveCalculator.HolidaySet(policy.CountWorkingDaysOnly ? await db.Holidays.AsNoTracking().ToListAsync(ct) : [], [y, y + 1], emp.Id);
        var items = leaves.OrderByDescending(l => l.StartDate).Select(l => new LeaveItemDto(
            l.Id, l.StartDate, l.EndDate, l.IsHalfShift,
            l.Status == LeaveStatus.Approved
                ? l.AnnualLeaveDaysDeducted
                : AnnualLeaveCalculator.CountDays(l.StartDate, l.EndDate, l.IsHalfShift, policy.CountWorkingDaysOnly, benefit?.PaidLeaveType, benefit?.WeeklyOffDays, hset),
            l.Status.ToString(), l.Type.ToString(), l.Reason)).ToList();
        var entries = await db.AnnualLeaveEntries.AsNoTracking()
            .Where(x => x.EmployeeId == employeeId && x.Year == y)
            .OrderByDescending(x => x.CreatedAt)
            .Select(x => new EntryDto(x.Id, x.Year, x.Kind, x.Days, x.Amount, x.DailyRate, x.PayrollMonth, x.Note, x.CreatedAt, x.CreatedBy))
            .ToListAsync(ct);
        return Ok(AppResponse<DetailDto>.Success(new DetailDto(ToRow(emp, benefit, yr), items, entries, ToDto(policy))));
    }

    /// <summary>Số ngày phép của một khoảng nghỉ (xem trước khi gửi đơn).</summary>
    [HttpGet("count-days")]
    public async Task<ActionResult<AppResponse<object>>> CountDays(
        [FromQuery] Guid employeeId, [FromQuery] DateTime start, [FromQuery] DateTime end, [FromQuery] bool half, CancellationToken ct)
    {
        if (LowRank && EmployeeId != employeeId)
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<object>.Fail("Chỉ xem được phép năm của bạn."));
        var (policy, rows) = await ComputeAsync(start.Year, employeeId, ct);
        if (rows.Count == 0) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhân viên."));
        var (emp, benefit, y, _) = rows[0];
        var hset = AnnualLeaveCalculator.HolidaySet(policy.CountWorkingDaysOnly ? await db.Holidays.AsNoTracking().ToListAsync(ct) : [], [start.Year, end.Year], emp.Id);
        var days = AnnualLeaveCalculator.CountDays(start, end, half, policy.CountWorkingDaysOnly, benefit?.PaidLeaveType, benefit?.WeeklyOffDays, hset);
        return Ok(AppResponse<object>.Success(new { days, available = y.Available, remaining = y.Remaining, eligible = y.Eligible, year = y.Year }));
    }

    // ─── Điều chỉnh ────────────────────────────────────────────────

    [HttpPost("entries")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Leave", "SalarySettings")]
    public async Task<ActionResult<AppResponse<EntryDto>>> Adjust([FromBody] AdjustRequest req)
    {
        if (req.Days == 0 || Math.Abs(req.Days) > 60)
            return BadRequest(AppResponse<EntryDto>.Fail("Số ngày điều chỉnh từ −60 đến 60, khác 0."));
        if (string.IsNullOrWhiteSpace(req.Note))
            return BadRequest(AppResponse<EntryDto>.Fail("Ghi lý do điều chỉnh."));
        if (!await db.Employees.AnyAsync(e => e.Id == req.EmployeeId))
            return NotFound(AppResponse<EntryDto>.Fail("Không tìm thấy nhân viên."));
        var x = new AnnualLeaveEntry
        {
            Id = Guid.NewGuid(), StoreId = RequiredStoreId, EmployeeId = req.EmployeeId, Year = req.Year,
            Kind = "adjust", Days = req.Days, Note = req.Note.Trim(), IsActive = true, CreatedBy = CurrentUserEmail,
        };
        db.AnnualLeaveEntries.Add(x);
        await db.SaveChangesAsync();
        return Ok(AppResponse<EntryDto>.Success(new EntryDto(x.Id, x.Year, x.Kind, x.Days, x.Amount, x.DailyRate, x.PayrollMonth, x.Note, x.CreatedAt, x.CreatedBy)));
    }

    [HttpDelete("entries/{id:guid}")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Leave", "SalarySettings")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteEntry(Guid id)
    {
        var x = await db.AnnualLeaveEntries.AsTracking().FirstOrDefaultAsync(e => e.Id == id && e.StoreId == RequiredStoreId);
        if (x == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy bút toán."));
        db.AnnualLeaveEntries.Remove(x);
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Trả tiền phép ─────────────────────────────────────────────

    /// <summary>Trả tiền ngày phép còn lại (nghỉ việc, cuối năm…) — khoản này cộng vào bảng lương tháng đã chọn.</summary>
    [HttpPost("payout")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Payroll", "SalarySettings")]
    public async Task<ActionResult<AppResponse<List<EntryDto>>>> Payout([FromBody] PayoutRequest req, CancellationToken ct)
    {
        if (req.Items == null || req.Items.Count == 0) return BadRequest(AppResponse<List<EntryDto>>.Fail("Chưa chọn nhân viên."));
        var (_, rows) = await ComputeAsync(req.Year, null, ct);
        var month = new DateTime(req.PayrollMonth.Year, req.PayrollMonth.Month, 1);
        var created = new List<AnnualLeaveEntry>();
        foreach (var it in req.Items)
        {
            var r = rows.FirstOrDefault(x => x.Emp.Id == it.EmployeeId);
            if (r.Emp == null) continue;
            var days = it.Days ?? r.Year.Remaining;
            days = Math.Min(days, r.Year.Remaining);
            if (days <= 0) continue;
            var x = new AnnualLeaveEntry
            {
                Id = Guid.NewGuid(), StoreId = RequiredStoreId, EmployeeId = r.Emp.Id, Year = req.Year,
                Kind = "payout", Days = -days, DailyRate = r.Year.DailyRate,
                Amount = Math.Round(days * r.Year.DailyRate, 0, MidpointRounding.AwayFromZero),
                PayrollMonth = month, Note = string.IsNullOrWhiteSpace(req.Note) ? $"Trả tiền {days:0.##} ngày phép {req.Year}" : req.Note.Trim(),
                IsActive = true, CreatedBy = CurrentUserEmail,
            };
            db.AnnualLeaveEntries.Add(x);
            created.Add(x);
        }
        if (created.Count == 0) return BadRequest(AppResponse<List<EntryDto>>.Fail("Không còn ngày phép nào để trả tiền."));
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<List<EntryDto>>.Success(created.Select(x => new EntryDto(x.Id, x.Year, x.Kind, x.Days, x.Amount, x.DailyRate, x.PayrollMonth, x.Note, x.CreatedAt, x.CreatedBy)).ToList()));
    }

    /// <summary>Tiền phép năm đưa vào bảng lương các tháng trong [from, to].</summary>
    [HttpGet("payouts")]
    public async Task<ActionResult<AppResponse<List<object>>>> Payouts([FromQuery] DateTime from, [FromQuery] DateTime to, CancellationToken ct)
    {
        var start = new DateTime(from.Year, from.Month, 1);
        var end = new DateTime(to.Year, to.Month, 1).AddMonths(1);
        var q = db.AnnualLeaveEntries.AsNoTracking()
            .Where(x => x.StoreId == RequiredStoreId && x.Kind == "payout" && x.PayrollMonth >= start && x.PayrollMonth < end);
        if (LowRank)
        {
            if (!EmployeeId.HasValue) return Ok(AppResponse<List<object>>.Success([]));
            q = q.Where(x => x.EmployeeId == EmployeeId.Value);
        }
        var list = await q.GroupBy(x => x.EmployeeId)
            .Select(g => new { employeeId = g.Key, days = -g.Sum(x => x.Days), amount = g.Sum(x => x.Amount ?? 0) })
            .ToListAsync(ct);
        return Ok(AppResponse<List<object>>.Success(list.Cast<object>().ToList()));
    }

    // ─── Chốt năm ──────────────────────────────────────────────────

    /// <summary>
    /// Xử lý phép còn lại cuối năm theo chính sách: chuyển sang năm sau (tối đa N ngày), trả tiền, hoặc hủy.
    /// Người nghỉ việc trong năm luôn được trả tiền phép còn lại (BLLĐ Điều 113.3).
    /// Apply = false: chỉ xem trước.
    /// </summary>
    [HttpPost("close-year")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Payroll", "SalarySettings")]
    public async Task<ActionResult<AppResponse<object>>> CloseYear([FromBody] CloseRequest req, CancellationToken ct)
    {
        var tag = $"close:{req.Year}";
        var closed = await db.AnnualLeaveEntries.AnyAsync(x => x.StoreId == RequiredStoreId && x.Note != null && x.Note.StartsWith(tag), ct);
        var (policy, rows) = await ComputeAsync(req.Year, null, ct);
        var preview = new List<ClosePreviewRow>();
        var yearEnd = new DateTime(req.Year, 12, 31);
        foreach (var (emp, _, y, _) in rows)
        {
            var rem = y.Remaining;
            if (rem <= 0) continue;
            var name = $"{emp.LastName} {emp.FirstName}".Trim();
            var resigned = emp.ResignationDate.HasValue && emp.ResignationDate.Value.Date <= yearEnd;
            decimal carry = 0, pay = 0;
            string reason;
            if (resigned)
            {
                pay = rem;
                reason = "Nghỉ việc — trả tiền phép còn lại";
            }
            else
            {
                switch (policy.YearEndMode)
                {
                    case "carry":
                        carry = policy.CarryMaxDays.HasValue ? Math.Min(rem, policy.CarryMaxDays.Value) : rem;
                        reason = "Chuyển sang năm sau";
                        break;
                    case "payout":
                        pay = rem;
                        reason = "Trả tiền phép còn lại";
                        break;
                    case "carry_payout":
                        carry = policy.CarryMaxDays.HasValue ? Math.Min(rem, policy.CarryMaxDays.Value) : rem;
                        pay = rem - carry;
                        reason = pay > 0 ? "Chuyển tối đa, trả tiền phần dư" : "Chuyển sang năm sau";
                        break;
                    default:
                        reason = "Hủy phép còn lại";
                        break;
                }
            }
            preview.Add(new ClosePreviewRow(emp.Id, emp.EmployeeCode, name, rem, carry, pay,
                Math.Round(pay * y.DailyRate, 0, MidpointRounding.AwayFromZero), rem - carry - pay, reason));
        }

        if (!req.Apply)
            return Ok(AppResponse<object>.Success(new { closed, rows = preview }));
        if (closed)
            return BadRequest(AppResponse<object>.Fail($"Năm {req.Year} đã chốt. Mở lại trước khi chốt lần nữa."));
        if (preview.Any(p => p.PayoutDays > 0) && req.PayrollMonth == null)
            return BadRequest(AppResponse<object>.Fail("Chọn tháng lương nhận tiền phép."));

        var month = req.PayrollMonth.HasValue ? new DateTime(req.PayrollMonth.Value.Year, req.PayrollMonth.Value.Month, 1) : (DateTime?)null;
        foreach (var p in preview)
        {
            var rate = rows.First(r => r.Emp.Id == p.EmployeeId).Year.DailyRate;
            if (p.Carry > 0)
                db.AnnualLeaveEntries.Add(new AnnualLeaveEntry
                {
                    Id = Guid.NewGuid(), StoreId = RequiredStoreId, EmployeeId = p.EmployeeId, Year = req.Year + 1,
                    Kind = "carry", Days = p.Carry, Note = $"{tag} Chuyển {p.Carry:0.##} ngày từ năm {req.Year}",
                    IsActive = true, CreatedBy = CurrentUserEmail,
                });
            if (p.PayoutDays > 0)
                db.AnnualLeaveEntries.Add(new AnnualLeaveEntry
                {
                    Id = Guid.NewGuid(), StoreId = RequiredStoreId, EmployeeId = p.EmployeeId, Year = req.Year,
                    Kind = "payout", Days = -p.PayoutDays, DailyRate = rate, Amount = p.PayoutAmount, PayrollMonth = month,
                    Note = $"{tag} Trả tiền {p.PayoutDays:0.##} ngày phép năm {req.Year}",
                    IsActive = true, CreatedBy = CurrentUserEmail,
                });
        }
        // Đánh dấu đã chốt (kể cả khi không ai còn phép).
        db.AnnualLeaveEntries.Add(new AnnualLeaveEntry
        {
            Id = Guid.NewGuid(), StoreId = RequiredStoreId, EmployeeId = rows.FirstOrDefault().Emp?.Id ?? Guid.Empty,
            Year = req.Year, Kind = "mark", Days = 0, Note = $"{tag} Đã chốt phép năm {req.Year}",
            IsActive = true, CreatedBy = CurrentUserEmail,
        });
        if (rows.Count == 0) return Ok(AppResponse<object>.Success(new { closed = true, rows = preview }));
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<object>.Success(new { closed = true, rows = preview }));
    }

    /// <summary>Mở lại năm đã chốt: xóa các bút toán chuyển phép / trả tiền do lần chốt tạo ra.</summary>
    [HttpPost("reopen-year/{year:int}")]
    [Authorize(Policy = PolicyNames.ManagerOrAccountant)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Payroll", "SalarySettings")]
    public async Task<ActionResult<AppResponse<int>>> ReopenYear(int year)
    {
        var tag = $"close:{year}";
        var list = await db.AnnualLeaveEntries.AsTracking()
            .Where(x => x.StoreId == RequiredStoreId && x.Note != null && x.Note.StartsWith(tag)).ToListAsync();
        db.AnnualLeaveEntries.RemoveRange(list);
        await db.SaveChangesAsync();
        return Ok(AppResponse<int>.Success(list.Count));
    }
}
