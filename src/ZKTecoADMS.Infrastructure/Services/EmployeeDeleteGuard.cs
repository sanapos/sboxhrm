using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

public class EmployeeDeleteGuard(ZKTecoDbContext db) : IEmployeeDeleteGuard
{
    public async Task<EmployeeDeleteEvaluation> EvaluateAsync(
        Guid employeeId,
        CancellationToken cancellationToken = default)
    {
        var batch = await EvaluateBatchAsync([employeeId], cancellationToken);
        return batch.TryGetValue(employeeId, out var evaluation)
            ? evaluation
            : new EmployeeDeleteEvaluation(true, null);
    }

    public async Task<IReadOnlyDictionary<Guid, EmployeeDeleteEvaluation>> EvaluateBatchAsync(
        IReadOnlyList<Guid> employeeIds,
        CancellationToken cancellationToken = default)
    {
        if (employeeIds.Count == 0)
        {
            return new Dictionary<Guid, EmployeeDeleteEvaluation>();
        }

        var ids = employeeIds.Distinct().ToList();
        var reasonsByEmployee = ids.ToDictionary(id => id, _ => new List<string>());

        foreach (var row in await db.Payslips
                     .Where(p => ids.Contains(p.EmployeeId))
                     .GroupBy(p => p.EmployeeId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "phiếu lương");
        }

        foreach (var row in await db.WorkSchedules
                     .Where(ws => ids.Contains(ws.EmployeeUserId))
                     .GroupBy(ws => ws.EmployeeUserId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "lịch ca");
        }

        foreach (var row in await db.ScheduleRegistrations
                     .Where(sr => ids.Contains(sr.EmployeeUserId))
                     .GroupBy(sr => sr.EmployeeUserId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "đăng ký ca");
        }

        foreach (var row in await db.PenaltyTickets
                     .Where(pt => ids.Contains(pt.EmployeeId))
                     .GroupBy(pt => pt.EmployeeId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "phiếu phạt");
        }

        foreach (var row in await db.Employees
                     .Where(e => e.DirectManagerEmployeeId != null && ids.Contains(e.DirectManagerEmployeeId.Value))
                     .GroupBy(e => e.DirectManagerEmployeeId!.Value)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "nhân viên báo cáo trực tiếp");
        }

        foreach (var row in await db.KpiResults
                     .Where(k => ids.Contains(k.EmployeeId))
                     .GroupBy(k => k.EmployeeId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "bản ghi KPI");
        }

        foreach (var row in await db.KpiSalaries
                     .Where(k => ids.Contains(k.EmployeeId))
                     .GroupBy(k => k.EmployeeId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "lương KPI");
        }

        foreach (var row in await db.KpiEmployeeTargets
                     .Where(k => ids.Contains(k.EmployeeId))
                     .GroupBy(k => k.EmployeeId)
                     .Select(g => new { EmployeeId = g.Key, Count = g.Count() })
                     .ToListAsync(cancellationToken))
        {
            AddReason(reasonsByEmployee, row.EmployeeId, row.Count, "chỉ tiêu KPI");
        }

        return reasonsByEmployee.ToDictionary(
            kvp => kvp.Key,
            kvp => kvp.Value.Count == 0
                ? new EmployeeDeleteEvaluation(true, null)
                : new EmployeeDeleteEvaluation(false, BuildMessage(kvp.Value)));
    }

    private static void AddReason(
        Dictionary<Guid, List<string>> reasonsByEmployee,
        Guid employeeId,
        int count,
        string label)
    {
        if (count > 0 && reasonsByEmployee.TryGetValue(employeeId, out var reasons))
        {
            reasons.Add($"{count} {label}");
        }
    }

    private static string BuildMessage(List<string> reasons) =>
        "Không thể xóa vì còn dữ liệu liên quan: "
        + string.Join(", ", reasons)
        + ". Nên chuyển trạng thái sang \"Đã nghỉ việc\" thay vì xóa.";
}
