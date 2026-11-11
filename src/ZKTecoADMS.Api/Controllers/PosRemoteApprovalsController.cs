using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Duyệt từ xa» (xem <see cref="PosRemoteApprovals"/>): máy POS gửi yêu cầu + hỏi kết quả; chủ / quản lý xem danh sách
/// và duyệt / từ chối trên SBOX BOSS. Duyệt xong máy chủ cấp mã <see cref="PosAfterBillApproval"/> như khi quản lý nhập
/// mật khẩu tại máy — người duyệt được ghi vào lịch sử hủy / trả như cũ.
/// </summary>
[ApiController]
[Route("api/pos/remote-approvals")]
[Authorize]
public sealed class PosRemoteApprovalsController(
    ZKTecoDbContext db,
    IPushNotificationService push,
    ILogger<PosRemoteApprovalsController> logger) : AuthenticatedControllerBase
{
    public record CreateRequest(string? Reason, string? Detail, decimal? Amount);
    public record RejectRequest(string? Reason);

    static readonly string[] ApproverRoles = ["StoreOwner", "Admin", "Director", "Manager"];

    static object View(PosRemoteApprovals.Request r, bool withToken) => new
    {
        id = r.Id,
        status = r.Status,
        reason = r.Reason,
        detail = r.Detail,
        amount = r.Amount,
        requestedBy = r.RequestedBy,
        createdAt = r.CreatedAt,
        expiresAt = r.ExpiresAt,
        expiresInSeconds = Math.Max(0, (int)(r.ExpiresAt - DateTime.UtcNow).TotalSeconds),
        decidedBy = r.DecidedBy,
        rejectReason = r.RejectReason,
        approvalToken = withToken && r.Status == "approved" ? r.ApprovalToken : null,
        tokenExpiresInSeconds = (int)PosAfterBillApproval.Lifetime.TotalSeconds,
    };

    async Task<string> DisplayNameAsync(CancellationToken ct)
    {
        var uid = CurrentUserId;
        var u = await db.Users.AsNoTracking().Where(x => x.Id == uid)
            .Select(x => new { x.LastName, x.FirstName, x.Email }).FirstOrDefaultAsync(ct);
        var n = $"{u?.LastName} {u?.FirstName}".Trim();
        return n.Length > 0 ? n : (u?.Email ?? CurrentUserEmail ?? "Nhân viên");
    }

    /// <summary>Thu ngân gửi yêu cầu (sau câu lỗi «Cần quản lý duyệt…»). Đẩy thông báo tới chủ / quản lý.</summary>
    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] CreateRequest req, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var reason = (req.Reason ?? "").Trim();
        reason = reason.StartsWith(PosAfterBillApproval.DeniedPrefix, StringComparison.OrdinalIgnoreCase)
            ? reason[PosAfterBillApproval.DeniedPrefix.Length..].TrimStart(':', ' ')
            : reason;
        if (reason.Length == 0) reason = "Thao tác sau tạm tính";
        var name = await DisplayNameAsync(ct);
        var r = PosRemoteApprovals.Create(storeId, HttpContext.BranchContext()?.CurrentBranchId, CurrentUserId, name,
            reason, req.Detail?.Trim(), req.Amount);
        if (r == null)
            return Ok(AppResponse<object>.Fail("Đang có quá nhiều yêu cầu chờ duyệt — nhờ chủ / quản lý xử lý trước"));

        try
        {
            var approverIds = await db.Users.AsNoTracking()
                .Where(u => u.StoreId == storeId && u.IsActive && u.Role != null && ApproverRoles.Contains(u.Role))
                .Select(u => u.Id)
                .ToListAsync(ct);
            // Không gửi cho chính người xin (chủ / quản lý thao tác trên máy POS).
            approverIds.Remove(CurrentUserId);
            if (approverIds.Count > 0)
            {
                // Push trực tiếp (không qua bộ định dạng) → tự ghi tên người xin; thêm chi tiết / số tiền khi máy POS gửi kèm.
                var title = reason.Length > 30 ? $"Cần duyệt: {reason[..30].TrimEnd()}…" : $"Cần duyệt: {reason}";
                var parts = new List<string> { name };
                var detail = req.Detail?.Trim();
                if (!string.IsNullOrEmpty(detail))
                    parts.Add(detail.Length > 40 ? detail[..40].TrimEnd() + "…" : detail);
                if (req.Amount is decimal amount && amount != 0)
                    parts.Add(amount.ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN")) + "đ");
                parts.Add("mở SBOX BOSS để duyệt");
                await push.PushToUsersAsync(approverIds, title, string.Join(" · ", parts),
                    data: new Dictionary<string, string> { ["type"] = "pos_remote_approval", ["id"] = r.Id.ToString() },
                    androidTag: $"pos-approval-{r.Id:N}", ct: ct);
            }
        }
        catch (Exception ex)
        {
            // Không có push vẫn duyệt được: SBOX BOSS tự hỏi danh sách «Cần duyệt».
            logger.LogWarning(ex, "Không gửi được thông báo duyệt từ xa {Id}", r.Id);
        }
        return Ok(AppResponse<object>.Success(View(r, withToken: false)));
    }

    /// <summary>Máy POS hỏi kết quả; chỉ người gửi nhận mã duyệt.</summary>
    [HttpGet("{id:guid}")]
    public ActionResult<AppResponse<object>> Get(Guid id)
    {
        var r = PosRemoteApprovals.Get(RequiredStoreId, id);
        if (r == null) return Ok(AppResponse<object>.Fail("Yêu cầu không còn (đã hết hạn)"));
        return Ok(AppResponse<object>.Success(View(r, withToken: r.RequestedByUserId == CurrentUserId)));
    }

    [HttpPost("{id:guid}/cancel")]
    public ActionResult<AppResponse<object>> Cancel(Guid id)
    {
        var r = PosRemoteApprovals.Get(RequiredStoreId, id);
        if (r == null || r.RequestedByUserId != CurrentUserId)
            return Ok(AppResponse<object>.Fail("Không tìm thấy yêu cầu"));
        PosRemoteApprovals.Decide(r, "cancelled", r.RequestedBy, null, null);
        return Ok(AppResponse<object>.Success(View(r, withToken: false)));
    }

    /// <summary>Yêu cầu đang chờ của cửa hàng (SBOX BOSS).</summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public ActionResult<AppResponse<object>> Pending() =>
        Ok(AppResponse<object>.Success(PosRemoteApprovals.Pending(RequiredStoreId).Select(r => View(r, false)).ToList()));

    [HttpPost("{id:guid}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<object>>> Approve(Guid id, CancellationToken ct)
    {
        if (!PosAfterBillApproval.IsManagerRole(CurrentUserRole))
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<object>.Fail("Chỉ chủ / quản lý được duyệt"));
        var storeId = RequiredStoreId;
        var r = PosRemoteApprovals.Get(storeId, id);
        if (r == null) return Ok(AppResponse<object>.Fail("Yêu cầu không còn (đã hết hạn)"));
        var approver = CurrentUserEmail ?? CurrentUserId.ToString();
        var token = PosAfterBillApproval.Issue(HttpContext.RequestServices, storeId, approver);
        if (!PosRemoteApprovals.Decide(r, "approved", await DisplayNameAsync(ct), token, null))
            return Ok(AppResponse<object>.Fail(r.Status == "approved" ? "Yêu cầu đã được duyệt" : "Yêu cầu đã hết hạn hoặc đã xử lý"));
        return Ok(AppResponse<object>.Success(View(r, withToken: false)));
    }

    [HttpPost("{id:guid}/reject")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<object>>> Reject(Guid id, [FromBody] RejectRequest? req, CancellationToken ct)
    {
        if (!PosAfterBillApproval.IsManagerRole(CurrentUserRole))
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<object>.Fail("Chỉ chủ / quản lý được duyệt"));
        var r = PosRemoteApprovals.Get(RequiredStoreId, id);
        if (r == null) return Ok(AppResponse<object>.Fail("Yêu cầu không còn (đã hết hạn)"));
        if (!PosRemoteApprovals.Decide(r, "rejected", await DisplayNameAsync(ct), null, req?.Reason?.Trim()))
            return Ok(AppResponse<object>.Fail("Yêu cầu đã hết hạn hoặc đã xử lý"));
        return Ok(AppResponse<object>.Success(View(r, withToken: false)));
    }
}
