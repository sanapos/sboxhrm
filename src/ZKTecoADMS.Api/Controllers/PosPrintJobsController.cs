using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
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

    public record AgentOfflineDto(string DeviceId);

    /// <summary>
    /// Agent phải thuộc store và gắn đúng user đang đăng nhập (trừ QL/Admin).
    /// Chống spoof agentId để claim payload đơn của máy khác.
    /// </summary>
    async Task<ActionResult?> DenyIfCannotUseAgentAsync(Guid agentId)
    {
        var agent = await db.PosPrintAgents.AsNoTracking()
            .FirstOrDefaultAsync(a =>
                a.Id == agentId && a.StoreId == RequiredStoreId && a.Deleted == null);
        if (agent == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy print agent"));

        if (IsAdmin || IsManager) return null;

        var uid = CurrentUserId.ToString();
        if (!string.IsNullOrWhiteSpace(agent.UserId) &&
            !string.Equals(agent.UserId, uid, StringComparison.OrdinalIgnoreCase))
        {
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<object>.Fail("Print agent đang gắn tài khoản khác trên thiết bị này."));
        }

        return null;
    }

    /// <summary>Chặn chiếm deviceId đang online của user khác.</summary>
    async Task<ActionResult?> DenyIfAgentDeviceHijackAsync(string deviceId)
    {
        if (IsAdmin || IsManager) return null;

        var agent = await db.PosPrintAgents.AsNoTracking()
            .FirstOrDefaultAsync(a =>
                a.StoreId == RequiredStoreId &&
                a.DeviceId == deviceId &&
                a.Deleted == null);
        if (agent == null) return null;

        var uid = CurrentUserId.ToString();
        if (string.IsNullOrWhiteSpace(agent.UserId) ||
            string.Equals(agent.UserId, uid, StringComparison.OrdinalIgnoreCase))
            return null;

        // Cho phép reclaim nếu agent đã stale (>3 phút) — đổi ca trên cùng máy.
        if (agent.LastHeartbeatAt is { } hb)
        {
            var now = DateTime.UtcNow;
            var ageUtc = Math.Abs((now - DateTime.SpecifyKind(hb, DateTimeKind.Utc)).TotalSeconds);
            var ageRaw = Math.Abs((now - hb).TotalSeconds);
            if (Math.Min(ageUtc, ageRaw) > 180) return null;
        }
        else if (!agent.IsOnline)
        {
            return null;
        }

        return StatusCode(StatusCodes.Status403Forbidden,
            AppResponse<object>.Fail(
                "Thiết bị đang là print agent của tài khoản khác. Đợi offline hoặc dùng tài khoản đó."));
    }

    [HttpGet("agents")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListAgents(
        [FromQuery] bool onlineOnly = true,
        [FromQuery] int staleSeconds = 90)
    {
        var storeId = RequiredStoreId;
        staleSeconds = Math.Clamp(staleSeconds, 30, 600);
        var now = DateTime.UtcNow;

        var agents = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null)
            .OrderByDescending(a => a.LastHeartbeatAt)
            .ToListAsync();

        // Tính online an toàn với datetime SQL (Unspecified/Local/Utc lệch).
        // Không đánh offline hàng loạt bằng so sánh timezone sai.
        static bool IsFresh(PosPrintAgent a, DateTime utcNow, int staleSec)
        {
            if (a.LastHeartbeatAt == null) return a.IsOnline;
            var hb = a.LastHeartbeatAt.Value;
            var ageUtc = Math.Abs((utcNow - DateTime.SpecifyKind(hb, DateTimeKind.Utc)).TotalSeconds);
            var ageRaw = Math.Abs((utcNow - hb).TotalSeconds);
            var age = Math.Min(ageUtc, ageRaw);
            if (age <= Math.Max(staleSec, 180)) return true;
            return a.IsOnline && age <= 600;
        }

        foreach (var a in agents)
        {
            var fresh = IsFresh(a, now, staleSeconds);
            if (fresh != a.IsOnline)
            {
                await db.PosPrintAgents
                    .Where(x => x.Id == a.Id)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.IsOnline, fresh)
                        .SetProperty(x => x.UpdatedAt, now));
                a.IsOnline = fresh;
            }
        }

        if (onlineOnly)
            agents = agents.Where(a => a.IsOnline).ToList();

        agents = agents
            .OrderByDescending(a => a.IsOnline)
            .ThenByDescending(a => a.LastHeartbeatAt)
            .ToList();

        var userIds = agents
            .Select(a => Guid.TryParse(a.UserId, out var uid) ? uid : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToList();
        var users = new Dictionary<Guid, (string? Email, string? UserName)>();
        if (userIds.Count > 0)
        {
            var userRows = await db.Users.AsNoTracking()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.Email, u.UserName })
                .ToListAsync();
            foreach (var u in userRows)
                users[u.Id] = (u.Email, u.UserName);
        }

        var printerNameById = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.Name })
            .ToDictionaryAsync(x => x.Id, x => x.Name);

        var items = agents.Select(a =>
        {
            var printerIds = ParsePrinterIds(a.AssignedPrinterIdsJson);
            string? accountEmail = null;
            string? accountUserName = null;
            if (Guid.TryParse(a.UserId, out var uid) && users.TryGetValue(uid, out var u))
            {
                accountEmail = u.Email;
                accountUserName = u.UserName;
            }
            return new
            {
                agentId = a.Id,
                a.DeviceId,
                a.DeviceName,
                a.EmployeeName,
                accountEmail,
                accountUserName,
                accountLabel = !string.IsNullOrWhiteSpace(a.EmployeeName)
                    ? a.EmployeeName
                    : (!string.IsNullOrWhiteSpace(accountEmail)
                        ? accountEmail
                        : accountUserName),
                printerIds,
                printerNames = printerIds
                    .Select(id => printerNameById.TryGetValue(id, out var n) ? n : id.ToString()[..8])
                    .ToList(),
                a.IsOnline,
                a.LastHeartbeatAt,
                a.AppVersion,
            };
        }).ToList();

        // Cùng 1 máy in được ≥2 agent online → xung đột.
        var conflictPrinterIds = items
            .Where(x => x.IsOnline)
            .SelectMany(x => x.printerIds.Select(pid => (pid, x.DeviceId)))
            .GroupBy(x => x.pid)
            .Where(g => g.Select(x => x.DeviceId).Distinct().Count() > 1)
            .Select(g => g.Key)
            .ToList();

        var onlineCount = items.Count(x => x.IsOnline);
        return Ok(AppResponse<object>.Success(new
        {
            onlineCount,
            multiAgent = onlineCount > 1,
            hasPrinterConflict = conflictPrinterIds.Count > 0,
            conflictPrinterIds,
            agents = items,
        }));
    }

    static List<Guid> ParsePrinterIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return System.Text.Json.JsonSerializer.Deserialize<List<Guid>>(json) ?? [];
        }
        catch
        {
            return [];
        }
    }

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

            // Đếm agent heartbeat tươi có gắn đúng máy in (không tin IsOnline — timezone SQL hay lệch).
            var now = DateTime.UtcNow;
            var agents = await db.PosPrintAgents.AsNoTracking()
                .Where(a => a.StoreId == RequiredStoreId && a.Deleted == null)
                .ToListAsync();
            var agentOnlineForPrinter = 0;
            foreach (var a in agents)
            {
                if (a.LastHeartbeatAt == null) continue;
                var hb = a.LastHeartbeatAt.Value;
                var ageUtc = Math.Abs((now - DateTime.SpecifyKind(hb, DateTimeKind.Utc)).TotalSeconds);
                var ageRaw = Math.Abs((now - hb).TotalSeconds);
                if (Math.Min(ageUtc, ageRaw) > 180) continue;
                var ids = ParsePrinterIds(a.AssignedPrinterIdsJson);
                if (ids.Contains(printer.Id)) agentOnlineForPrinter++;
            }

            return Ok(AppResponse<object>.Success(new
            {
                jobId = job.Id,
                printerId = printer.Id,
                printerName = printer.Name,
                requiresAgent = printer.RequiresAgent,
                connectionType = printer.ConnectionType.ToString(),
                status = job.Status.ToString(),
                agentOnlineForPrinter,
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RegisterAgent([FromBody] AgentRegisterDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.DeviceId))
            return BadRequest(AppResponse<object>.Fail("Thiếu deviceId"));
        if (dto.PrinterIds == null || dto.PrinterIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Agent phải chọn ít nhất một máy in"));

        var hijack = await DenyIfAgentDeviceHijackAsync(dto.DeviceId.Trim());
        if (hijack != null) return hijack;

        var display = dto.EmployeeName?.Trim();
        if (string.IsNullOrWhiteSpace(display))
            display = CurrentUserEmail ?? User.Identity?.Name;

        try
        {
            await dispatch.RegisterAgentHeartbeatAsync(
                RequiredStoreId,
                dto.DeviceId.Trim(),
                dto.DeviceName,
                display,
                CurrentUserId.ToString(),
                dto.PrinterIds,
                dto.AppVersion);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<object>.Fail(ex.Message));
        }
        catch (DbUpdateException ex)
        {
            var detail = ex.InnerException?.Message ?? ex.Message;
            return BadRequest(AppResponse<object>.Fail($"Không lưu Print Agent: {detail}"));
        }

        var agent = await db.PosPrintAgents.AsNoTracking()
            .FirstAsync(a =>
                a.StoreId == RequiredStoreId &&
                a.DeviceId == dto.DeviceId.Trim() &&
                a.Deleted == null);

        return Ok(AppResponse<object>.Success(new
        {
            agentId = agent.Id,
            printerIds = ParsePrinterIds(agent.AssignedPrinterIdsJson),
            isOnline = agent.IsOnline,
            lastHeartbeatAt = agent.LastHeartbeatAt,
        }));
    }

    [HttpPost("agents/offline")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MarkAgentOffline([FromBody] AgentOfflineDto? dto)
    {
        if (dto == null || string.IsNullOrWhiteSpace(dto.DeviceId))
            return BadRequest(AppResponse<object>.Fail("Thiếu deviceId"));

        var agent = await db.PosPrintAgents.AsNoTracking()
            .FirstOrDefaultAsync(a =>
                a.StoreId == RequiredStoreId &&
                a.DeviceId == dto.DeviceId.Trim() &&
                a.Deleted == null);
        if (agent != null)
        {
            var owned = await DenyIfCannotUseAgentAsync(agent.Id);
            if (owned != null) return owned;
        }

        await dispatch.MarkAgentOfflineAsync(RequiredStoreId, dto.DeviceId.Trim());
        return Ok(AppResponse<object>.Success(new { offline = true }));
    }

    [HttpPost("agents/{agentId:guid}/claim")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Claim(Guid agentId)
    {
        var denied = await DenyIfCannotUseAgentAsync(agentId);
        if (denied != null) return denied;

        var job = await dispatch.ClaimNextJobAsync(RequiredStoreId, agentId);
        if (job == null)
            return Ok(AppResponse<object>.Success(null));

        return Ok(AppResponse<object>.Success(ToClaimDto(job)));
    }

    /// <summary>Claim đúng jobId — dùng khi test cloud trên chính máy Agent.</summary>
    [HttpPost("{id:guid}/claim")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> ClaimById(
        Guid id, [FromQuery] Guid agentId)
    {
        var denied = await DenyIfCannotUseAgentAsync(agentId);
        if (denied != null) return denied;

        var job = await dispatch.ClaimJobByIdAsync(RequiredStoreId, agentId, id);
        if (job == null)
            return Ok(AppResponse<object>.Success(null));

        return Ok(AppResponse<object>.Success(ToClaimDto(job)));
    }

    static object ToClaimDto(PosPrintJob job) => new
    {
        jobId = job.Id,
        printerId = job.PrinterId,
        documentType = job.DocumentType.ToString(),
        job.ReferenceNo,
        payloadFormat = job.PayloadFormat.ToString(),
        payload = job.Payload,
        job.Copies,
    };

    [HttpPost("{id:guid}/printing")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> MarkPrinting(Guid id, [FromQuery] Guid agentId)
    {
        var denied = await DenyIfCannotUseAgentAsync(agentId);
        if (denied != null) return denied;

        var job = await dispatch.MarkPrintingAsync(id, agentId);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không claim được job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Complete(Guid id, [FromQuery] Guid agentId)
    {
        var denied = await DenyIfCannotUseAgentAsync(agentId);
        if (denied != null) return denied;

        var job = await dispatch.CompleteJobAsync(id, agentId);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không hoàn thành job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }

    [HttpPost("{id:guid}/fail")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Fail(Guid id, [FromQuery] Guid? agentId, [FromBody] FailJobDto dto)
    {
        if (!agentId.HasValue || agentId.Value == Guid.Empty)
            return BadRequest(AppResponse<object>.Fail("Thiếu agentId"));

        var denied = await DenyIfCannotUseAgentAsync(agentId.Value);
        if (denied != null) return denied;

        var job = await dispatch.FailJobAsync(id, agentId, dto.ErrorCode, dto.ErrorMessage);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không cập nhật job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }

    /// Agent không in được trên máy này (USB không gắn…) → nhả Queued cho Agent khác.
    [HttpPost("{id:guid}/release")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Release(
        Guid id,
        [FromQuery] Guid agentId,
        [FromBody] FailJobDto? dto)
    {
        var denied = await DenyIfCannotUseAgentAsync(agentId);
        if (denied != null) return denied;

        var job = await dispatch.ReleaseClaimAsync(
            id,
            agentId,
            dto?.ErrorMessage ?? dto?.ErrorCode ?? "NOT_LOCAL",
            dto?.ErrorCode);
        if (job == null) return NotFound(AppResponse<object>.Fail("Không nhả được job"));
        return Ok(AppResponse<object>.Success(new { status = job.Status.ToString() }));
    }
}
