using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Leaves;

/// <summary>
/// Phép năm theo sổ phép: còn lại = được hưởng + chuyển sang ± điều chỉnh − đã nghỉ − đã trả tiền.
/// Đơn phép năm được duyệt thì ghi số ngày (ngày làm việc) vào đơn; hủy duyệt thì hoàn.
/// </summary>
public class AnnualLeaveBalanceService(
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<Employee> employeeRepository,
    IRepository<EmployeeWorkingInfo> workingInfoRepository,
    IRepository<Leave> leaveRepository,
    IRepository<Holiday> holidayRepository,
    IRepository<AnnualLeavePolicy> policyRepository,
    IRepository<AnnualLeaveEntry> entryRepository
) : IAnnualLeaveBalanceService
{
    public bool ShouldDeductFromAnnualBalance(Leave leave)
    {
        if (leave.CountAsWork || leave.AnnualBalanceApplied)
            return false;

        return IsAnnualType(leave);
    }

    static bool IsAnnualType(Leave leave) =>
        !leave.CountAsWork
        && (leave.Type == LeaveType.AnnualLeave
            || (leave.Type == LeaveType.SickLeave && leave.SickLeaveMode == SickLeaveMode.UseAnnualLeave));

    /// <summary>Số ngày lịch (dự phòng khi chưa có dữ liệu nhân viên).</summary>
    public decimal CalculateLeaveDays(Leave leave)
    {
        var days = (leave.EndDate.Date - leave.StartDate.Date).Days + 1;
        if (days < 1) days = 1;
        return leave.IsHalfShift ? days * 0.5m : days;
    }

    // ─── Dữ liệu ───────────────────────────────────────────────────

    async Task<AnnualLeavePolicy> PolicyAsync(Guid? storeId, CancellationToken ct)
    {
        if (storeId.HasValue)
        {
            var p = await policyRepository.GetSingleAsync(x => x.StoreId == storeId.Value, cancellationToken: ct);
            if (p != null) return p;
        }
        return new AnnualLeavePolicy { StoreId = storeId ?? Guid.Empty };
    }

    async Task<Benefit?> CurrentBenefitAsync(Guid employeeId, DateTime day, CancellationToken ct)
    {
        var versions = await employeeBenefitRepository.GetAllAsync(
            eb => eb.EmployeeId == employeeId,
            includeProperties: [nameof(EmployeeBenefit.Benefit)],
            cancellationToken: ct);
        return BenefitTimeline.PickCurrent(versions, day)?.Benefit;
    }

    async Task<List<Leave>> AnnualLeavesAsync(Employee emp, int year, CancellationToken ct)
    {
        var from = new DateTime(year, 1, 1);
        var to = from.AddYears(1);
        var userId = emp.ApplicationUserId;
        var list = await leaveRepository.GetAllAsync(
            l => (l.EmployeeId == emp.Id || (l.EmployeeId == null && userId != null && l.EmployeeUserId == userId))
                 && l.StartDate >= from && l.StartDate < to
                 && (l.Status == LeaveStatus.Approved || l.Status == LeaveStatus.Pending),
            cancellationToken: ct);
        return list.Where(IsAnnualType).ToList();
    }

    /// <summary>Số ngày phép (ngày làm việc) của một đơn theo hồ sơ lương và ngày lễ.</summary>
    public async Task<decimal> CountDaysAsync(Leave leave, Guid employeeId, AnnualLeavePolicy policy, Benefit? benefit, CancellationToken ct)
    {
        var years = Enumerable.Range(leave.StartDate.Year, Math.Max(1, leave.EndDate.Year - leave.StartDate.Year + 1));
        var holidays = policy.CountWorkingDaysOnly
            ? await holidayRepository.GetAllAsync(h => h.StoreId == policy.StoreId || h.StoreId == null, cancellationToken: ct)
            : [];
        return AnnualLeaveCalculator.CountDays(
            leave.StartDate, leave.EndDate, leave.IsHalfShift, policy.CountWorkingDaysOnly,
            benefit?.PaidLeaveType, benefit?.WeeklyOffDays,
            AnnualLeaveCalculator.HolidaySet(holidays, years, employeeId));
    }

    async Task<(AnnualLeaveYear Year, AnnualLeavePolicy Policy, Benefit? Benefit)> ComputeAsync(
        Employee emp, int year, Guid? excludeLeaveId, CancellationToken ct)
    {
        var policy = await PolicyAsync(emp.StoreId, ct);
        var today = BenefitTimeline.VnToday();
        var benefit = await CurrentBenefitAsync(emp.Id, year == today.Year ? today : new DateTime(year, 12, 31), ct);
        var leaves = await AnnualLeavesAsync(emp, year, ct);
        var uses = new List<AnnualLeaveCalculator.LeaveUse>();
        foreach (var l in leaves.Where(l => l.Id != excludeLeaveId))
        {
            if (l.Status == LeaveStatus.Approved)
            {
                if (l.AnnualBalanceApplied) uses.Add(new(l.StartDate, l.AnnualLeaveDaysDeducted, true));
            }
            else
            {
                uses.Add(new(l.StartDate, await CountDaysAsync(l, emp.Id, policy, benefit, ct), false));
            }
        }
        var entries = await entryRepository.GetAllAsync(e => e.EmployeeId == emp.Id && e.Year == year, cancellationToken: ct);
        return (AnnualLeaveCalculator.Compute(policy, emp, benefit, year, uses, entries, today), policy, benefit);
    }

    // ─── Dịch vụ ───────────────────────────────────────────────────

    public async Task<AnnualLeaveBalanceDto?> GetBalanceAsync(
        Guid employeeId,
        CancellationToken cancellationToken = default)
    {
        var emp = await employeeRepository.GetByIdAsync(employeeId, cancellationToken: cancellationToken);
        if (emp == null) return null;
        var (y, _, benefit) = await ComputeAsync(emp, BenefitTimeline.VnToday().Year, null, cancellationToken);
        if (benefit == null) return null;

        return new AnnualLeaveBalanceDto
        {
            EmployeeId = employeeId,
            Year = y.Year,
            Eligible = y.Eligible,
            RemainingDays = y.Remaining,
            AvailableDays = y.Available,
            EntitlementDays = y.Entitled,
            CarryDays = y.Carry - y.CarryExpired,
            CarryExpiresOn = y.CarryExpired > 0 ? null : y.CarryExpiresOn,
            AdjustDays = y.Adjust,
            UsedDays = y.Used,
            PendingDays = y.Pending,
            PaidOutDays = y.PaidOutDays,
            BenefitName = benefit.Name,
        };
    }

    public async Task<AppResponse<decimal>> TryApplyDeductionAsync(
        Leave leave,
        CancellationToken cancellationToken = default)
    {
        if (!ShouldDeductFromAnnualBalance(leave))
            return AppResponse<decimal>.Success(0);

        var employeeId = await ResolveEmployeeIdAsync(leave, cancellationToken);
        if (!employeeId.HasValue)
            return AppResponse<decimal>.Error("Không xác định được nhân viên để trừ phép năm.");
        var emp = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: cancellationToken);
        if (emp == null)
            return AppResponse<decimal>.Error("Không tìm thấy nhân viên để trừ phép năm.");

        var (y, policy, benefit) = await ComputeAsync(emp, leave.StartDate.Year, leave.Id, cancellationToken);
        if (benefit == null)
            return AppResponse<decimal>.Error(
                "Nhân viên chưa có thiết lập lương. Vui lòng thiết lập lương trước khi duyệt phép năm.");
        if (!y.Eligible)
            return AppResponse<decimal>.Error(
                "Nhân viên không thuộc diện hưởng phép năm (chính sách chỉ áp dụng lương tháng). Hãy chọn loại nghỉ khác.");

        var days = await CountDaysAsync(leave, emp.Id, policy, benefit, cancellationToken);
        if (days <= 0)
            return AppResponse<decimal>.Error("Khoảng nghỉ chỉ gồm ngày lễ / ngày nghỉ hằng tuần — không cần dùng phép năm.");

        // Số còn lại không tính chính đơn này (đơn đang chờ duyệt khác vẫn được trừ ở «Available»).
        var remaining = y.Remaining;
        if (days > remaining && !policy.AllowNegative)
        {
            return AppResponse<decimal>.Error(
                $"Không đủ phép năm {y.Year}. Còn lại: {remaining:0.##} ngày, đơn cần: {days:0.##} ngày.");
        }

        leave.AnnualLeaveDaysDeducted = days;
        leave.AnnualBalanceApplied = true;
        leave.EmployeeId ??= employeeId;

        await SyncCacheAsync(emp, leave.EmployeeUserId, remaining - days, y.Year, cancellationToken);
        return AppResponse<decimal>.Success(remaining - days);
    }

    public async Task RestoreAsync(Leave leave, CancellationToken cancellationToken = default)
    {
        if (!leave.AnnualBalanceApplied || leave.AnnualLeaveDaysDeducted <= 0)
            return;

        leave.AnnualLeaveDaysDeducted = 0;
        leave.AnnualBalanceApplied = false;

        var employeeId = await ResolveEmployeeIdAsync(leave, cancellationToken);
        if (!employeeId.HasValue) return;
        var emp = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: cancellationToken);
        if (emp == null) return;
        var (y, _, _) = await ComputeAsync(emp, leave.StartDate.Year, leave.Id, cancellationToken);
        await SyncCacheAsync(emp, leave.EmployeeUserId, y.Remaining, y.Year, cancellationToken);
    }

    public async Task<string?> CheckRequestAsync(Leave leave, CancellationToken cancellationToken = default)
    {
        if (!IsAnnualType(leave)) return null;
        var employeeId = await ResolveEmployeeIdAsync(leave, cancellationToken);
        if (!employeeId.HasValue) return null;
        var emp = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: cancellationToken);
        if (emp == null) return null;
        var (y, policy, benefit) = await ComputeAsync(emp, leave.StartDate.Year, leave.Id, cancellationToken);
        if (benefit == null)
            return "Bạn chưa có thiết lập lương nên chưa có quỹ phép năm. Liên hệ quản lý.";
        if (!y.Eligible)
            return "Bạn không thuộc diện hưởng phép năm. Hãy chọn loại nghỉ khác (nghỉ không lương…).";
        var days = await CountDaysAsync(leave, emp.Id, policy, benefit, cancellationToken);
        if (days <= 0)
            return "Khoảng nghỉ chỉ gồm ngày lễ / ngày nghỉ hằng tuần — không cần xin phép năm.";
        if (days > y.Available && !policy.AllowNegative)
            return $"Không đủ phép năm {y.Year}: còn có thể xin {y.Available:0.##} ngày (đã trừ đơn đang chờ duyệt), đơn này {days:0.##} ngày.";
        return null;
    }

    /// <summary>Ghi số phép còn lại năm hiện tại vào hồ sơ (màn cũ / báo cáo cũ đọc trường này).</summary>
    async Task SyncCacheAsync(Employee emp, Guid employeeUserId, decimal remaining, int year, CancellationToken ct)
    {
        if (year != BenefitTimeline.VnToday().Year) return;
        var versions = await employeeBenefitRepository.GetAllAsync(eb => eb.EmployeeId == emp.Id, cancellationToken: ct);
        var cur = BenefitTimeline.PickCurrent(versions, BenefitTimeline.VnToday());
        if (cur != null)
        {
            cur.BalancedPaidLeaveDays = remaining;
            await employeeBenefitRepository.UpdateAsync(cur, ct);
        }
        var wi = await workingInfoRepository.GetSingleAsync(
            w => w.EmployeeId == emp.Id || w.EmployeeUserId == employeeUserId,
            cancellationToken: ct);
        if (wi == null) return;
        wi.BalancedPaidLeaveDays = remaining;
        await workingInfoRepository.UpdateAsync(wi, ct);
    }

    private async Task<Guid?> ResolveEmployeeIdAsync(Leave leave, CancellationToken cancellationToken)
    {
        if (leave.EmployeeId.HasValue)
            return leave.EmployeeId;

        var emp = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == leave.EmployeeUserId,
            cancellationToken: cancellationToken);
        return emp?.Id;
    }
}
