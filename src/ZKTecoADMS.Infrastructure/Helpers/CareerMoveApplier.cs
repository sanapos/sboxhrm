using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Điều chuyển / bổ nhiệm có ngày hiệu lực tương lai được lưu ở trạng thái chờ (IsActive = false).
/// Đến ngày hiệu lực thì cập nhật phòng ban, chức vụ trên hồ sơ nhân viên và đánh dấu đã áp dụng.
/// Chạy định kỳ (nền) và mỗi khi mở quá trình công tác của nhân viên.
/// </summary>
public static class CareerMoveApplier
{
    static readonly string[] MoveKinds = ["transfer", "appointment", "promotion"];

    public static DateTime TodayVn => DateTime.UtcNow.AddHours(7).Date;

    public static async Task<int> ApplyDueAsync(ZKTecoDbContext db, DateTime todayVn, Guid? employeeId = null, CancellationToken ct = default)
    {
        var due = await db.EmployeeCareerRecords.IgnoreQueryFilters().AsTracking()
            .Where(r => r.Deleted == null && !r.IsActive && MoveKinds.Contains(r.Kind) && r.EffectiveDate <= todayVn
                && (employeeId == null || r.EmployeeId == employeeId))
            .OrderBy(r => r.EffectiveDate).ThenBy(r => r.CreatedAt)
            .ToListAsync(ct);
        if (due.Count == 0) return 0;
        var empIds = due.Select(r => r.EmployeeId).Distinct().ToList();
        var emps = await db.Employees.IgnoreQueryFilters().AsTracking()
            .Where(e => empIds.Contains(e.Id) && e.Deleted == null)
            .ToDictionaryAsync(e => e.Id, ct);
        var asgIds = due.Where(r => r.OrgAssignmentId != null).Select(r => r.OrgAssignmentId!.Value).ToList();
        var deptOfAsg = await db.OrgAssignments.IgnoreQueryFilters().AsNoTracking()
            .Where(a => asgIds.Contains(a.Id))
            .ToDictionaryAsync(a => a.Id, a => a.DepartmentId, ct);
        foreach (var r in due)
        {
            r.IsActive = true;
            r.UpdatedAt = DateTime.UtcNow;
            if (!emps.TryGetValue(r.EmployeeId, out var e)) continue;
            if (r.OrgAssignmentId is Guid a && deptOfAsg.TryGetValue(a, out var deptId)) e.DepartmentId = deptId;
            if (!string.IsNullOrWhiteSpace(r.ToDepartment)) e.Department = r.ToDepartment;
            if (!string.IsNullOrWhiteSpace(r.ToPosition)) e.Position = r.ToPosition;
            e.UpdatedAt = DateTime.UtcNow;
        }
        await db.SaveChangesAsync(ct);
        return due.Count;
    }
}
