using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
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
    IGeminiAiService geminiAiService,
    IDeepSeekAiService deepSeekAiService,
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
        public string? Provider { get; set; } // "gemini" | "deepseek"
    }

    public class ChatResponse
    {
        public string Reply { get; set; } = "";
        public string Provider { get; set; } = "";
        public List<string> Actions { get; set; } = new();
        /// <summary>Structured create intents: "type,key=val,key=val" — Flutter parses and calls API directly.</summary>
        public List<string> Creates { get; set; } = new();
    }

    /// <summary>
    /// Chat với trợ lý ảo. Server nạp context cá nhân (profile, leave balance, attendance, payslip gần đây)
    /// rồi chuyển tới Gemini/DeepSeek. AI có thể trả về text + tag ACTION gợi ý Flutter điều hướng.
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

            // Load user context
            var contextText = await BuildUserContextAsync(ct);

            // Build system prompt
            var systemPrompt = BuildSystemPrompt(contextText);

            // Combine history into a single user prompt (keep last 10 turns)
            var history = dto.Messages
                .TakeLast(20)
                .Select(m => $"[{(m.Role == "assistant" ? "Trợ lý" : "Người dùng")}]: {m.Content}")
                .ToList();
            var combined = string.Join("\n", history);

            // Pick provider
            var wantGemini = string.Equals(dto.Provider, "gemini", StringComparison.OrdinalIgnoreCase);
            var wantDeepSeek = string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase);
            string reply;
            string usedProvider;
            if (wantDeepSeek)
            {
                reply = await deepSeekAiService.GeneratePlainTextAsync(systemPrompt, combined, 1500);
                usedProvider = "deepseek";
            }
            else
            {
                try
                {
                    reply = await geminiAiService.GeneratePlainTextAsync(systemPrompt, combined, 1500);
                    usedProvider = "gemini";
                }
                catch (Exception geminiEx) when (!wantGemini)
                {
                    logger.LogWarning(geminiEx, "Gemini failed, fallback to DeepSeek");
                    reply = await deepSeekAiService.GeneratePlainTextAsync(systemPrompt, combined, 1500);
                    usedProvider = "deepseek";
                }
            }

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
                if (!string.IsNullOrWhiteSpace(ctag)) creates.Add(ctag);
                cleaned = cleaned.Remove(ci, cj - ci + 2);
                cStart = ci;
            }

            return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
            {
                Reply = cleaned.Trim(),
                Provider = usedProvider,
                Actions = actions,
                Creates = creates
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "AI Assistant chat failed");
            return StatusCode(500, AppResponse<ChatResponse>.Fail("Lỗi trợ lý AI: " + ex.Message));
        }
    }

    /// <summary>
    /// Lấy context tóm tắt của người dùng đang đăng nhập để gắn vào system prompt.
    /// </summary>
    private async Task<string> BuildUserContextAsync(CancellationToken ct)
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

    private static string BuildSystemPrompt(string userContext)
    {
        return $@"Bạn là Trợ lý ảo HRM của hệ thống SBOX HRM, chuyên hỗ trợ nhân viên và quản lý bằng tiếng Việt.

NGUYÊN TẮC:
- Luôn trả lời BẰNG TIẾNG VIỆT, ngắn gọn, thân thiện, chuyên nghiệp.
- Chỉ trả lời dựa trên DỮ LIỆU CÁ NHÂN của chính người dùng được cung cấp bên dưới.
- KHÔNG bịa số liệu. Nếu không đủ thông tin, nói thẳng ""Tôi không thể truy cập dữ liệu này"".
- Tôn trọng phân quyền: nếu user là nhân viên (Employee) thì chỉ nói về dữ liệu CỦA HỌ. Nếu là quản lý/admin thì có thể nói về số đơn chờ duyệt toàn cửa hàng (đã cung cấp ở context).
- Khi người dùng muốn thực hiện tác vụ (tạo/sửa/xem), hãy hướng dẫn ngắn gọn VÀ kèm thẻ hành động ở cuối tin nhắn.

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

CÁC THẺ HÀNH ĐỘNG HỢP LỆ (đặt CUỐI tin nhắn, mỗi thẻ 1 dòng riêng, KHÔNG giải thích):

— XEM DỮ LIỆU —
- [[ACTION:nav_dashboard]]               → Tổng quan
- [[ACTION:nav_attendance_history]]      → Lịch sử chấm công cá nhân
- [[ACTION:nav_payroll]]                 → Phiếu lương cá nhân
- [[ACTION:nav_kpi]]                     → KPI cá nhân
- [[ACTION:nav_communication]]           → Bảng tin / truyền thông
- [[ACTION:nav_meal]]                    → Đăng ký ăn / báo cơm
- [[ACTION:nav_tasks]]                   → Danh sách công việc
- [[ACTION:nav_assets]]                  → Tài sản đang giữ
- [[ACTION:nav_bonus_penalty]]           → Lịch sử thưởng / phạt

— TẠO PHIẾU MỚI (gợi ý dùng các thẻ ""_create"" khi user muốn THÊM/TẠO/ĐĂNG KÝ MỚI) —
- [[ACTION:nav_leave_create]]            → Thêm phiếu xin nghỉ phép
- [[ACTION:nav_advance_create]]          → Thêm phiếu ứng lương
- [[ACTION:nav_overtime_create]]         → Đăng ký tăng ca / OT
- [[ACTION:nav_field_checkin_create]]    → Tạo phiếu đi công tác / chấm công ngoài
- [[ACTION:nav_attendance_correction_create]] → Tạo phiếu sửa giờ / báo quên chấm công
- [[ACTION:nav_shift_change]]            → Đổi ca / đăng ký lịch làm
- [[ACTION:nav_feedback_create]]         → Gửi phản ánh / ý kiến

— XEM/SỬA DANH SÁCH (cho quản lý) —
- [[ACTION:nav_leave]]                   → Danh sách phiếu nghỉ
- [[ACTION:nav_advance]]                 → Danh sách phiếu ứng lương
- [[ACTION:nav_attendance_correction]]   → Danh sách phiếu sửa giờ
- [[ACTION:nav_overtime]]                → Danh sách phiếu OT
- [[ACTION:nav_field_checkin]]           → Danh sách phiếu công tác
- [[ACTION:nav_employees]]               → Quản lý nhân viên
- [[ACTION:nav_departments]]             → Phòng ban
- [[ACTION:nav_cash]]                    → Giao dịch quỹ

QUY TẮC DÙNG THẺ:
- Người dùng nói ""thêm"", ""tạo"", ""đăng ký"", ""xin"", ""gửi"" → ưu tiên thẻ ""_create"".
- Người dùng nói ""xem"", ""danh sách"", ""kiểm tra"", ""trạng thái"", ""bao nhiêu"" → dùng thẻ xem.
- Tối đa 2 thẻ ACTION mỗi câu trả lời. Đặt ở cuối, mỗi thẻ 1 dòng.
- Tuyệt đối KHÔNG đặt thẻ giữa câu.

— TẠO PHIẾU TRỰC TIẾP (thẻ [[CREATE:...]]) —
Khi người dùng muốn TẠO một phiếu VÀ đã cung cấp đầy đủ dữ liệu bắt buộc → dùng thẻ [[CREATE:...]] thay cho [[ACTION:...]].
Hệ thống sẽ tạo phiếu trực tiếp khi người dùng nhấn xác nhận, KHÔNG cần mở màn hình.

LOẠI TẠO HỖ TRỢ:
1. Phiếu sửa giờ / báo quên chấm công:
   Dữ liệu bắt buộc: ngày + giờ + lý do
   Thẻ: [[CREATE:attendance_correction,date=YYYY-MM-DD,time=HH:MM,action=add,reason=lý do không có dấu phẩy]]
   - action=add (thêm lần chấm mới / quên chấm) hoặc action=edit (sửa giờ chấm sai)
   - date: ngày theo định dạng YYYY-MM-DD (""hôm nay"" = {DateTime.UtcNow.AddHours(7).ToString("yyyy-MM-dd")})
   - time: giờ theo HH:MM
   - reason: KHÔNG dùng dấu phẩy trong lý do; thay bằng dấu gạch ngang hoặc chữ khác
   Ví dụ: [[CREATE:attendance_correction,date=2026-05-07,time=13:00,action=add,reason=quên chấm công buổi chiều]]

2. Nếu thiếu dữ liệu → hỏi lại thông tin còn thiếu, KHÔNG phát thẻ CREATE.
3. Nếu người dùng chưa xác nhận → mô tả ngắn gọn thông tin sẽ tạo + kèm thẻ CREATE để họ nhấn xác nhận.
4. Chỉ 1 thẻ CREATE mỗi câu trả lời.

=== THÔNG TIN NGƯỜI DÙNG ===
{userContext}
=== HẾT THÔNG TIN ===

Bắt đầu trả lời câu hỏi của người dùng.";
    }
}
