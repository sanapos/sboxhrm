using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/print-jobs")]
[Authorize]
public class PosPrintJobsController(
    ZKTecoDbContext db,
    IPosPrintDispatchService dispatch) : AuthenticatedControllerBase
{
    public record CreateJobDto(
        string DocumentType,
        string PayloadFormat,
        string Payload,
        int Copies,
        string? ReferenceNo,
        Guid? ReferenceId,
        Guid? PrinterId);

    public record FailJobDto(string ErrorCode, string ErrorMessage);

    public record AgentRegisterDto(
        string DeviceId,
        string? DeviceName,
        string? EmployeeName,
        List<Guid> PrinterIds,
        string? AppVersion);

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] CreateJobDto dto)
    {
        if (!Enum.TryParse<PosPrintDocumentType>(dto.DocumentType, out var docType))
            return BadRequest(AppResponse<object>.Fail("Loại chứng từ không hợp lệ"));
        if (!Enum.TryParse<PosPrintPayloadFormat>(dto.PayloadFormat, out var format))
            return BadRequest(AppResponse<object>.Fail("Định dạng payload không hợp lệ"));
        if (string.IsNullOrWhiteSpace(dto.Payload))
            return BadRequest(AppResponse<object>.Fail("Payload trống"));

        try
        {
            var job = await dispatch.EnqueueJobAsync(new EnqueuePrintJobRequest(
                RequiredStoreId,
                docType,
                format,
                dto.Payload,
                dto.Copies,
                dto.ReferenceNo,
                dto.ReferenceId,
                CurrentUserId.ToString(),
                CurrentUserEmail ?? User.Identity?.Name,
                dto.PrinterId));

            var printer = await db.PosStorePrinters.AsNoTracking()
                .FirstAsync(p => p.Id == job.PrinterId);

            return Ok(AppResponse<object>.Success(new
            {
                jobId = job.Id,
                printerId = printer.Id,
                printerName = printer.Name,
                requiresAgent = printer.RequiresAgent,
                connectionType = printer.ConnectionType.ToString(),
                status = job.Status.ToString(),
            }));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<object>.Fail(ex.Message));
        }
    }

    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] int limit = 30,
        [FromQuery] string? status = null)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, 100);

        var query = db.PosPrintJobs.AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null);

        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosPrintJobStatus>(status, true, out var st))
            query = query.Where(j => j.Status == st);

        var items = await query
            .OrderByDescending(j => j.CreatedAt)
            .Take(limit)
            .Select(j => new
            {
                j.Id,
                printerId = j.PrinterId,
                documentType = j.DocumentType.ToString(),
                j.ReferenceNo,
                status = j.Status.ToString(),
                j.ErrorCode,
                j.ErrorMessage,
                j.RequestedByName,
                j.CreatedAt,
                j.CompletedAt,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var job = await db.PosPrintJobs.AsNoTracking()
            .FirstOrDefaultAsync(j => j.Id == id && j.StoreId == storeId && j.Deleted == null);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy job"));

        return Ok(AppResponse<object>.Success(new
        {
            job.Id,
            printerId = job.PrinterId,
            documentType = job.DocumentType.ToString(),
            job.ReferenceNo,
            status = job.Status.ToString(),
            payloadFormat = job.PayloadFormat.ToString(),
            payload = job.Status == PosPrintJobStatus.Queued || job.Status == PosPrintJobStatus.Claimed
                ? job.Payload : null,
            job.Copies,
            job.ErrorCode,
            job.ErrorMessage,
            job.RequestedByName,
            job.CreatedAt,
            job.CompletedAt,
        }));
    }

    [HttpPost("agents/register")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> RegisterAgent([FromBody] AgentRegisterDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.DeviceId))
            return BadRequest(AppResponse<object>.Fail("Thiếu deviceId"));

        await dispatch.RegisterAgentHeartbeatAsync(
            RequiredStoreId,
            dto.DeviceId.Trim(),
            dto.DeviceName,
            dto.EmployeeName,
            CurrentUserId.ToString(),
            dto.PrinterIds ?? [],
            dto.AppVersion);

        var agent = await db.PosPrintAgents.AsNoTracking()
            .FirstAsync(a => a.StoreId == RequiredStoreId && a.DeviceId == dto.DeviceId.Trim());

        return Ok(AppResponse<object>.Success(new { agentId = agent.Id }));
    }

    [HttpPost("agents/{agentId:guid}/claim")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Claim(Guid agentId)
    {
        var job = await dispatch.ClaimNextJobAsync(RequiredStoreId, agentId);
        if (job == null)
            return Ok(AppResponse<object>.Success(null));

        return Ok(AppResponse<object>.Success(new
        {
            jobId = job.Id,
            printerId = job.PrinterId,
            documentType = job.DocumentType.ToString(),
            job.ReferenceNo,
            payloadFormat = job.PayloadFormat.ToString(),
            payload = job.Payload,
            job.Copies,
        }));
    }

    [HttpPost("{id:guid}/printing")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> MarkPrinting(Guid id, [FromQuery] Guid agentId)
    {
        var job = await dispatch.MarkPrintingAsync(id, agentId);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không claim được job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Complete(Guid id, [FromQuery] Guid agentId)
    {
        var job = await dispatch.CompleteJobAsync(id, agentId);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không hoàn thành job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }

    [HttpPost("{id:guid}/fail")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Fail(Guid id, [FromQuery] Guid? agentId, [FromBody] FailJobDto dto)
    {
        var job = await dispatch.FailJobAsync(id, agentId, dto.ErrorCode, dto.ErrorMessage);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không cập nhật job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }
}
