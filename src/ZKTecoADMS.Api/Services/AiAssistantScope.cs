using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Phạm vi dữ liệu nhân sự của người hỏi trợ lý — cùng quy tắc với API (EmployeesController):
///  • Admin / Giám đốc / Kế toán (và tài khoản toàn quyền) → cả cửa hàng;
///  • nhân viên tự phục vụ (Nhân viên, Thu ngân, Phục vụ, Người dùng) → chỉ bản thân;
///  • còn lại (Quản lý, Trưởng phòng, vai trò tự tạo) → cấp dưới + phòng ban / chi nhánh được giao + bản thân.
/// Mọi tra cứu trực tiếp CSDL của trợ lý (tìm nhân viên, phiếu, đơn chờ duyệt, tình hình hôm nay) đều lọc qua đây —
/// báo cáo thì đã lọc sẵn vì trợ lý gọi lại API bằng phiên của người hỏi.
/// </summary>
public sealed class AiAssistantScope
{
    readonly HashSet<Guid> _employeeIds;
    readonly HashSet<Guid> _userIds;

    AiAssistantScope(bool wholeStore, bool selfOnly, Guid? selfEmployeeId, HashSet<Guid> employeeIds, HashSet<Guid> userIds)
    {
        WholeStore = wholeStore;
        SelfOnly = selfOnly;
        SelfEmployeeId = selfEmployeeId;
        _employeeIds = employeeIds;
        _userIds = userIds;
    }

    public bool WholeStore { get; }

    /// <summary>Chỉ thấy dữ liệu của chính mình.</summary>
    public bool SelfOnly { get; }

    public Guid? SelfEmployeeId { get; }

    /// <summary>Có quản lý người khác (được lập phiếu / duyệt đơn cho người khác).</summary>
    public bool ManagesOthers => WholeStore || _employeeIds.Any(id => id != SelfEmployeeId);

    /// <summary>Id nhân viên trong phạm vi (null = cả cửa hàng) — dùng cho Contains trong truy vấn EF.</summary>
    public List<Guid>? EmployeeIds => WholeStore ? null : _employeeIds.ToList();

    /// <summary>Id tài khoản đăng nhập của nhân viên trong phạm vi (null = cả cửa hàng).</summary>
    public List<Guid>? UserIds => WholeStore ? null : _userIds.ToList();

    public bool HasEmployee(Guid employeeId) => WholeStore || _employeeIds.Contains(employeeId);

    public bool HasUser(Guid userId) => WholeStore || _userIds.Contains(userId);

    public string Describe() => WholeStore
        ? "toàn cửa hàng"
        : SelfOnly ? "chỉ dữ liệu của chính bạn" : $"{_employeeIds.Count} nhân viên trong phạm vi bạn quản lý (gồm bạn)";

    public static AiAssistantScope Whole() => new(true, false, null, [], []);

    public static AiAssistantScope Of(Guid? selfEmployeeId, IEnumerable<(Guid EmployeeId, Guid? UserId)> employees, bool selfOnly)
    {
        var list = employees.ToList();
        return new(false, selfOnly, selfEmployeeId,
            list.Select(e => e.EmployeeId).ToHashSet(),
            list.Where(e => e.UserId.HasValue).Select(e => e.UserId!.Value).ToHashSet());
    }

    static readonly string[] WholeStoreRoles = [nameof(Roles.Director), nameof(Roles.Accountant)];

    static readonly string[] SelfServiceRoles =
        [nameof(Roles.Employee), nameof(Roles.Cashier), nameof(Roles.Waiter), nameof(Roles.User)];

    public static bool IsWholeStoreRole(string role) =>
        ModulePermissionDefaults.IsSuperRole(role) || WholeStoreRoles.Contains(role, StringComparer.OrdinalIgnoreCase);

    public static bool IsSelfServiceRole(string role) => SelfServiceRoles.Contains(role, StringComparer.OrdinalIgnoreCase);

    public static async Task<AiAssistantScope> ResolveAsync(
        ZKTecoDbContext db, IDataScopeService dataScope, HttpContext? http,
        Guid userId, Guid storeId, string role, CancellationToken ct)
    {
        if (IsWholeStoreRole(role)) return Whole();

        var self = await db.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId && e.Deleted == null)
            .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
        var ids = new HashSet<Guid>();
        if (self is Guid s) ids.Add(s);

        var selfOnly = IsSelfServiceRole(role);
        if (!selfOnly)
        {
            foreach (var id in await dataScope.GetSubordinateEmployeeIdsAsync(userId, storeId)) ids.Add(id);
            // Quản lý chi nhánh thấy cả nhân viên thuộc chi nhánh mình được phép (như màn Nhân viên).
            if (http.BranchContext() is { StoreUsesBranches: true, AllowedBranchIds: { } allowed } bctx)
            {
                var branches = allowed.ToList();
                var hq = bctx.HeadquarterBranchId ?? Guid.Empty;
                foreach (var id in await db.Employees.AsNoTracking()
                             .Where(e => e.StoreId == storeId && e.Deleted == null && branches.Contains(e.BranchId ?? hq))
                             .Select(e => e.Id).ToListAsync(ct))
                    ids.Add(id);
            }
        }

        var idList = ids.ToList();
        var rows = await db.Employees.AsNoTracking()
            .Where(e => idList.Contains(e.Id))
            .Select(e => new { e.Id, e.ApplicationUserId })
            .ToListAsync(ct);
        return Of(self, rows.Select(r => (r.Id, r.ApplicationUserId)), selfOnly);
    }
}
