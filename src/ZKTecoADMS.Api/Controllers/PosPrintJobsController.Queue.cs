using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Hàng đợi in TOÀN CỬA HÀNG — mọi máy (thu ngân, điện thoại phục vụ, máy bếp) cùng thấy lệnh đang chờ / kẹt / lỗi
/// và xử lý được (in lại, chuyển máy in khác, hủy). Trước đây «phiếu treo» chỉ lưu trên đúng máy đã gửi lệnh.
/// </summary>
public partial class PosPrintJobsController
{
    /// <summary>Chờ quá chừng này mà chưa máy nào nhận → coi là treo.</summary>
    const int HungQueuedSeconds = 60;
    /// <summary>Đã nhận / đang in quá chừng này mà chưa xong → coi là treo.</summary>
    const int HungClaimedSeconds = 90;

    public record RetryJobDto(Guid? PrinterId = null);

    [HttpGet("queue")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Queue(
        [FromQuery] int hours = 24,
        [FromQuery] bool includeCompleted = false,
        [FromQuery] int limit = 200)
    {
        var storeId = RequiredStoreId;
        hours = Math.Clamp(hours, 1, 72);
        limit = Math.Clamp(limit, 1, 500);
        var now = DateTime.UtcNow;
        var since = now.AddHours(-hours);

        var q = db.PosPrintJobs.AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null && j.CreatedAt >= since);
        if (!includeCompleted)
            q = q.Where(j => j.Status != PosPrintJobStatus.Completed
                && !(j.Status == PosPrintJobStatus.Cancelled && j.ErrorCode == "USER_CANCELLED"));

        var jobs = await q
            .OrderByDescending(j => j.CreatedAt)
            .Take(limit)
            .Select(j => new
            {
                j.Id, j.PrinterId, j.AgentId, j.DocumentType, j.ReferenceNo, j.ReferenceId, j.Status,
                j.ErrorCode, j.ErrorMessage, j.RequestedByName, j.CreatedAt, j.ClaimedAt, j.StartedAt,
                j.CompletedAt, j.AttemptCount, j.Copies,
            })
            .ToListAsync();

        var printers = await db.PosStorePrinters.IgnoreQueryFilters().AsNoTracking()
            .Where(p => p.StoreId == storeId)
            .Select(p => new
            {
                p.Id, p.Name, ConnectionType = p.ConnectionType.ToString(), p.HealthStatus, p.LastErrorMessage,
                p.IsActive, Deleted = p.Deleted != null, p.RequiresAgent, p.IsDeviceLocal,
            })
            .ToDictionaryAsync(p => p.Id);

        // Agent đang online (heartbeat trong 3 phút) và các máy in nó đang phục vụ.
        var agents = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.IsOnline)
            .Select(a => new { a.Id, a.DeviceName, a.EmployeeName, a.LastHeartbeatAt, a.AssignedPrinterIdsJson })
            .ToListAsync();
        var liveAgents = agents
            .Where(a => a.LastHeartbeatAt is { } hb
                && Math.Min(Math.Abs((now - DateTime.SpecifyKind(hb, DateTimeKind.Utc)).TotalSeconds),
                            Math.Abs((now - hb).TotalSeconds)) <= 180)
            .Select(a => new
            {
                a.Id, a.DeviceName, a.EmployeeName,
                PrinterIds = ParseIds(a.AssignedPrinterIdsJson),
            })
            .ToList();
        var agentsByPrinter = liveAgents
            .SelectMany(a => a.PrinterIds.Select(pid => (pid, name: a.DeviceName ?? a.EmployeeName ?? "Agent")))
            .GroupBy(x => x.pid)
            .ToDictionary(g => g.Key, g => g.Select(x => x.name).Distinct().ToList());
        var agentNames = liveAgents.ToDictionary(a => a.Id, a => a.DeviceName ?? a.EmployeeName ?? "Agent");

        string Problem(PosPrintJobStatus st, double age, Guid printerId)
        {
            // Đã hủy (người dùng / hệ thống: máy in bị xóa, quá hạn…) → không cần xử lý, chỉ hiện ở «Tất cả».
            if (st == PosPrintJobStatus.Cancelled) return "cancelled";
            var p = printers.GetValueOrDefault(printerId);
            if (p == null || p.Deleted || !p.IsActive) return "printer_removed";
            if (st == PosPrintJobStatus.Failed) return "failed";
            if (st == PosPrintJobStatus.Queued && p.RequiresAgent && !agentsByPrinter.ContainsKey(printerId)) return "no_agent";
            if (st == PosPrintJobStatus.Queued && age > HungQueuedSeconds) return "hung";
            if ((st == PosPrintJobStatus.Claimed || st == PosPrintJobStatus.Printing) && age > HungClaimedSeconds) return "hung";
            return "";
        }

        var items = jobs.Select(j =>
        {
            var p = printers.GetValueOrDefault(j.PrinterId);
            var refAt = j.Status is PosPrintJobStatus.Claimed or PosPrintJobStatus.Printing
                ? (j.StartedAt ?? j.ClaimedAt ?? j.CreatedAt) : j.CreatedAt;
            var age = (now - DateTime.SpecifyKind(refAt, DateTimeKind.Utc)).TotalSeconds;
            var problem = j.Status == PosPrintJobStatus.Completed ? "" : Problem(j.Status, age, j.PrinterId);
            return new
            {
                id = j.Id,
                printerId = j.PrinterId,
                printerName = p?.Name ?? "(máy in đã xóa)",
                documentType = j.DocumentType.ToString(),
                referenceNo = j.ReferenceNo,
                referenceId = j.ReferenceId,
                status = j.Status.ToString(),
                problem,
                errorCode = j.ErrorCode,
                errorMessage = j.ErrorMessage,
                requestedByName = j.RequestedByName,
                agentName = j.AgentId is Guid aid ? agentNames.GetValueOrDefault(aid) : null,
                createdAt = j.CreatedAt,
                completedAt = j.CompletedAt,
                ageSeconds = (int)Math.Max(0, (now - DateTime.SpecifyKind(j.CreatedAt, DateTimeKind.Utc)).TotalSeconds),
                attemptCount = j.AttemptCount,
                copies = j.Copies,
            };
        }).ToList();

        var printerSummary = printers.Values
            .Where(p => !p.Deleted && p.IsActive && !p.IsDeviceLocal)
            .Select(p => new
            {
                id = p.Id,
                name = p.Name,
                connectionType = p.ConnectionType,
                health = p.HealthStatus.ToString(),
                lastError = p.LastErrorMessage,
                requiresAgent = p.RequiresAgent,
                agents = agentsByPrinter.GetValueOrDefault(p.Id) ?? [],
                waiting = items.Count(i => i.printerId == p.Id && (i.status == "Queued" || i.status == "Claimed" || i.status == "Printing")),
                problems = items.Count(i => i.printerId == p.Id && i.problem != ""),
            })
            .OrderByDescending(x => x.problems).ThenBy(x => x.name)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            generatedAt = now,
            hungQueuedSeconds = HungQueuedSeconds,
            problemCount = items.Count(i => i.problem != "" && i.problem != "cancelled"),
            waitingCount = items.Count(i => i.status is "Queued" or "Claimed" or "Printing"),
            printers = printerSummary,
            items,
        }));
    }

    [HttpPost("{id:guid}/retry")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Retry(Guid id, [FromBody] RetryJobDto? dto)
    {
        try
        {
            var job = await dispatch.RetryJobAsync(RequiredStoreId, id, dto?.PrinterId, CurrentUserEmail);
            if (job == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy lệnh in"));
            return Ok(AppResponse<object>.Success(new { jobId = job.Id, printerId = job.PrinterId, status = job.Status.ToString() }));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<object>.Fail(ex.Message));
        }
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Cancel(Guid id)
    {
        try
        {
            var job = await dispatch.CancelJobAsync(RequiredStoreId, id, CurrentUserEmail);
            if (job == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy lệnh in"));
            return Ok(AppResponse<object>.Success(new { jobId = job.Id, status = job.Status.ToString() }));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<object>.Fail(ex.Message));
        }
    }

    static List<Guid> ParseIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return JsonSerializer.Deserialize<List<Guid>>(json) ?? []; }
        catch { return []; }
    }
}
