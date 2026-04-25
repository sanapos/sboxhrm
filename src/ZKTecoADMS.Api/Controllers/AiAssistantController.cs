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
        var buf = new StringBuilder();

        try
        {
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
                    e.DepartmentId
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
                if (!string.IsNullOrEmpty(dept)) buf.AppendLine($"Phòng ban: {dept}");
            }
            else
            {
                buf.AppendLine("(Chưa liên kết hồ sơ nhân viên)");
            }

            var today = DateTime.UtcNow.Date;

            // Leaves: pending + recent
            var leaves = await db.Leaves
                .AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= today.AddDays(-60))
                .OrderByDescending(l => l.StartDate)
                .Take(10)
                .Select(l => new { l.StartDate, l.EndDate, l.Status, l.Type, l.Reason })
                .ToListAsync(ct);
            if (leaves.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Lịch sử nghỉ phép (60 ngày gần nhất):");
                foreach (var l in leaves)
                {
                    buf.AppendLine(
                        $"- {l.StartDate:dd/MM/yyyy}..{l.EndDate:dd/MM/yyyy} | Loại {(int)l.Type} | {l.Status}");
                }
            }

            // Attendance: last 7 days count
            var weekAgo = today.AddDays(-7);
            var attCount = await db.AttendanceLogs
                .AsNoTracking()
                .Where(a => a.AttendanceTime >= weekAgo
                    && db.Employees.Any(e => e.ApplicationUserId == userId && e.Id == a.EmployeeId))
                .CountAsync(ct);
            buf.AppendLine();
            buf.AppendLine($"Chấm công 7 ngày gần đây: {attCount} lượt");

            // Last payslip
            var lastPayslip = await db.Payslips
                .AsNoTracking()
                .Where(p => p.EmployeeUserId == userId)
                .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
                .Select(p => new { p.Year, p.Month, p.NetSalary, p.Status })
                .FirstOrDefaultAsync(ct);
            if (lastPayslip != null)
            {
                buf.AppendLine();
                buf.AppendLine($"Phiếu lương mới nhất: {lastPayslip.Month:D2}/{lastPayslip.Year} - Thực nhận {lastPayslip.NetSalary:N0} VND ({lastPayslip.Status})");
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
        return $@"Bạn là Trợ lý ảo HRM của hệ thống SBOX HRM, chuyên hỗ trợ nhân viên bằng tiếng Việt.

NGUYÊN TẮC:
- Luôn trả lời BẰNG TIẾNG VIỆT, ngắn gọn, thân thiện, chuyên nghiệp.
- Chỉ trả lời dựa trên DỮ LIỆU CÁ NHÂN của chính người dùng được cung cấp bên dưới.
- KHÔNG bịa số liệu. Nếu không đủ thông tin, nói thẳng ""Tôi không có dữ liệu này"".
- Khi người dùng muốn thực hiện tác vụ, hãy hướng dẫn ngắn gọn VÀ kèm thẻ hành động ở cuối tin nhắn.

XỬ LÝ ĐẦU VÀO GIỌNG NÓI (RẤT QUAN TRỌNG):
- Người dùng có thể nhập qua MICRO, do đó câu hỏi có thể bị NHẬN DẠNG SAI, THIẾU DẤU, SAI CHÍNH TẢ, GHÉP CHỮ LẠ, hoặc bị NÓI NGỌNG/PHƯƠNG NGỮ.
- Hãy tự động ĐOÁN Ý theo NGỮ CẢNH HRM (chấm công, nghỉ phép, lịch làm, lương, phản ánh, truyền thông) — KHÔNG yêu cầu người dùng nói lại.
- Một số ví dụ thường gặp cần đoán đúng:
  • ""chấm cong"" / ""chăm công"" / ""trấm công"" → ""chấm công""
  • ""quên trấm"" / ""kuen cham"" / ""quên chấm cong"" → ""quên chấm công""
  • ""nghỉ fép"" / ""nghi phep"" / ""nghĩ phép"" → ""nghỉ phép""
  • ""đổi ka"" / ""doi ca"" / ""đổi ga"" → ""đổi ca""
  • ""fiếu lương"" / ""phieu luong"" / ""bảng lương"" → ""phiếu lương""
  • ""fản ánh"" / ""phan anh"" / ""góp í"" → ""phản ánh / ý kiến""
  • ""truyen thong"" / ""bản tin"" → ""truyền thông""
  • ""sửa giờ"" / ""sủa giờ"" / ""sua gio cham"" → ""yêu cầu sửa giờ chấm công""
- Nếu thật sự MƠ HỒ giữa nhiều ý, hãy hỏi LẠI ngắn gọn 1 câu (vd: ""Bạn muốn xin nghỉ phép hay đổi ca?"").
- KHÔNG nhắc lại lỗi nhận dạng, KHÔNG chê người dùng phát âm sai. Trả lời tự nhiên như đã hiểu đúng ngay từ đầu.

CÁC THẺ HÀNH ĐỘNG HỢP LỆ (ĐẶT Ở CUỐI, MỖI THẺ 1 DÒNG, KHÔNG GIẢI THÍCH THÊM):
- [[ACTION:nav_leave]]                 → mở màn đăng ký nghỉ phép
- [[ACTION:nav_work_schedule]]         → mở màn đăng ký lịch làm / đổi ca
- [[ACTION:nav_attendance_correction]] → mở màn gửi yêu cầu sửa giờ / quên chấm
- [[ACTION:nav_attendance_history]]    → mở lịch sử chấm công cá nhân
- [[ACTION:nav_payroll]]               → mở phiếu lương cá nhân
- [[ACTION:nav_feedback]]              → mở màn gửi phản ánh/ý kiến
- [[ACTION:nav_communication]]         → mở bảng tin truyền thông

QUY TẮC DÙNG THẺ:
- Chỉ kèm thẻ khi người dùng THẬT SỰ muốn đi tới màn đó.
- Tối đa 1-2 thẻ mỗi câu trả lời.
- Tuyệt đối KHÔNG đặt thẻ giữa câu, chỉ đặt ở cuối.

=== THÔNG TIN CÁ NHÂN NGƯỜI DÙNG ===
{userContext}
=== HẾT THÔNG TIN ===

Bắt đầu trả lời câu hỏi của người dùng.";
    }
}
