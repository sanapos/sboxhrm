using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trợ lý ảo AI cá nhân - chat với Gemini có context người dùng (nghỉ phép, chấm công, lương, công việc).
/// Chỉ truy cập dữ liệu cá nhân của chính user đang đăng nhập.
/// </summary>
[ApiController]
[Route("api/ai/assistant")]
[Authorize]
public class AiAssistantController(
    ZKTecoDbContext db,
    IModulePermissionService modulePermissionService,
    IGeminiAiService geminiAiService,
    ILogger<AiAssistantController> logger) : AuthenticatedControllerBase
{
    public class ChatMessage
    {
        public string Role { get; set; } = "user"; // "user" | "assistant"
        public string Content { get; set; } = "";
    }

    public class ChatRequest
    {
        public List<ChatMessage> Messages { get; set; } = new();
        public string? Provider { get; set; } // "gemini" (only supported provider)
    }

    public class ChatResponse
    {
        public string Reply { get; set; } = "";
        public string Provider { get; set; } = "";
        public List<string> Actions { get; set; } = new();
        /// <summary>Structured create intents: "type,key=val,key=val" — Flutter parses and calls API directly.</summary>
        public List<string> Creates { get; set; } = new();
        /// <summary>Guide deep links: "basic/leave", "advanced/kpi".</summary>
        public List<string> Guides { get; set; } = new();
    }

    /// <summary>
    /// Chat với trợ lý ảo. Server nạp context cá nhân (profile, leave balance, attendance, payslip gần đây)
    /// rồi chuyển tới Gemini. AI có thể trả về text + tag ACTION gợi ý Flutter điều hướng.
    /// </summary>
    [HttpPost("chat")]
    public async Task<IActionResult> Chat([FromBody] ChatRequest dto, CancellationToken ct)
    {
        try
        {
            if (dto.Messages == null || dto.Messages.Count == 0)
                return BadRequest(AppResponse<ChatResponse>.Fail("Thiếu nội dung chat"));

            var lastUserMessage = dto.Messages.LastOrDefault(m =>
                string.Equals(m.Role, "user", StringComparison.OrdinalIgnoreCase));
            if (lastUserMessage == null || string.IsNullOrWhiteSpace(lastUserMessage.Content))
                return BadRequest(AppResponse<ChatResponse>.Fail("Tin nhắn trống"));

            var role = CurrentUserRole;
            var permMap = await modulePermissionService.GetEffectivePermissionsAsync(
                CurrentUserId, role, CurrentStoreId, ct);
            var isSuperUser = ModulePermissionDefaults.IsSuperRole(role);
            var allowedActions = AiAssistantPermissionRules.AllowedActionTags(permMap, isSuperUser);
            var allowedCreates = AiAssistantPermissionRules.AllowedCreateExamples(permMap, isSuperUser);

            var contextText = await AiAssistantContextBuilder.BuildAsync(
                db, CurrentUserId, RequiredStoreId, role, logger, ct, permMap, isSuperUser);
            contextText += "\n\n=== QUYỀN TÀI KHOẢN ===\n";
            contextText += AiAssistantPermissionRules.BuildPermissionsSummary(permMap, isSuperUser, role);

            var extra = await AiAssistantQueryTools.BuildExtraContextAsync(
                db, CurrentUserId, RequiredStoreId, role, lastUserMessage.Content,
                permMap, isSuperUser, logger, ct);
            if (!string.IsNullOrWhiteSpace(extra))
                contextText += "\n\n" + extra;

            // Gợi ý GUIDE từ kết quả search (kể cả khi model quên tag)
            var helpHits = AiAssistantHelpCorpus.Search(lastUserMessage.Content, topK: 4);
            var suggestedGuides = helpHits
                .Select(h => $"{h.Mode}/{h.StepId}")
                .Distinct()
                .ToList();
            // Bổ sung ACTION từ help nếu user hỏi hướng dẫn
            foreach (var hit in helpHits)
            {
                foreach (var tag in hit.ActionTags)
                {
                    if (AiAssistantPermissionRules.CanAction(tag, permMap, isSuperUser)
                        && !allowedActions.Contains(tag))
                        allowedActions.Add(tag);
                }
            }

            var systemPrompt = AiAssistantPromptBuilder.Build(
                contextText, allowedActions, allowedCreates, suggestedGuides);
            logger.LogInformation(
                "AI assistant context for {UserId}: {Length} chars, digest: {Digest}",
                CurrentUserId,
                contextText.Length,
                AiAssistantContextBuilder.BuildDigest(contextText));

            var chatTurns = dto.Messages
                .Where(m => !string.IsNullOrWhiteSpace(m.Content))
                .Where(m => !IsBoilerplateAssistantMessage(m))
                .TakeLast(16)
                .Select(m => (
                    Role: string.Equals(m.Role, "assistant", StringComparison.OrdinalIgnoreCase)
                        ? "assistant" : "user",
                    Content: m.Content.Trim()))
                .ToList();

            // Ghim tóm tắt dữ liệu vào câu hỏi cuối — tránh model bỏ qua system instruction dài.
            if (chatTurns.Count > 0)
            {
                var digest = AiAssistantContextBuilder.BuildDigest(contextText);
                var last = chatTurns[^1];
                if (last.Role == "user")
                {
                    chatTurns[^1] = (
                        "user",
                        $"[Dữ liệu hệ thống đã nạp]\n{digest}\n\n[Câu hỏi]\n{last.Content}");
                }
            }

            if (!geminiAiService.IsConfigured || !geminiAiService.IsEnabled)
            {
                return BadRequest(AppResponse<ChatResponse>.Fail(
                    "Gemini AI chưa được bật hoặc chưa cấu hình API key. Vào Cài đặt → Thiết lập AI (Gemini) để kích hoạt trợ lý."));
            }

            if (string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(AppResponse<ChatResponse>.Fail(
                    "DeepSeek đã ngừng hỗ trợ. Hệ thống chỉ dùng Google Gemini cho trợ lý ảo."));
            }

            var reply = await geminiAiService.GenerateAssistantChatAsync(
                systemPrompt, chatTurns, 2048, ct);
            const string usedProvider = "gemini";

            // Extract [[ACTION:xxx]] tags
            var actions = new List<string>();
            var cleaned = reply ?? string.Empty;
            var start = 0;
            while (true)
            {
                var i = cleaned.IndexOf("[[ACTION:", start, StringComparison.Ordinal);
                if (i < 0) break;
                var j = cleaned.IndexOf("]]", i, StringComparison.Ordinal);
                if (j < 0) break;
                var tag = cleaned.Substring(i + 9, j - (i + 9)).Trim();
                if (!string.IsNullOrWhiteSpace(tag)) actions.Add(tag);
                cleaned = cleaned.Remove(i, j - i + 2);
                start = i;
            }

            // Extract [[CREATE:xxx]] tags (structured create intents)
            var creates = new List<string>();
            var cStart = 0;
            while (true)
            {
                var ci = cleaned.IndexOf("[[CREATE:", cStart, StringComparison.Ordinal);
                if (ci < 0) break;
                var cj = cleaned.IndexOf("]]", ci, StringComparison.Ordinal);
                if (cj < 0) break;
                var ctag = cleaned.Substring(ci + 9, cj - (ci + 9)).Trim();
                if (!string.IsNullOrWhiteSpace(ctag))
                {
                    var validated = AiAssistantCreateValidator.ExtractAndValidate(
                        ctag, permMap, isSuperUser, out _);
                    creates.AddRange(validated);
                }
                cleaned = cleaned.Remove(ci, cj - ci + 2);
                cStart = ci;
            }

            // Extract [[GUIDE:mode/stepId]]
            var guides = new List<string>();
            var gStart = 0;
            while (true)
            {
                var gi = cleaned.IndexOf("[[GUIDE:", gStart, StringComparison.Ordinal);
                if (gi < 0) break;
                var gj = cleaned.IndexOf("]]", gi, StringComparison.Ordinal);
                if (gj < 0) break;
                var gtag = cleaned.Substring(gi + 8, gj - (gi + 8)).Trim();
                if (AiAssistantHelpCorpus.TryParseGuideTag(gtag, out var mode, out var stepId))
                    guides.Add($"{mode}/{stepId}");
                cleaned = cleaned.Remove(gi, gj - gi + 2);
                gStart = gi;
            }

            // Nếu hỏi hướng dẫn mà model quên GUIDE → gắn gợi ý top hit
            if (guides.Count == 0 && suggestedGuides.Count > 0
                && (lastUserMessage.Content.Contains("cách", StringComparison.OrdinalIgnoreCase)
                    || lastUserMessage.Content.Contains("hướng dẫn", StringComparison.OrdinalIgnoreCase)
                    || lastUserMessage.Content.Contains("làm sao", StringComparison.OrdinalIgnoreCase)
                    || lastUserMessage.Content.Contains("ở đâu", StringComparison.OrdinalIgnoreCase)))
            {
                guides.Add(suggestedGuides[0]);
            }

            actions = actions
                .Where(a => AiAssistantPermissionRules.CanAction(a, permMap, isSuperUser))
                .Distinct()
                .ToList();
            creates = creates.Distinct().ToList();
            guides = guides.Distinct().Take(2).ToList();

            return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
            {
                Reply = cleaned.Trim(),
                Provider = usedProvider,
                Actions = actions,
                Creates = creates,
                Guides = guides
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "AI Assistant chat failed");
            return StatusCode(500, AppResponse<ChatResponse>.Fail("Lỗi trợ lý AI: " + ex.Message));
        }
    }

    private static bool IsBoilerplateAssistantMessage(ChatMessage m)
    {
        if (!string.Equals(m.Role, "assistant", StringComparison.OrdinalIgnoreCase))
            return false;
        var c = m.Content.Trim();
        return c.StartsWith("Xin chào! Tôi là trợ lý", StringComparison.Ordinal)
               || c.StartsWith("⚠️", StringComparison.Ordinal)
               || c.StartsWith("❌", StringComparison.Ordinal)
               || c.StartsWith("✅ Đã tạo", StringComparison.Ordinal)
               || c.StartsWith("📋 Đã mở", StringComparison.Ordinal);
    }

}
#if false // removed legacy context — see AiAssistantContextBuilder
    private async Task<string> BuildUserContextAsync_Legacy(CancellationToken ct)
    {
        var userId = CurrentUserId;
        var storeId = CurrentStoreId;
        var role = string.Empty;
        try { role = CurrentUserRole; } catch { /* token may not have role */ }
        var buf = new StringBuilder();

        try
        {
            buf.AppendLine($"Vai trò: {(string.IsNullOrEmpty(role) ? "(không rõ)" : role)}");

            // Profile
            var emp = await db.Employees
                .AsNoTracking()
                .Where(e => e.ApplicationUserId == userId)
                .Select(e => new
                {
                    e.Id,
                    e.EmployeeCode,
                    e.FirstName,
                    e.LastName,
                    e.DepartmentId,
                    e.Position,
                    e.JoinDate
                })
                .FirstOrDefaultAsync(ct);

            if (emp != null)
            {
                var dept = emp.DepartmentId.HasValue
                    ? await db.Departments.AsNoTracking()
                        .Where(d => d.Id == emp.DepartmentId.Value)
                        .Select(d => d.Name)
                        .FirstOrDefaultAsync(ct)
                    : null;

                buf.AppendLine($"Họ tên: {emp.LastName} {emp.FirstName}");
                buf.AppendLine($"Mã NV: {emp.EmployeeCode}");
                if (!string.IsNullOrEmpty(emp.Position)) buf.AppendLine($"Chức vụ: {emp.Position}");
                if (!string.IsNullOrEmpty(dept)) buf.AppendLine($"Phòng ban: {dept}");
                if (emp.JoinDate.HasValue) buf.AppendLine($"Ngày vào làm: {emp.JoinDate.Value:dd/MM/yyyy}");
            }
            else
            {
                buf.AppendLine("(Chưa liên kết hồ sơ nhân viên)");
            }

            var today = DateTime.UtcNow.Date;
            var startOfYear = new DateTime(today.Year, 1, 1);

            // Leaves: pending + recent + total this year
            var leaves = await db.Leaves
                .AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= today.AddDays(-90))
                .OrderByDescending(l => l.StartDate)
                .Take(10)
                .Select(l => new { l.StartDate, l.EndDate, l.Status, l.Type, l.Reason })
                .ToListAsync(ct);

            var leavesYearStats = await db.Leaves
                .AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= startOfYear)
                .GroupBy(l => l.Status)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync(ct);

            if (leavesYearStats.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Tổng số đơn nghỉ năm nay (theo trạng thái):");
                foreach (var s in leavesYearStats)
                    buf.AppendLine($"- {s.Status}: {s.Count} đơn");
            }
            if (leaves.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Lịch sử nghỉ phép (90 ngày gần nhất):");
                foreach (var l in leaves)
                {
                    buf.AppendLine(
                        $"- {l.StartDate:dd/MM/yyyy}..{l.EndDate:dd/MM/yyyy} | Loại {(int)l.Type} | {l.Status}");
                }
            }

            // Attendance: last 7 days count + 30 days summary
            var weekAgo = today.AddDays(-7);
            var monthAgo = today.AddDays(-30);
            var empId = emp?.Id;
            if (empId.HasValue)
            {
                var attCount7 = await db.AttendanceLogs
                    .AsNoTracking()
                    .Where(a => a.AttendanceTime >= weekAgo && a.EmployeeId == empId.Value)
                    .CountAsync(ct);
                var attCount30 = await db.AttendanceLogs
                    .AsNoTracking()
                    .Where(a => a.AttendanceTime >= monthAgo && a.EmployeeId == empId.Value)
                    .CountAsync(ct);
                buf.AppendLine();
                buf.AppendLine($"Chấm công 7 ngày gần đây: {attCount7} lượt | 30 ngày: {attCount30} lượt");
            }

            // Advance requests recent
            var advances = await db.AdvanceRequests
                .AsNoTracking()
                .Where(a => a.EmployeeUserId == userId && a.RequestDate >= today.AddDays(-180))
                .OrderByDescending(a => a.RequestDate)
                .Take(5)
                .Select(a => new { a.RequestDate, a.Amount, a.Status, a.Reason })
                .ToListAsync(ct);
            if (advances.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Yêu cầu ứng lương (180 ngày gần nhất):");
                foreach (var a in advances)
                    buf.AppendLine($"- {a.RequestDate:dd/MM/yyyy} | {a.Amount:N0}đ | {a.Status} | {a.Reason}");
            }

            // Last 3 payslips
            var payslips = await db.Payslips
                .AsNoTracking()
                .Where(p => p.EmployeeUserId == userId)
                .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
                .Take(3)
                .Select(p => new { p.Year, p.Month, p.NetSalary, p.Status })
                .ToListAsync(ct);
            if (payslips.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Phiếu lương gần nhất:");
                foreach (var p in payslips)
                    buf.AppendLine($"- {p.Month:D2}/{p.Year}: {p.NetSalary:N0}đ ({p.Status})");
            }

            // Manager-only: pending approvals + today attendance/absent summary
            var roleLower = role.ToLowerInvariant();
            if (roleLower == "owner" || roleLower == "admin" || roleLower == "director" ||
                roleLower == "manager" || roleLower == "departmenthead")
            {
                try
                {
                    var pendingLeaves = await db.Leaves.AsNoTracking()
                        .Where(l => l.StoreId == storeId && l.Status == Domain.Enums.LeaveStatus.Pending)
                        .CountAsync(ct);
                    var pendingAdv = await db.AdvanceRequests.AsNoTracking()
                        .Where(a => a.StoreId == storeId && a.Status == Domain.Enums.AdvanceRequestStatus.Pending)
                        .CountAsync(ct);
                    buf.AppendLine();
                    buf.AppendLine("Đơn chờ duyệt (toàn cửa hàng):");
                    buf.AppendLine($"- Nghỉ phép: {pendingLeaves} | Ứng lương: {pendingAdv}");
                }
                catch { /* ignore */ }

                // Today's attendance vs leave cross-reference (nghỉ có phép / nghỉ không phép)
                try
                {
                    var todayVn = DateTime.UtcNow.AddHours(7).Date;
                    var tomorrowVn = todayVn.AddDays(1);

                    // All active employees in this store
                    var activeEmps = await db.Employees
                        .AsNoTracking()
                        .Where(e => e.StoreId == storeId && e.WorkStatus == Domain.Enums.EmployeeWorkStatus.Active)
                        .Select(e => new { e.Id, e.ApplicationUserId, e.FirstName, e.LastName })
                        .ToListAsync(ct);

                    var activeEmpIds = activeEmps.Select(e => e.Id).ToList();
                    var activeUserIds = activeEmps
                        .Where(e => e.ApplicationUserId.HasValue)
                        .Select(e => e.ApplicationUserId!.Value)
                        .ToList();

                    // Employees who checked in today (any punch counts as present)
                    var checkedInEmpIds = await db.AttendanceLogs
                        .AsNoTracking()
                        .Where(a => a.AttendanceTime >= todayVn && a.AttendanceTime < tomorrowVn
                                    && a.EmployeeId.HasValue && activeEmpIds.Contains(a.EmployeeId.Value))
                        .Select(a => a.EmployeeId!.Value)
                        .Distinct()
                        .ToListAsync(ct);

                    // Employees with approved leave covering today
                    var approvedLeaveUserIds = await db.Leaves
                        .AsNoTracking()
                        .Where(l => l.StoreId == storeId
                                    && l.Status == Domain.Enums.LeaveStatus.Approved
                                    && l.StartDate.Date <= todayVn && l.EndDate.Date >= todayVn
                                    && activeUserIds.Contains(l.EmployeeUserId))
                        .Select(l => l.EmployeeUserId)
                        .Distinct()
                        .ToListAsync(ct);

                    var absentWithLeave = activeEmps
                        .Where(e => !checkedInEmpIds.Contains(e.Id)
                                    && e.ApplicationUserId.HasValue
                                    && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value))
                        .ToList();

                    var absentNoLeave = activeEmps
                        .Where(e => !checkedInEmpIds.Contains(e.Id)
                                    && !(e.ApplicationUserId.HasValue
                                         && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value)))
                        .ToList();

                    buf.AppendLine();
                    buf.AppendLine($"Tình hình nhân sự hôm nay ({todayVn:dd/MM/yyyy}):");
                    buf.AppendLine($"- Tổng nhân viên (đang làm việc): {activeEmps.Count}");
                    buf.AppendLine($"- Đã chấm công: {checkedInEmpIds.Count}");
                    buf.AppendLine($"- Vắng CÓ PHÉP (đơn nghỉ được duyệt): {absentWithLeave.Count}");
                    buf.AppendLine($"- Vắng KHÔNG PHÉP (không chấm công, không có đơn duyệt): {absentNoLeave.Count}");

                    if (absentWithLeave.Count > 0)
                    {
                        buf.AppendLine("Danh sách nghỉ CÓ PHÉP hôm nay:");
                        foreach (var e in absentWithLeave.Take(20))
                            buf.AppendLine($"  • {e.LastName} {e.FirstName}");
                        if (absentWithLeave.Count > 20)
                            buf.AppendLine($"  ...và {absentWithLeave.Count - 20} người khác");
                    }

                    if (absentNoLeave.Count > 0)
                    {
                        buf.AppendLine("Danh sách vắng KHÔNG PHÉP hôm nay:");
                        foreach (var e in absentNoLeave.Take(20))
                            buf.AppendLine($"  • {e.LastName} {e.FirstName}");
                        if (absentNoLeave.Count > 20)
                            buf.AppendLine($"  ...và {absentNoLeave.Count - 20} người khác");
                    }
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Failed to load today absent summary");
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "BuildUserContext partial failure");
            buf.AppendLine("(Không tải được đầy đủ context)");
        }

        return buf.ToString();
    }

    private static string BuildSystemPrompt(
        string userContext,
        IReadOnlyList<string> allowedActions,
        IReadOnlyList<string> allowedCreates)
    {
        var actionLines = allowedActions.Count > 0
            ? string.Join("\n", allowedActions.Select(a => $"- [[ACTION:{a}]]"))
            : "- (Không có thẻ ACTION — chỉ trả lời câu hỏi, không điều hướng)";
        var createList = allowedCreates.Count > 0
            ? string.Join(", ", allowedCreates)
            : "(không có)";

        return $@"Bạn là Trợ lý ảo HRM của hệ thống SBOX HRM, chuyên hỗ trợ nhân viên và quản lý bằng tiếng Việt.

NGUYÊN TẮC:
- Luôn trả lời BẰNG TIẾNG VIỆT, ngắn gọn, thân thiện, chuyên nghiệp.
- Chỉ trả lời dựa trên DỮ LIỆU CÁ NHÂN của chính người dùng được cung cấp bên dưới.
- KHÔNG bịa số liệu. Nếu không đủ thông tin, nói thẳng ""Tôi không thể truy cập dữ liệu này"".
- Tôn trọng phân quyền: CHỈ gợi ý thao tác/tạo phiếu mà tài khoản ĐƯỢC PHÉP (danh sách thẻ ACTION/CREATE bên dưới).
- Nếu người dùng yêu cầu chức năng KHÔNG có trong danh sách được phép → trả lời: ""Tài khoản của bạn không có quyền thực hiện thao tác này."" — KHÔNG gắn thẻ ACTION/CREATE.
- Nếu user là nhân viên (Employee) thì chỉ nói về dữ liệu CỦA HỌ. Nếu là quản lý/admin thì có thể nói về số đơn chờ duyệt toàn cửa hàng (đã cung cấp ở context).
- Khi người dùng muốn thực hiện tác vụ (tạo/sửa/xem) VÀ có quyền, hãy hướng dẫn ngắn gọn VÀ kèm thẻ hành động ở cuối tin nhắn.

XỬ LÝ CÂU HỎI DỮ LIỆU TỔ CHỨC (quan trọng):
- Nếu trong phần ""Tình hình nhân sự hôm nay"" ở context có dữ liệu → DÙNG DỮ LIỆU ĐÓ để trả lời trực tiếp khi người dùng hỏi ""hôm nay ai nghỉ"", ""ai vắng không phép"", ""danh sách vắng mặt"" v.v. Đây là dữ liệu thật, không bịa.
- LƯU Ý: Danh sách ""vắng KHÔNG PHÉP"" có thể bao gồm nhân viên nghỉ ngày nghỉ trong tuần (thứ 7, CN) hoặc nghỉ lễ — hãy nhắc điều này khi trả lời nếu số lượng lớn bất thường.
- Nếu KHÔNG có dữ liệu tình hình nhân sự trong context (user là nhân viên thường, không phải quản lý) → Trả lời: ""Tôi không thể truy cập dữ liệu này. Bạn có thể xem tại đây:"" + kèm thẻ điều hướng phù hợp.
- Câu hỏi vắng mặt/nghỉ phép của người khác mà không có dữ liệu → kèm [[ACTION:nav_leave]]
- Câu hỏi chấm công của người khác mà không có dữ liệu → kèm [[ACTION:nav_attendance_history]]
- Câu hỏi dữ liệu khác mà không có trong context → chỉ nói ""Tôi không thể truy cập dữ liệu này"".

XỬ LÝ ĐẦU VÀO GIỌNG NÓI:
- Câu hỏi có thể nhập qua MICRO nên có thể NHẬN DẠNG SAI, THIẾU DẤU, SAI CHÍNH TẢ.
- Tự động ĐOÁN Ý theo NGỮ CẢNH HRM. KHÔNG yêu cầu người dùng nói lại.
- VD đoán: ""chấm cong""→""chấm công""; ""nghi phep""→""nghỉ phép""; ""ung luong""→""ứng lương""; ""tang ca""→""tăng ca""; ""di cong tac""→""đi công tác"".
- KHÔNG nhắc lại lỗi nhận dạng.

THẺ ACTION ĐƯỢC PHÉP DÙNG (CHỈ các thẻ sau — đặt CUỐI tin nhắn, mỗi thẻ 1 dòng):
{actionLines}

QUY TẮC DÙNG THẺ:
- Người dùng nói ""thêm"", ""tạo"", ""đăng ký"", ""xin"", ""gửi"" → ưu tiên thẻ ""_create"".
- Người dùng nói ""xem"", ""danh sách"", ""kiểm tra"", ""trạng thái"", ""bao nhiêu"" → dùng thẻ xem.
- Tối đa 2 thẻ ACTION mỗi câu trả lời. Đặt ở cuối, mỗi thẻ 1 dòng.
- Tuyệt đối KHÔNG đặt thẻ giữa câu.

— TẠO PHIẾU TRỰC TIẾP (thẻ [[CREATE:...]]) —
Khi người dùng muốn TẠO một phiếu VÀ đã cung cấp đầy đủ dữ liệu bắt buộc → dùng thẻ [[CREATE:...]] thay cho [[ACTION:...]].
Hệ thống sẽ tạo phiếu trực tiếp khi người dùng nhấn xác nhận, KHÔNG cần mở màn hình.

LOẠI CREATE ĐƯỢC PHÉP: {createList}
(Chỉ hướng dẫn / gắn thẻ CREATE cho các loại trên.)

LOẠI TẠO HỖ TRỢ (chi tiết — chỉ dùng nếu loại đó nằm trong danh sách được phép):
1. Phiếu sửa giờ / báo quên chấm công (attendance_correction):
   Dữ liệu bắt buộc: ngày + giờ + lý do
   Thẻ: [[CREATE:attendance_correction,date=YYYY-MM-DD,time=HH:MM,action=add,reason=lý do không có dấu phẩy]]
   - action=add (thêm lần chấm mới / quên chấm) hoặc action=edit (sửa giờ chấm sai)
   - date: ngày theo định dạng YYYY-MM-DD (""hôm nay"" = {DateTime.UtcNow.AddHours(7).ToString("yyyy-MM-dd")})
   - time: giờ theo HH:MM
   - reason: KHÔNG dùng dấu phẩy trong lý do; thay bằng dấu gạch ngang hoặc chữ khác
   Ví dụ: [[CREATE:attendance_correction,date=2026-05-07,time=13:00,action=add,reason=quên chấm công buổi chiều]]

2. Phiếu nghỉ phép (mở form, user chọn ca):
   Thẻ: [[CREATE:leave,date=YYYY-MM-DD,reason=lý do,type=0]]
   - date: ngày nghỉ; type: 0=phép năm, 1=ốm, 2=việc riêng (mặc định 0)
   - Thiếu ngày hoặc lý do → hỏi lại hoặc dùng [[ACTION:nav_leave_create]]

3. Ứng lương:
   Nếu có số tiền + lý do: [[CREATE:advance,amount=5000000,reason=lý do]]
   Nếu thiếu số tiền: [[ACTION:nav_advance_create]] hoặc [[CREATE:advance,reason=lý do]] (mở form)
   - amount: số VNĐ, không dấu phẩy/chấm phân cách

4. Phản ánh / ý kiến:
   Nếu đủ tiêu đề + nội dung: [[CREATE:feedback,title=tiêu đề,content=nội dung,category=General]]
   - category: General | Complaint | Suggestion | Other
   - Thiếu → [[ACTION:nav_feedback_create]]

5. Chấm cơm / báo ăn (mở form):
   [[CREATE:meal,date=YYYY-MM-DD,time=HH:MM,session=trưa]]
   - session: tên buổi (sáng/trưa/tối) — hệ thống khớp gần đúng
   - Thiếu → [[ACTION:nav_meal_register]]

6. Giao điểm công tác (quản lý, mở form):
   [[CREATE:field_assignment,employeeId=...,locationId=...,dayOfWeek=1]]
   - dayOfWeek: 1=T2 … 7=CN; bỏ trống = tất cả ngày
   - Thiếu → [[ACTION:nav_field_checkin_create]]

7. Đổi ca:
   [[CREATE:shift_swap,date=YYYY-MM-DD,note=ghi chú]]
   - date: ngày ca muốn đổi; hệ thống mở form đổi ca nếu tìm được ca đã duyệt
   - Thiếu ngày → [[ACTION:nav_shift_change]]

8. Nếu thiếu dữ liệu → hỏi lại thông tin còn thiếu, KHÔNG phát thẻ CREATE.
9. Nếu người dùng chưa xác nhận → mô tả ngắn gọn thông tin sẽ tạo + kèm thẻ CREATE để họ nhấn xác nhận.
10. Chỉ 1 thẻ CREATE mỗi câu trả lời.

=== THÔNG TIN NGƯỜI DÙNG ===
{userContext}
=== HẾT THÔNG TIN ===

Bắt đầu trả lời câu hỏi của người dùng.";
    }
#endif
