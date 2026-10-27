using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Duyệt / từ chối đơn thay quản lý: nghỉ phép, ứng lương, tăng ca, bổ sung chấm công, phiếu phạt.
/// Chỉ đơn của nhân viên TRONG PHẠM VI quản lý (API duyệt của app không tự kiểm phạm vi — trợ lý chặn ở đây),
/// không tự duyệt đơn của chính mình, mỗi loại cần quyền Duyệt của chức năng tương ứng.
/// </summary>
public sealed partial class AiAssistantActions
{
    /// <summary>Một loại chứng từ của công cụ nhiều loại: nhãn hiển thị, chức năng + quyền cần.</summary>
    sealed record KindRule(string Label, string Module, char Need);

    const string ReviewModule = "@review";

    static readonly Dictionary<string, KindRule> ReviewKinds = new()
    {
        ["leave"] = new("Đơn nghỉ phép", "Leave", 'A'),
        ["advance"] = new("Ứng lương", "AdvanceRequests", 'A'),
        ["overtime"] = new("Tăng ca", "Overtime", 'A'),
        ["attendance_fix"] = new("Bổ sung chấm công", "AttendanceCorrection", 'A'),
        ["penalty"] = new("Phiếu phạt", "PenaltyTickets", 'A'),
    };

    static readonly Def[] ReviewDefs =
    [
        new("propose_review_requests", ReviewModule, 'A', true,
            "DUYỆT hoặc TỪ CHỐI một hay nhiều đơn chờ duyệt cùng loại (lấy id từ find_pending_requests).",
            new()
            {
                ["kind"] = ("STRING", "Loại đơn"),
                ["ids"] = ("STRING", "Id các đơn, cách nhau dấu phẩy"),
                ["decision"] = ("STRING", "approve (duyệt) | reject (từ chối)"),
                ["reason"] = ("STRING", "Lý do (bắt buộc khi từ chối)"),
                ["approved_amount"] = ("NUMBER", "Ứng lương: số tiền duyệt nếu thấp hơn số xin (chỉ khi duyệt 1 đơn)"),
            }, ["kind", "ids", "decision"]),
    ];

    /// <summary>Các loại (của công cụ nhiều loại) người hỏi được làm — theo quyền + gói dịch vụ.</summary>
    List<string> AllowedKinds(Ctx c, string module)
    {
        var map = KindsOf(module);
        return map.Where(kv => Can(c, kv.Value.Module, kv.Value.Need)).Select(kv => kv.Key).ToList();
    }

    static Dictionary<string, KindRule> KindsOf(string module) => module switch
    {
        ReviewModule => ReviewKinds,
        DeleteModule => DeleteKinds,
        CancelModule => CancelKinds,
        ContactModule => ContactKinds,
        _ => OpsKindsOf(module),
    };

    /// <summary>Tham số «kind» chỉ liệt kê loại được phép — model không đề xuất loại tài khoản không làm được.</summary>
    Dictionary<string, (string Type, string Desc)> KindParams(Ctx c, Def d)
    {
        if (!d.Module.StartsWith('@') || !d.Params.ContainsKey("kind")) return d.Params;
        var map = KindsOf(d.Module);
        var kinds = AllowedKinds(c, d.Module).Select(k => $"{k} ({map[k].Label.ToLower(Vi)})");
        var ps = new Dictionary<string, (string Type, string Desc)>(d.Params)
        {
            ["kind"] = ("STRING", string.Join(" | ", kinds)),
        };
        return ps;
    }

    void AddReviewFinders(Ctx c, List<Def> allowed, List<object> decls)
    {
        if (allowed.All(d => d.Module != ReviewModule)) return;
        decls.Add(Fn("find_pending_requests",
            "Danh sách đơn CHỜ DUYỆT của nhân viên trong phạm vi quản lý → id, người, nội dung. Dùng trước khi duyệt / từ chối.",
            new()
            {
                ["kind"] = ("STRING", string.Join(" | ", AllowedKinds(c, ReviewModule)) + " | all"),
                ["employee_id"] = ("STRING", "Chỉ đơn của nhân viên này (find_employees)"),
            }, []));
    }

    static readonly Dictionary<LeaveType, string> LeaveLabels = new()
    {
        [LeaveType.AnnualLeave] = "Phép năm", [LeaveType.Holiday] = "Nghỉ lễ", [LeaveType.PersonalPaid] = "Việc riêng có lương",
        [LeaveType.PersonalUnpaid] = "Việc riêng không lương", [LeaveType.SickLeave] = "Ốm", [LeaveType.MaternityLeave] = "Thai sản",
        [LeaveType.CompensatoryLeave] = "Nghỉ bù", [LeaveType.LongTermLeave] = "Nghỉ dài hạn",
    };

    /// <summary>Đơn chờ duyệt (đã lọc phạm vi, bỏ đơn của chính mình).</summary>
    sealed record PendingReq(Guid Id, string Kind, Guid? EmployeeId, Guid? UserId, string Detail, decimal? Amount);

    async Task<List<PendingReq>> PendingRequestsAsync(Ctx c, string kind, IReadOnlyCollection<Guid>? onlyIds, CancellationToken ct)
    {
        var users = c.Scope.UserIds;
        var emps = c.Scope.EmployeeIds;
        var ids = onlyIds?.ToList();
        var since = DateTime.UtcNow.AddDays(-120);
        var self = c.UserId;
        List<PendingReq> rows = kind switch
        {
            "leave" => (await db.Leaves.AsNoTracking()
                    .Where(l => l.StoreId == c.StoreId && l.Status == LeaveStatus.Pending && l.CreatedAt >= since)
                    .Where(l => ids == null || ids.Contains(l.Id))
                    .Where(l => users == null || users.Contains(l.EmployeeUserId))
                    .OrderBy(l => l.StartDate).Take(40)
                    .Select(l => new { l.Id, l.EmployeeUserId, l.Type, l.StartDate, l.EndDate, l.IsHalfShift, l.Reason })
                    .ToListAsync(ct))
                .Select(l => new PendingReq(l.Id, kind, null, l.EmployeeUserId,
                    $"{(LeaveLabels.TryGetValue(l.Type, out var lt) ? lt : l.Type.ToString())} {l.StartDate:dd/MM}"
                    + (l.EndDate.Date != l.StartDate.Date ? $"–{l.EndDate:dd/MM}" : "") + (l.IsHalfShift ? " (nửa ca)" : "")
                    + (string.IsNullOrWhiteSpace(l.Reason) ? "" : $" · {l.Reason}"), null)).ToList(),
            "advance" => (await db.AdvanceRequests.AsNoTracking()
                    .Where(a => a.StoreId == c.StoreId && a.Status == AdvanceRequestStatus.Pending && a.CreatedAt >= since)
                    .Where(a => ids == null || ids.Contains(a.Id))
                    .Where(a => (users == null || (a.EmployeeUserId != null && users.Contains(a.EmployeeUserId.Value)))
                                || (emps != null && a.EmployeeId != null && emps.Contains(a.EmployeeId.Value)))
                    .OrderBy(a => a.RequestDate).Take(40)
                    .Select(a => new { a.Id, a.EmployeeUserId, a.EmployeeId, a.Amount, a.Reason, a.RequestDate, a.ForMonth })
                    .ToListAsync(ct))
                .Select(a => new PendingReq(a.Id, kind, a.EmployeeId, a.EmployeeUserId,
                    $"{Vnd(a.Amount)} · xin ngày {a.RequestDate:dd/MM}" + (a.ForMonth is int m ? $" · trừ lương T{m}" : "")
                    + (string.IsNullOrWhiteSpace(a.Reason) ? "" : $" · {a.Reason}"), a.Amount)).ToList(),
            "overtime" => (await db.Overtimes.AsNoTracking()
                    .Where(o => o.StoreId == c.StoreId && o.Status == OvertimeStatus.Pending && o.CreatedAt >= since)
                    .Where(o => ids == null || ids.Contains(o.Id))
                    .Where(o => users == null || users.Contains(o.EmployeeUserId))
                    .OrderBy(o => o.Date).Take(40)
                    .Select(o => new { o.Id, o.EmployeeUserId, o.Date, o.StartTime, o.EndTime, o.PlannedHours, o.Reason })
                    .ToListAsync(ct))
                .Select(o => new PendingReq(o.Id, kind, null, o.EmployeeUserId,
                    $"{o.Date:dd/MM} {o.StartTime:hh\\:mm}–{o.EndTime:hh\\:mm} ({o.PlannedHours:0.#}h)"
                    + (string.IsNullOrWhiteSpace(o.Reason) ? "" : $" · {o.Reason}"), null)).ToList(),
            "attendance_fix" => (await db.AttendanceCorrectionRequests.AsNoTracking()
                    .Where(r => r.StoreId == c.StoreId && r.Status == CorrectionStatus.Pending && r.CreatedAt >= since)
                    .Where(r => ids == null || ids.Contains(r.Id))
                    .Where(r => users == null || users.Contains(r.EmployeeUserId))
                    .OrderBy(r => r.CreatedAt).Take(40)
                    .Select(r => new { r.Id, r.EmployeeUserId, r.Action, r.NewDate, r.NewTime, r.NewPunchType, r.Reason })
                    .ToListAsync(ct))
                .Select(r => new PendingReq(r.Id, kind, null, r.EmployeeUserId,
                    (r.Action switch { CorrectionAction.Add => "Thêm giờ", CorrectionAction.Edit => "Sửa giờ", _ => "Xóa giờ" })
                    + (r.NewDate is DateTime nd ? $" {nd:dd/MM}" : "") + (r.NewTime is TimeSpan nt ? $" {nt:hh\\:mm}" : "")
                    + (string.IsNullOrWhiteSpace(r.NewPunchType) ? "" : $" ({r.NewPunchType})")
                    + (string.IsNullOrWhiteSpace(r.Reason) ? "" : $" · {r.Reason}"), null)).ToList(),
            "penalty" => (await db.PenaltyTickets.AsNoTracking()
                    .Where(t => t.StoreId == c.StoreId && t.Status == PenaltyTicketStatus.Pending && t.CreatedAt >= since)
                    .Where(t => ids == null || ids.Contains(t.Id))
                    .Where(t => emps == null || emps.Contains(t.EmployeeId))
                    .OrderBy(t => t.ViolationDate).Take(40)
                    .Select(t => new { t.Id, t.EmployeeId, t.TicketCode, t.Type, t.Amount, t.ViolationDate, t.Description })
                    .ToListAsync(ct))
                .Select(t => new PendingReq(t.Id, kind, t.EmployeeId, null,
                    $"{t.TicketCode} · {(PenaltyLabels.TryGetValue(t.Type.ToString(), out var pl) ? pl : t.Type.ToString())} {Vnd(t.Amount)} ngày {t.ViolationDate:dd/MM}"
                    + (string.IsNullOrWhiteSpace(t.Description) ? "" : $" · {t.Description}"), t.Amount)).ToList(),
            _ => [],
        };
        // Không tự duyệt đơn của mình (trừ tài khoản toàn quyền — chủ cửa hàng).
        if (!c.IsSuper)
            rows = rows.Where(r => r.UserId != self && (r.EmployeeId == null || r.EmployeeId != c.Scope.SelfEmployeeId)).ToList();
        return rows;
    }

    async Task<Dictionary<Guid, string>> NamesByUserAsync(Ctx c, IEnumerable<Guid?> userIds, IEnumerable<Guid?> empIds, CancellationToken ct)
    {
        var u = userIds.Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
        var e = empIds.Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
        var rows = await db.Employees.AsNoTracking()
            .Where(x => x.StoreId == c.StoreId && ((x.ApplicationUserId != null && u.Contains(x.ApplicationUserId.Value)) || e.Contains(x.Id)))
            .Select(x => new { x.Id, x.ApplicationUserId, Name = (x.FirstName + " " + x.LastName).Trim() })
            .ToListAsync(ct);
        var map = new Dictionary<Guid, string>();
        foreach (var r in rows)
        {
            map[r.Id] = r.Name;
            if (r.ApplicationUserId is Guid au) map[au] = r.Name;
        }
        return map;
    }

    static string NameOf(Dictionary<Guid, string> names, PendingReq r) =>
        (r.EmployeeId is Guid e && names.TryGetValue(e, out var n1) ? n1 : null)
        ?? (r.UserId is Guid u && names.TryGetValue(u, out var n2) ? n2 : null) ?? "(không rõ)";

    async Task<object> FindPendingRequestsAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var want = (S(a, "kind") ?? "all").Trim().ToLowerInvariant();
        var kinds = AllowedKinds(c, ReviewModule).Where(k => want is "all" or "" || k == want).ToList();
        if (kinds.Count == 0) return new { error = "Tài khoản không có quyền duyệt loại đơn này." };
        var emp = G(a, "employee_id");
        var all = new List<PendingReq>();
        foreach (var k in kinds) all.AddRange(await PendingRequestsAsync(c, k, null, ct));
        var names = await NamesByUserAsync(c, all.Select(x => x.UserId), all.Select(x => x.EmployeeId), ct);
        if (emp is Guid eid)
        {
            var uid = await db.Employees.AsNoTracking().Where(x => x.Id == eid).Select(x => x.ApplicationUserId).FirstOrDefaultAsync(ct);
            all = all.Where(x => x.EmployeeId == eid || (uid != null && x.UserId == uid)).ToList();
        }
        if (all.Count == 0)
            return new { ket_qua = "Không có đơn nào chờ bạn duyệt" + (c.Scope.WholeStore ? "" : " (trong phạm vi bạn quản lý)") + "." };
        return new
        {
            tong = all.Count,
            ket_qua = all.GroupBy(x => x.Kind).Select(g => new
            {
                loai = g.Key, ten_loai = ReviewKinds[g.Key].Label, so_don = g.Count(),
                don = g.Take(15).Select(x => new { id = x.Id, nhan_vien = NameOf(names, x), noi_dung = x.Detail }),
            }),
        };
    }

    async Task<Pending> ReviewAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var kind = (S(a, "kind") ?? "").Trim().ToLowerInvariant();
        if (!AllowedKinds(c, ReviewModule).Contains(kind))
            throw new ActionError("Tài khoản không có quyền duyệt loại đơn này.");
        var approve = (S(a, "decision") ?? "").Trim().ToLowerInvariant() is "approve" or "duyệt" or "duyet" or "yes";
        var reason = S(a, "reason");
        if (!approve && string.IsNullOrWhiteSpace(reason)) throw new ActionError("Từ chối cần lý do — hỏi người dùng lý do.");
        var ids = (S(a, "ids") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => Guid.TryParse(x, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).Distinct().ToList();
        if (ids.Count == 0) throw new ActionError("Thiếu id đơn — gọi find_pending_requests.");

        var reqs = await PendingRequestsAsync(c, kind, ids, ct);
        if (reqs.Count == 0)
            throw new ActionError("Không có đơn nào trong số này đang chờ bạn duyệt (đã xử lý, ngoài phạm vi quản lý, hoặc là đơn của chính bạn).");
        var names = await NamesByUserAsync(c, reqs.Select(x => x.UserId), reqs.Select(x => x.EmployeeId), ct);
        var approvedAmount = approve && reqs.Count == 1 && kind == "advance" ? ParseMoney(S(a, "approved_amount")) : null;
        if (approvedAmount is decimal aa && (aa <= 0 || aa > (reqs[0].Amount ?? aa)))
            throw new ActionError("Số tiền duyệt phải lớn hơn 0 và không quá số xin ứng.");

        var steps = new List<Step>();
        var undo = new List<Step?>();
        var lines = new List<Line>();
        foreach (var r in reqs)
        {
            var who = NameOf(names, r);
            var (step, back) = ReviewStep(kind, r.Id, approve, reason, approvedAmount);
            steps.Add(step with { Label = who });
            undo.Add(back);
            lines.Add(new(who, r.Detail + (approvedAmount is decimal x ? $" → duyệt {Vnd(x)}" : "")));
        }
        var skipped = ids.Count - reqs.Count;
        var warnings = new List<string>();
        if (skipped > 0) warnings.Add($"Bỏ qua {skipped} đơn không còn chờ bạn duyệt / ngoài phạm vi.");
        if (!approve) warnings.Add("Lý do từ chối: " + reason);
        var label = ReviewKinds[kind].Label.ToLower(Vi);
        return New(c, approve ? "review_approve" : "review_reject",
                (approve ? "Duyệt " : "Từ chối ") + label, lines, "POST", steps[0].Path, null,
                kind switch
                {
                    "leave" => "Leave", "advance" => "AdvanceRequests", "overtime" => "Overtime",
                    "attendance_fix" => "AttendanceCorrection", _ => "PenaltyTickets",
                }, warnings)
            with
            {
                Steps = steps, Batch = true, BatchUndo = undo,
                // Duyệt / từ chối hàng loạt nhiều đơn — xác nhận hai lần.
                Risk = reqs.Count > 5 ? "high" : "normal",
            };
    }

    /// <summary>Lời gọi API duyệt / từ chối một đơn + cách hoàn tác (null = API không có).</summary>
    static (Step Do, Step? Undo) ReviewStep(string kind, Guid id, bool approve, string? reason, decimal? approvedAmount)
    {
        string J(object o) => JsonSerializer.Serialize(o, Json);
        return kind switch
        {
            "leave" => (approve
                    ? new Step("POST", $"/api/Leaves/{id}/approve", "{}")
                    : new Step("POST", $"/api/Leaves/{id}/reject", J(new { rejectionReason = reason })),
                new Step("POST", $"/api/Leaves/{id}/undo-approve", null)),
            "advance" => (new Step("POST", $"/api/AdvanceRequests/{id}/approve",
                    J(new { requestId = id, isApproved = approve, rejectionReason = approve ? null : reason, approvedAmount })),
                new Step("POST", $"/api/AdvanceRequests/{id}/undo-approve", null)),
            "overtime" => (approve
                    ? new Step("POST", $"/api/Overtimes/{id}/approve", null)
                    : new Step("POST", $"/api/Overtimes/{id}/reject", J(new { rejectionReason = reason })),
                null),
            "attendance_fix" => (new Step("POST", $"/api/AttendanceCorrections/{id}/approve",
                    J(new { requestId = id, isApproved = approve, approverNote = reason })),
                approve ? new Step("POST", $"/api/AttendanceCorrections/{id}/undo-approve", null) : null),
            _ => (approve
                    ? new Step("POST", $"/api/PenaltyTickets/{id}/approve", J(new { note = reason }))
                    : new Step("POST", $"/api/PenaltyTickets/{id}/cancel", J(new { reason })),
                approve ? new Step("POST", $"/api/PenaltyTickets/{id}/unapprove", null) : null),
        };
    }
}
