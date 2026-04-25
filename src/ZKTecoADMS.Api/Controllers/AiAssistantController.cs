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

            // Pick provider — only use providers that are ENABLED + CONFIGURED.
            var wantGemini = string.Equals(dto.Provider, "gemini", StringComparison.OrdinalIgnoreCase);
            var wantDeepSeek = string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase);
            var geminiOk = geminiAiService.IsEnabled;
            var deepSeekOk = deepSeekAiService.IsEnabled;

            if (!geminiOk && !deepSeekOk)
            {
                return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
                {
                    Reply = "Trợ lý AI hiện chưa được cấu hình. Vui lòng liên hệ quản trị viên để bật Gemini hoặc DeepSeek trong phần Cài đặt hệ thống.",
                    Provider = "none",
                    Actions = new List<string>()
                }));
            }

            string reply;
            string usedProvider;
            // Decide order: respect explicit choice if available, otherwise prefer Gemini when both enabled.
            var tryOrder = new List<string>();
            if (wantDeepSeek && deepSeekOk) tryOrder.Add("deepseek");
            if (wantGemini && geminiOk) tryOrder.Add("gemini");
            if (geminiOk && !tryOrder.Contains("gemini")) tryOrder.Add("gemini");
            if (deepSeekOk && !tryOrder.Contains("deepseek")) tryOrder.Add("deepseek");

            reply = string.Empty;
            usedProvider = string.Empty;
            Exception? lastEx = null;
            foreach (var provider in tryOrder)
            {
                try
                {
                    if (provider == "gemini")
                    {
                        reply = await geminiAiService.GeneratePlainTextAsync(systemPrompt, combined, 1500);
                        usedProvider = "gemini";
                    }
                    else
                    {
                        reply = await deepSeekAiService.GeneratePlainTextAsync(systemPrompt, combined, 1500);
                        usedProvider = "deepseek";
                    }
                    lastEx = null;
                    break;
                }
                catch (Exception ex)
                {
                    lastEx = ex;
                    logger.LogWarning(ex, "AI provider {Provider} failed, will try next", provider);
                }
            }

            if (string.IsNullOrEmpty(usedProvider))
            {
                logger.LogError(lastEx, "All AI providers failed");
                return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
                {
                    Reply = "Xin lỗi, trợ lý AI tạm thời không phản hồi. Vui lòng thử lại sau ít phút.",
                    Provider = "error",
                    Actions = new List<string>()
                }));
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

            return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
            {
                Reply = cleaned.Trim(),
                Provider = usedProvider,
                Actions = actions
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "AI Assistant chat failed");
            return Ok(AppResponse<ChatResponse>.Success(new ChatResponse
            {
                Reply = "Xin lỗi, đã có lỗi khi xử lý câu hỏi. Bạn thử lại nhé.",
                Provider = "error",
                Actions = new List<string>()
            }));
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

            // Manager-only: pending approvals snapshot (only count, no PII of others)
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
- KHÔNG bịa số liệu. Nếu không đủ thông tin, nói thẳng ""Tôi không có dữ liệu này"".
- Tôn trọng phân quyền: nếu user là nhân viên (Employee) thì chỉ nói về dữ liệu CỦA HỌ. Nếu là quản lý/admin thì có thể nói về số đơn chờ duyệt toàn cửa hàng (đã cung cấp ở context).
- Khi người dùng muốn thực hiện tác vụ (tạo/sửa/xem), hãy hướng dẫn ngắn gọn VÀ kèm thẻ hành động ở cuối tin nhắn.

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

— TẠO PHIẾU TRỰC TIẾP (AI tự tạo, có hộp xác nhận) —
- [[ACTION:create_advance|amount=SO_TIEN|reason=LY_DO|month=THANG|year=NAM]]
  → Khi người dùng nói cụ thể số tiền muốn ứng (vd: ""ứng lương 2 triệu tháng này""), HÃY emit thẻ này
    với amount = số nguyên (đơn vị VND, KHÔNG có dấu phẩy/chấm). VD:
    [[ACTION:create_advance|amount=2000000|reason=Ứng lương tháng 4|month=4|year=2026]]
  → Nếu user chỉ nói ""ứng lương"" mà KHÔNG có số tiền → dùng [[ACTION:nav_advance_create]] thay thế.
  → KHÔNG bịa số tiền. Chỉ dùng khi user nêu rõ số.

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
- Tối đa 2 thẻ mỗi câu trả lời. Đặt ở cuối, mỗi thẻ 1 dòng.
- Tuyệt đối KHÔNG đặt thẻ giữa câu.

=== THÔNG TIN NGƯỜI DÙNG ===
{userContext}
=== HẾT THÔNG TIN ===

Bắt đầu trả lời câu hỏi của người dùng.";
    }
}
