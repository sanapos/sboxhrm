using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/ai")]
[Authorize]
public class AiAssistController(
    IGeminiAiService geminiAiService,
    IDeepSeekAiService deepSeekAiService,
    ILogger<AiAssistController> logger) : ControllerBase
{
    public class AiAssistRequest
    {
        public string Kind { get; set; } = "generic";
        public string Prompt { get; set; } = "";
        public string? Context { get; set; }
        public string? Tone { get; set; }
        public string? Provider { get; set; }
        public int MaxTokens { get; set; } = 1024;
    }

    public class AiAssistResponse
    {
        public string Text { get; set; } = "";
        public string Provider { get; set; } = "";
    }

    /// <summary>
    /// Generic AI text assist - dùng cho soạn thảo văn bản ở nhiều màn hình:
    /// feedback, leave, attendance, schedule, attendance_report, ...
    /// </summary>
    [HttpPost("assist")]
    public async Task<IActionResult> Assist([FromBody] AiAssistRequest dto)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(dto.Prompt))
                return BadRequest(AppResponse<AiAssistResponse>.Fail("Vui lòng nhập nội dung cần AI hỗ trợ"));

            var systemPrompt = BuildSystemPrompt(dto.Kind, dto.Tone, dto.Context);
            var userPrompt = dto.Prompt.Trim();

            // Auto-select provider
            var useGemini = string.Equals(dto.Provider, "gemini", StringComparison.OrdinalIgnoreCase);
            var useDeepSeek = string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(dto.Provider))
            {
                if (geminiAiService.IsEnabled) useGemini = true;
                else if (deepSeekAiService.IsEnabled) useDeepSeek = true;
            }

            string text;
            string providerName;
            if (useDeepSeek && deepSeekAiService.IsEnabled)
            {
                text = await deepSeekAiService.GeneratePlainTextAsync(systemPrompt, userPrompt, dto.MaxTokens);
                providerName = "deepseek";
            }
            else if (useGemini && geminiAiService.IsEnabled)
            {
                text = await geminiAiService.GeneratePlainTextAsync(systemPrompt, userPrompt, dto.MaxTokens);
                providerName = "gemini";
            }
            else
            {
                return BadRequest(AppResponse<AiAssistResponse>.Fail(
                    "Chưa có AI provider nào được bật. Vui lòng cấu hình tại Thiết lập HRM > Tích hợp AI."));
            }

            return Ok(AppResponse<AiAssistResponse>.Success(new AiAssistResponse
            {
                Text = text,
                Provider = providerName
            }));
        }
        catch (AiApiException ex)
        {
            logger.LogWarning(ex, "AI assist error");
            return StatusCode(ex.StatusCode == 0 ? 500 : ex.StatusCode,
                AppResponse<AiAssistResponse>.Fail(ex.Message));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error in AI assist");
            return StatusCode(500, AppResponse<AiAssistResponse>.Fail($"Lỗi AI: {ex.Message}"));
        }
    }

    private static string BuildSystemPrompt(string kind, string? tone, string? context)
    {
        var toneLabel = (tone ?? "").ToLower() switch
        {
            "formal" => "trang trọng, chuyên nghiệp",
            "friendly" => "thân thiện, gần gũi",
            "concise" => "ngắn gọn, đi vào trọng tâm",
            "empathetic" => "đồng cảm, lịch sự",
            _ => "chuyên nghiệp, rõ ràng"
        };

        var (role, rule) = kind.ToLower() switch
        {
            "feedback" => (
                "trợ lý soạn thảo phản ánh/ý kiến cho nhân viên",
                "- Viết dưới dạng văn bản phản ánh/đề xuất gửi tới ban lãnh đạo/HR.\n" +
                "- Nêu rõ vấn đề, dẫn chứng (nếu có), đề xuất giải pháp.\n" +
                "- Giữ thái độ tôn trọng, xây dựng. Độ dài vừa phải (150-400 từ)."
            ),
            "leave_reason" => (
                "trợ lý viết lý do đơn xin nghỉ phép",
                "- Viết lý do nghỉ phép ngắn gọn, lịch sự (1-3 câu).\n" +
                "- Không bịa thông tin không có trong yêu cầu của người dùng.\n" +
                "- Văn phong trang trọng."
            ),
            "attendance_reason" => (
                "trợ lý viết lý do giải trình chấm công",
                "- Viết lý do giải trình việc chấm công (quên chấm công, chấm công muộn, sửa giờ...).\n" +
                "- Ngắn gọn 1-3 câu, lịch sự, có cam kết (nếu phù hợp)."
            ),
            "schedule_request" => (
                "trợ lý viết đề xuất đăng ký/đổi lịch làm việc",
                "- Viết nội dung đề xuất đổi/đăng ký ca làm việc.\n" +
                "- Nêu rõ ca mong muốn, lý do, cam kết hoàn thành công việc.\n" +
                "- Ngắn gọn, trang trọng (2-5 câu)."
            ),
            "schedule_approval" => (
                "quản lý viết ý kiến duyệt/từ chối đề xuất lịch làm việc",
                "- Viết nhận xét ngắn gọn của quản lý khi duyệt/từ chối.\n" +
                "- Văn phong chuyên nghiệp, rõ quan điểm, có căn cứ (2-4 câu)."
            ),
            "attendance_report" => (
                "chuyên gia HR tóm tắt báo cáo chấm công",
                "- Viết đoạn tóm tắt, nhận xét, khuyến nghị dựa trên số liệu chấm công do người dùng cung cấp.\n" +
                "- Cấu trúc: (1) Tổng quan, (2) Điểm đáng chú ý, (3) Khuyến nghị.\n" +
                "- Văn phong chuyên nghiệp, súc tích, dạng plain text có gạch đầu dòng."
            ),
            _ => (
                "trợ lý soạn thảo văn bản nội bộ doanh nghiệp",
                "- Viết văn bản ngắn gọn, rõ ràng, đúng yêu cầu của người dùng."
            )
        };

        var contextPart = string.IsNullOrWhiteSpace(context) ? "" : $"\n\nBỐI CẢNH:\n{context}";

        return $@"Bạn là {role}. Viết bằng tiếng Việt, giọng văn {toneLabel}.
QUY TẮC:
{rule}
- Chỉ trả về văn bản thuần (plain text), KHÔNG markdown, KHÔNG code block, KHÔNG JSON.
- KHÔNG thêm ghi chú ngoài lề (''đây là bài viết...'' v.v.), chỉ trả nội dung cuối.{contextPart}";
    }
}
