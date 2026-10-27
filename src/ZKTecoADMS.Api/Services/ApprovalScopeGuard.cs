using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Chặn duyệt / từ chối / bỏ duyệt / chi đơn của nhân viên NGOÀI phạm vi quản lý — trước đây API duyệt chỉ kiểm quyền
/// chức năng, nên Trưởng phòng A gọi thẳng API vẫn duyệt được đơn phòng B.
/// Quy tắc (theo thứ tự):
///  1. Tài khoản toàn quyền (Admin / SuperAdmin / Agent) → được, kể cả đơn của chính mình.
///  2. Đơn của chính người duyệt → không được tự duyệt.
///  3. Giám đốc / Kế toán (xem cả cửa hàng) → được.
///  4. Người được giao duyệt đơn này (bước trong chuỗi duyệt, hoặc quản lý ghi trên đơn) → được, dù không phải cấp trên.
///  5. Người duyệt CHƯA được giao phạm vi nào (không cấp dưới, phòng ban, chi nhánh) → được như trước (cửa hàng nhỏ
///     chỉ có chủ + một quản lý chưa phân phòng ban vẫn duyệt bình thường; phân phạm vi xong mới bị giới hạn).
///  6. Còn lại: nhân viên phải thuộc phạm vi (cấp dưới + phòng ban / chi nhánh được giao), cùng quy tắc màn Nhân viên.
/// </summary>
public sealed class ApprovalScopeGuard(ZKTecoDbContext db, IDataScopeService dataScope, IHttpContextAccessor http)
{
    public enum Kind { Leave, Advance, Overtime, AttendanceCorrection, Penalty }

    public const string OutOfScopeMessage = "Nhân viên này không thuộc phạm vi bạn quản lý";
    public const string OwnRequestMessage = "Không thể tự duyệt đơn của chính mình";

    /// <summary>Người có đơn + người duyệt có được giao xử lý đơn này không.</summary>
    public sealed record Target(Guid? EmployeeId, Guid? UserId, bool AssignedToApprover);

    /// <summary>Lý do chặn (null = được phép). Không tìm thấy đơn → null, để API trả lỗi «không tìm thấy» như cũ.</summary>
    public async Task<string?> DenyAsync(Kind kind, Guid id, Guid approverUserId, Guid storeId, string role, CancellationToken ct = default)
    {
        if (ModulePermissionDefaults.IsSuperRole(role)) return null;
        var target = await TargetAsync(kind, id, storeId, approverUserId, ct);
        if (target == null) return null;
        var (scope, selfEmployeeId) = await ApproverAsync(approverUserId, storeId, role, ct);
        return Decide(role, approverUserId, selfEmployeeId, target, scope);
    }

    (AiAssistantScope, Guid?)? _approver;

    /// <summary>Phạm vi + hồ sơ nhân viên của người duyệt (tính một lần mỗi yêu cầu — duyệt lô không truy vấn lại).</summary>
    async Task<(AiAssistantScope Scope, Guid? SelfEmployeeId)> ApproverAsync(Guid approverUserId, Guid storeId, string role, CancellationToken ct)
    {
        if (_approver is { } cached) return cached;
        var scope = await AiAssistantScope.ResolveAsync(db, dataScope, http.HttpContext, approverUserId, storeId, role, ct);
        var self = scope.SelfEmployeeId ?? await db.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == approverUserId && e.StoreId == storeId && e.Deleted == null)
            .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
        _approver = (scope, self);
        return (scope, self);
    }

    /// <summary>Quyết định thuần (không truy vấn) — tách riêng để kiểm thử.</summary>
    public static string? Decide(string role, Guid approverUserId, Guid? approverEmployeeId, Target target, AiAssistantScope scope)
    {
        if (ModulePermissionDefaults.IsSuperRole(role)) return null;
        if ((target.UserId is Guid u && u == approverUserId)
            || (target.EmployeeId is Guid e && approverEmployeeId is Guid se && e == se))
            return OwnRequestMessage;
        if (AiAssistantScope.IsWholeStoreRole(role) || scope.WholeStore) return null;
        if (target.AssignedToApprover) return null;
        if (!scope.ManagesOthers) return null;
        var inScope = (target.EmployeeId is Guid te && scope.HasEmployee(te)) || (target.UserId is Guid tu && scope.HasUser(tu));
        return inScope ? null : OutOfScopeMessage;
    }

    async Task<Target?> TargetAsync(Kind kind, Guid id, Guid storeId, Guid approver, CancellationToken ct) => kind switch
    {
        Kind.Leave => await db.Leaves.AsNoTracking()
            .Where(l => l.Id == id && l.StoreId == storeId)
            .Select(l => new Target(l.EmployeeId, l.EmployeeUserId,
                l.ManagerId == approver || db.LeaveApprovalRecords.Any(r => r.LeaveId == l.Id && r.AssignedUserId == approver)))
            .FirstOrDefaultAsync(ct),
        Kind.Advance => await db.AdvanceRequests.AsNoTracking()
            .Where(a => a.Id == id && a.StoreId == storeId)
            .Select(a => new Target(a.EmployeeId, a.EmployeeUserId,
                db.AdvanceApprovalRecords.Any(r => r.AdvanceRequestId == a.Id && r.AssignedUserId == approver)))
            .FirstOrDefaultAsync(ct),
        Kind.Overtime => await db.Overtimes.AsNoTracking()
            .Where(o => o.Id == id && o.StoreId == storeId)
            .Select(o => new Target(null, o.EmployeeUserId, o.ManagerId == approver))
            .FirstOrDefaultAsync(ct),
        Kind.AttendanceCorrection => await db.AttendanceCorrectionRequests.AsNoTracking()
            .Where(c => c.Id == id && c.StoreId == storeId)
            .Select(c => new Target(null, c.EmployeeUserId,
                db.ApprovalRecords.Any(r => r.CorrectionRequestId == c.Id && r.AssignedUserId == approver)))
            .FirstOrDefaultAsync(ct),
        _ => await db.PenaltyTickets.AsNoTracking()
            .Where(t => t.Id == id && t.StoreId == storeId && t.Deleted == null)
            .Select(t => new Target(t.EmployeeId, null, false))
            .FirstOrDefaultAsync(ct),
    };
}
