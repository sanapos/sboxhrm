using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Trình soạn mẫu in: gõ yêu cầu → AI sửa mẫu V2 → app xem trước, áp dụng (hoàn tác được) rồi mới lưu.</summary>
[ApiController]
[Authorize]
[Route("api/pos/print-templates/ai-edit")]
public class PosPrintTemplateAiController(
    PosPrintTemplateAiService ai,
    ILogger<PosPrintTemplateAiController> logger) : AuthenticatedControllerBase
{
    [HttpPost]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PrintTemplateAiEditResult>>> Edit(
        [FromBody] PrintTemplateAiEditRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Instruction))
            return BadRequest(AppResponse<PrintTemplateAiEditResult>.Fail("Nhập yêu cầu sửa mẫu."));
        if (req.Instruction.Length > PosPrintTemplateAiService.MaxInstructionLength)
            return BadRequest(AppResponse<PrintTemplateAiEditResult>.Fail("Yêu cầu quá dài — viết ngắn gọn hơn."));
        if (req.Template.ValueKind != JsonValueKind.Object)
            return BadRequest(AppResponse<PrintTemplateAiEditResult>.Fail("Thiếu mẫu in."));
        if (req.Template.GetRawText().Length > PosPrintTemplateAiService.MaxTemplateChars)
            return BadRequest(AppResponse<PrintTemplateAiEditResult>.Fail("Mẫu quá lớn để AI sửa."));
        _ = RequiredStoreId;

        try
        {
            return Ok(AppResponse<PrintTemplateAiEditResult>.Success(await ai.EditAsync(req, ct)));
        }
        catch (AiApiException ex)
        {
            logger.LogWarning("AI print template edit failed ({Status}): {Message}", ex.StatusCode, ex.Message);
            return Ok(AppResponse<PrintTemplateAiEditResult>.Fail(ex.Message));
        }
        catch (Exception ex) when (ex is InvalidOperationException or JsonException)
        {
            return Ok(AppResponse<PrintTemplateAiEditResult>.Fail(
                ex is JsonException ? "AI trả kết quả lỗi — thử lại." : ex.Message));
        }
    }
}
