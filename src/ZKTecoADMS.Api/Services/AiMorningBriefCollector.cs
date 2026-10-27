using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Truy vấn số liệu bản tin sáng thẳng từ CSDL (chạy nền, không có phiên người dùng nên không gọi lại API báo cáo).
/// Cùng quy ước với trợ lý / báo cáo: đơn đã hoàn thành, giờ VN; hàng cần nhập = tồn ≤ tồn tối thiểu (như «Gợi ý nhập hàng»);
/// chấm công = giờ tường VN trong DB.
/// </summary>
public static class AiMorningBriefCollector
{
    const int TopItems = 3;
    const int StockItems = 8;

    static readonly PosProductType[] TrackedTypes = [PosProductType.Goods, PosProductType.Material, PosProductType.Topping];

    public static async Task<AiMorningBriefStoreData> CollectStoreAsync(
        ZKTecoDbContext db, Guid storeId, DateTime briefDate, IReadOnlyCollection<string> sections, CancellationToken ct)
    {
        var name = await db.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.Name).FirstOrDefaultAsync(ct);
        var data = new AiMorningBriefStoreData
        {
            StoreId = storeId, StoreName = name ?? "", BriefDate = briefDate.Date,
            Sections = sections.ToHashSet(StringComparer.OrdinalIgnoreCase),
        };
        if (data.Sections.Contains(AiMorningBriefOptions.Sales)) data.Sales = await SalesAsync(db, storeId, data.DataDate, ct);
        if (data.Sections.Contains(AiMorningBriefOptions.Stock)) data.Stock = await StockAsync(db, storeId, ct);
        if (data.Sections.Contains(AiMorningBriefOptions.Debt)) data.Debt = await DebtAsync(db, storeId, data.DataDate, ct);
        if (data.Sections.Contains(AiMorningBriefOptions.Attendance)) data.Attendance = await AttendanceAsync(db, storeId, data.DataDate, ct);
        return data;
    }

    // ─── Bán hàng ─────────────────────────────────────────────────

    static IQueryable<Domain.Entities.PosSaleOrder> CompletedOrders(ZKTecoDbContext db, Guid storeId, DateTime fromVn, DateTime toVnExclusive)
    {
        // SaleDate / CreatedAt lưu UTC (mặt số) → đổi khung ngày VN sang UTC.
        var from = VnTimeHelper.VnLocalToUtcWall(fromVn);
        var to = VnTimeHelper.VnLocalToUtcWall(toVnExclusive);
        return db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= from && (o.SaleDate ?? o.CreatedAt) < to);
    }

    static async Task<(int Count, decimal Sum)> AggAsync(IQueryable<Domain.Entities.PosSaleOrder> q, CancellationToken ct) =>
        (await q.CountAsync(ct), await q.SumAsync(o => o.Total, ct));

    public static async Task<BriefSales> SalesAsync(ZKTecoDbContext db, Guid storeId, DateTime day, CancellationToken ct)
    {
        day = day.Date;
        var y = await AggAsync(CompletedOrders(db, storeId, day, day.AddDays(1)), ct);
        var lw = await AggAsync(CompletedOrders(db, storeId, day.AddDays(-7), day.AddDays(-6)), ct);
        var month = await AggAsync(CompletedOrders(db, storeId, new DateTime(day.Year, day.Month, 1), day.AddDays(1)), ct);
        var ids = CompletedOrders(db, storeId, day, day.AddDays(1)).Select(o => o.Id);
        var top = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => ids.Contains(l.SaleOrderId))
            .GroupBy(l => l.ProductName)
            .Select(g => new { Name = g.Key, Qty = g.Sum(x => x.Qty), Amount = g.Sum(x => x.LineTotal) })
            .OrderByDescending(x => x.Amount)
            .Take(TopItems)
            .ToListAsync(ct);
        return new BriefSales(y.Count, y.Sum, lw.Count, lw.Sum, month.Count, month.Sum,
            top.Select(t => new BriefTopItem(t.Name, t.Qty, t.Amount)).ToList());
    }

    // ─── Tồn kho ──────────────────────────────────────────────────

    public static async Task<BriefStock> StockAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct)
    {
        var q = db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && TrackedTypes.Contains(p.ProductType)
                        && p.MinStockQty > 0 && p.OnHandQty <= p.MinStockQty);
        var count = await q.CountAsync(ct);
        var outCount = await q.CountAsync(p => p.OnHandQty <= 0, ct);
        var items = await q.OrderBy(p => p.OnHandQty).ThenBy(p => p.Name).Take(StockItems)
            .Select(p => new BriefStockItem(p.Name, p.OnHandQty, p.MinStockQty))
            .ToListAsync(ct);
        return new BriefStock(count, outCount, items);
    }

    // ─── Công nợ khách ────────────────────────────────────────────

    public static async Task<BriefDebt> DebtAsync(ZKTecoDbContext db, Guid storeId, DateTime day, CancellationToken ct)
    {
        var debtors = db.PosCustomers.AsNoTracking().Where(c => c.StoreId == storeId && c.Deleted == null && c.CurrentDebt > 0);
        var count = await debtors.CountAsync(ct);
        var total = count == 0 ? 0m : await debtors.SumAsync(c => c.CurrentDebt, ct);
        var over = await debtors.Where(c => c.DebtLimit != null && c.DebtLimit > 0 && c.CurrentDebt > c.DebtLimit)
            .OrderByDescending(c => c.CurrentDebt).Take(3)
            .Select(c => new BriefDebtor(c.Name, c.CurrentDebt, c.DebtLimit))
            .ToListAsync(ct);
        var newDebt = CompletedOrders(db, storeId, day.Date, day.Date.AddDays(1)).Where(o => o.Total > o.PaidAmount);
        var n = await newDebt.CountAsync(ct);
        var amount = n == 0 ? 0m : await newDebt.SumAsync(o => o.Total - o.PaidAmount, ct);
        return new BriefDebt(total, count, amount, n, over);
    }

    // ─── Chấm công hôm qua (đi trễ / vắng không phép) ─────────────

    public static async Task<BriefAttendance> AttendanceAsync(ZKTecoDbContext db, Guid storeId, DateTime day, CancellationToken ct)
    {
        day = day.Date;
        var end = day.AddDays(1);
        var holiday = await db.Holidays.AsNoTracking()
            .Where(h => h.Deleted == null && h.Date >= day && h.Date < end && (h.StoreId == null || h.StoreId == storeId))
            .Select(h => h.Name).FirstOrDefaultAsync(ct);

        var schedules = await (
                from ws in db.WorkSchedules.AsNoTracking()
                where ws.StoreId == storeId && ws.Date >= day && ws.Date < end && !ws.IsDayOff
                      && (ws.ShiftId != null || ws.StartTime != null)
                join st in db.ShiftTemplates.AsNoTracking() on ws.ShiftId equals st.Id into sts
                from st in sts.DefaultIfEmpty()
                select new
                {
                    ws.EmployeeUserId,
                    ws.StartTime,
                    ShiftStart = st != null ? (TimeSpan?)st.StartTime : null,
                    Grace = st != null ? st.LateGraceMinutes : 5,
                })
            .ToListAsync(ct);
        var byUser = schedules.GroupBy(s => s.EmployeeUserId).ToDictionary(g => g.Key, g => g.First());
        if (byUser.Count == 0) return new BriefAttendance(0, holiday, [], []);

        var userIds = byUser.Keys.ToList();
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus != EmployeeWorkStatus.Resigned
                        && e.ApplicationUserId != null && userIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new { e.Id, UserId = e.ApplicationUserId!.Value, e.LastName, e.FirstName, e.EmployeeCode })
            .ToListAsync(ct);
        if (emps.Count == 0) return new BriefAttendance(0, holiday, [], []);

        var empIds = emps.Select(e => e.Id).ToList();
        var codes = emps.Select(e => e.EmployeeCode).Where(c => !string.IsNullOrEmpty(c)).ToList();
        var byCode = emps.Where(e => !string.IsNullOrEmpty(e.EmployeeCode)).GroupBy(e => e.EmployeeCode)
            .ToDictionary(g => g.Key, g => g.First().Id);
        // AttendanceLogs.EmployeeId = DeviceUser.Id (không phải Employees.Id).
        var duMap = (await db.DeviceUsers.AsNoTracking()
                .Where(du => du.EmployeeId != null && empIds.Contains(du.EmployeeId.Value))
                .Select(du => new { du.Id, Emp = du.EmployeeId!.Value })
                .ToListAsync(ct))
            .GroupBy(x => x.Id).ToDictionary(g => g.Key, g => g.First().Emp);
        var duIds = duMap.Keys.ToList();

        var present = new HashSet<Guid>();
        var firstIn = new Dictionary<Guid, DateTime>();
        void Seen(Guid emp, DateTime vn, bool checkIn)
        {
            present.Add(emp);
            if (checkIn && (!firstIn.TryGetValue(emp, out var cur) || vn < cur)) firstIn[emp] = vn;
        }

        foreach (var log in await db.AttendanceLogs.AsNoTracking()
                     .Where(a => a.AttendanceTime >= day && a.AttendanceTime < end
                                 && ((a.EmployeeId != null && duIds.Contains(a.EmployeeId.Value)) || codes.Contains(a.PIN)))
                     .Select(a => new { a.EmployeeId, a.PIN, a.AttendanceTime, a.AttendanceState })
                     .ToListAsync(ct))
        {
            Guid? emp = log.EmployeeId is Guid du && duMap.TryGetValue(du, out var e1) ? e1
                : !string.IsNullOrEmpty(log.PIN) && byCode.TryGetValue(log.PIN, out var e2) ? e2 : null;
            if (emp is Guid id)
                Seen(id, VnTimeHelper.AttendanceWallClock(log.AttendanceTime), log.AttendanceState == AttendanceStates.CheckIn);
        }

        var byUserStr = emps.ToDictionary(e => e.UserId.ToString(), e => e.Id);
        var mobileKeys = byUserStr.Keys.Concat(codes).ToList();
        foreach (var m in await db.MobileAttendanceRecords.AsNoTracking()
                     .Where(m => m.StoreId == storeId && m.IsActive && m.PunchTime >= day && m.PunchTime < end
                                 && mobileKeys.Contains(m.OdooEmployeeId))
                     .Select(m => new { m.OdooEmployeeId, m.PunchTime, m.PunchType })
                     .ToListAsync(ct))
        {
            Guid? emp = byUserStr.TryGetValue(m.OdooEmployeeId, out var e1) ? e1
                : byCode.TryGetValue(m.OdooEmployeeId, out var e2) ? e2 : null;
            if (emp is Guid id) Seen(id, VnTimeHelper.AttendanceWallClock(m.PunchTime), m.PunchType == 0);
        }

        var onLeave = (await db.Leaves.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                            && l.StartDate < end && l.EndDate >= day && userIds.Contains(l.EmployeeUserId))
                .Select(l => l.EmployeeUserId)
                .ToListAsync(ct))
            .ToHashSet();

        var late = new List<BriefLate>();
        var absent = new List<BriefAbsent>();
        foreach (var e in emps)
        {
            var name = $"{e.LastName} {e.FirstName}".Trim();
            var sch = byUser[e.UserId];
            if (!present.Contains(e.Id))
            {
                if (!onLeave.Contains(e.UserId)) absent.Add(new BriefAbsent(e.Id, name));
                continue;
            }
            if ((sch.StartTime ?? sch.ShiftStart) is not TimeSpan start ||!firstIn.TryGetValue(e.Id, out var arrived)) continue;
            if (arrived.TimeOfDay > start + TimeSpan.FromMinutes(Math.Max(sch.Grace, 0)))
                late.Add(new BriefLate(e.Id, name, (int)(arrived.TimeOfDay - start).TotalMinutes));
        }
        return new BriefAttendance(emps.Count, holiday,
            late.OrderByDescending(l => l.Minutes).ToList(),
            holiday == null ? absent.OrderBy(a => a.Name).ToList() : []);
    }

    // ─── Chờ duyệt (theo quyền + phạm vi từng người nhận) ─────────

    static bool CanApprove(IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuper, params string[] modules) =>
        isSuper || modules.Any(m => perms.TryGetValue(m, out var p) && p.CanApprove);

    public static async Task<BriefApprovals?> ApprovalsAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuper,
        AiAssistantScope scope, CancellationToken ct)
    {
        if (scope.SelfOnly) return null;
        var users = scope.UserIds;
        var emps = scope.EmployeeIds;
        int? leave = null, adv = null, ot = null, corr = null, pen = null;
        if (CanApprove(perms, isSuper, "Leave"))
            leave = await db.Leaves.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Pending)
                .Where(l => users == null || users.Contains(l.EmployeeUserId))
                .CountAsync(ct);
        if (CanApprove(perms, isSuper, "AdvanceRequests"))
            adv = await db.AdvanceRequests.AsNoTracking()
                .Where(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Pending)
                .Where(a => users == null || (a.EmployeeUserId != null && users.Contains(a.EmployeeUserId.Value))
                            || (emps != null && a.EmployeeId != null && emps.Contains(a.EmployeeId.Value)))
                .CountAsync(ct);
        if (CanApprove(perms, isSuper, "Overtime"))
            ot = await db.Overtimes.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Status == OvertimeStatus.Pending)
                .Where(o => users == null || users.Contains(o.EmployeeUserId))
                .CountAsync(ct);
        if (CanApprove(perms, isSuper, "AttendanceApproval", "AttendanceCorrection"))
            corr = await db.AttendanceCorrectionRequests.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.Status == CorrectionStatus.Pending)
                .Where(c => users == null || users.Contains(c.EmployeeUserId))
                .CountAsync(ct);
        if (CanApprove(perms, isSuper, "PenaltyTickets"))
            pen = await db.PenaltyTickets.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Status == PenaltyTicketStatus.Pending)
                .Where(p => emps == null || emps.Contains(p.EmployeeId))
                .CountAsync(ct);
        var r = new BriefApprovals(leave, adv, ot, corr, pen);
        return r.Any ? r : null;
    }

    // ─── Người nhận ───────────────────────────────────────────────

    static readonly string[] ManagerRoles = [nameof(Roles.Manager), nameof(Roles.Director), nameof(Roles.DepartmentHead)];
    static readonly string[] PlatformRoles = [nameof(Roles.SuperAdmin), nameof(Roles.Agent)];

    public sealed record Recipient(Guid UserId, string Role);

    /// <summary>
    /// Người nhận theo nhóm đã chọn: owner = chủ cửa hàng + Admin; manager = Quản lý / Giám đốc / Trưởng phòng;
    /// accountant = Kế toán; sales_viewers = mọi tài khoản có quyền xem «Báo cáo bán hàng». Chỉ tài khoản đang hoạt động.
    /// </summary>
    public static async Task<List<Recipient>> SelectRecipientsAsync(
        ZKTecoDbContext db, IModulePermissionService permissions, Guid storeId, IReadOnlyCollection<string> groups,
        CancellationToken ct)
    {
        if (groups.Count == 0) return [];
        var ownerId = await db.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.OwnerId).FirstOrDefaultAsync(ct);
        var users = await db.Users.AsNoTracking()
            .Where(u => u.IsActive && (u.StoreId == storeId || (ownerId != null && u.Id == ownerId)))
            .Select(u => new { u.Id, u.Role })
            .ToListAsync(ct);
        bool Has(string g) => groups.Contains(g, StringComparer.OrdinalIgnoreCase);
        var result = new List<Recipient>();
        foreach (var u in users)
        {
            var role = u.Role ?? "";
            if (PlatformRoles.Contains(role, StringComparer.OrdinalIgnoreCase)) continue;
            var pick = (Has(AiMorningBriefOptions.Owner)
                        && (u.Id == ownerId || string.Equals(role, nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)))
                       || (Has(AiMorningBriefOptions.Manager) && ManagerRoles.Contains(role, StringComparer.OrdinalIgnoreCase))
                       || (Has(AiMorningBriefOptions.Accountant)
                           && string.Equals(role, nameof(Roles.Accountant), StringComparison.OrdinalIgnoreCase));
            if (!pick && Has(AiMorningBriefOptions.SalesViewers))
            {
                pick = ModulePermissionDefaults.IsSuperRole(role)
                       || (await permissions.GetEffectivePermissionsAsync(u.Id, role, storeId, ct))
                       .TryGetValue("PosSalesReport", out var p) && p.CanView;
            }
            if (pick) result.Add(new Recipient(u.Id, role));
        }
        return result;
    }
}
