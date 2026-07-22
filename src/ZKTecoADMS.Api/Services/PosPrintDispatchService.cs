using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public interface IPosPrintDispatchService
{
    Task<PosStorePrinter?> ResolvePrinterAsync(Guid storeId, PosPrintDocumentType documentType, CancellationToken ct = default);
    Task<IReadOnlyList<PosStorePrinter>> ResolvePrintersAsync(Guid storeId, PosPrintDocumentType documentType, CancellationToken ct = default);
    Task EnsureDefaultRoutesAsync(Guid storeId, CancellationToken ct = default);
    Task<PosPrintJob> EnqueueJobAsync(EnqueuePrintJobRequest request, CancellationToken ct = default);
    Task<PosPrintJob?> ClaimNextJobAsync(Guid storeId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> ClaimJobByIdAsync(Guid storeId, Guid agentId, Guid jobId, CancellationToken ct = default);
    Task<PosPrintJob?> MarkPrintingAsync(Guid jobId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> CompleteJobAsync(Guid jobId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> FailJobAsync(Guid jobId, Guid? agentId, string errorCode, string errorMessage, CancellationToken ct = default);
    Task RegisterAgentHeartbeatAsync(Guid storeId, string deviceId, string? deviceName, string? employeeName, string? userId, IEnumerable<Guid> printerIds, string? appVersion, CancellationToken ct = default);
    Task MarkAgentOfflineAsync(Guid storeId, string deviceId, CancellationToken ct = default);
    Task SetPrinterHealthAsync(Guid printerId, PosPrinterHealthStatus status, string? errorMessage, CancellationToken ct = default);
}

public record EnqueuePrintJobRequest(
    Guid StoreId,
    PosPrintDocumentType DocumentType,
    PosPrintPayloadFormat PayloadFormat,
    string Payload,
    int Copies,
    string? ReferenceNo,
    Guid? ReferenceId,
    string? RequestedByUserId,
    string? RequestedByName,
    Guid? PrinterIdOverride = null);

public class PosPrintDispatchService(
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hubContext,
    ILogger<PosPrintDispatchService> logger) : IPosPrintDispatchService
{
    static readonly TimeSpan JobTtl = TimeSpan.FromHours(24);
    static readonly TimeSpan AgentOfflineThreshold = TimeSpan.FromSeconds(90);
    /// <summary>Job Claimed/Printing quá lâu → Queued lại. Phải &lt; client timeout 90s.</summary>
    static readonly TimeSpan StuckClaimReclaimAfter = TimeSpan.FromSeconds(40);
    /// <summary>
    /// Job Queued quá lâu (Agent tắt/offline) → hủy thay vì để dồn hàng đợi.
    /// Trước là 20 phút — Agent tắt máy nửa buổi rồi mở lại sẽ in ồ ạt cả loạt
    /// hóa đơn/phiếu bếp cũ trong 1 lần, trông như "in linh tinh khi bật máy".
    /// 5 phút vẫn đủ chịu được mất kết nối mạng ngắn, nhưng chặn được dồn lô lớn.
    /// </summary>
    static readonly TimeSpan StaleQueuedCancelAfter = TimeSpan.FromMinutes(5);

    public async Task EnsureDefaultRoutesAsync(Guid storeId, CancellationToken ct = default)
    {
        var printers = await db.PosStorePrinters
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.SortOrder)
            .ToListAsync(ct);

        if (printers.Count == 0) return;

        var defaultPrinter = printers.FirstOrDefault(p => p.IsDefault) ?? printers[0];
        if (!printers.Any(p => p.IsDefault))
        {
            defaultPrinter.IsDefault = true;
            defaultPrinter.UpdatedAt = DateTime.UtcNow;
        }

        if (printers.Count == 1)
        {
            foreach (PosPrintDocumentType dt in Enum.GetValues<PosPrintDocumentType>())
            {
                await UpsertRouteAsync(storeId, defaultPrinter.Id, dt, ct);
            }
            await db.SaveChangesAsync(ct);
            return;
        }

        await db.SaveChangesAsync(ct);
    }

    public async Task<PosStorePrinter?> ResolvePrinterAsync(Guid storeId, PosPrintDocumentType documentType, CancellationToken ct = default)
    {
        var list = await ResolvePrintersAsync(storeId, documentType, ct);
        return list.FirstOrDefault();
    }

    public async Task<IReadOnlyList<PosStorePrinter>> ResolvePrintersAsync(
        Guid storeId, PosPrintDocumentType documentType, CancellationToken ct = default)
    {
        await EnsureDefaultRoutesAsync(storeId, ct);

        var routed = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Include(r => r.Printer)
            .Where(r => r.StoreId == storeId && r.DocumentType == documentType
                && r.Deleted == null && r.IsActive && r.Printer != null
                && r.Printer.Deleted == null && r.Printer.IsActive)
            .OrderBy(r => r.CreatedAt)
            .Select(r => r.Printer!)
            .ToListAsync(ct);

        if (routed.Count > 0) return routed;

        var fallback = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDefault)
            .FirstOrDefaultAsync(ct);

        return fallback != null ? [fallback] : [];
    }

    public async Task<PosPrintJob> EnqueueJobAsync(EnqueuePrintJobRequest request, CancellationToken ct = default)
    {
        var printer = request.PrinterIdOverride.HasValue
            ? await db.PosStorePrinters.FirstOrDefaultAsync(p =>
                p.Id == request.PrinterIdOverride && p.StoreId == request.StoreId && p.Deleted == null, ct)
            : await ResolvePrinterAsync(request.StoreId, request.DocumentType, ct);

        if (printer == null)
            throw new InvalidOperationException("Chưa cấu hình máy in cho loại chứng từ này");

        var tracked = await db.PosStorePrinters.FirstAsync(p => p.Id == printer.Id, ct);

        var job = new PosPrintJob
        {
            Id = Guid.NewGuid(),
            StoreId = request.StoreId,
            PrinterId = tracked.Id,
            DocumentType = request.DocumentType,
            ReferenceNo = request.ReferenceNo,
            ReferenceId = request.ReferenceId,
            PayloadFormat = request.PayloadFormat,
            Payload = request.Payload,
            Copies = Math.Clamp(request.Copies, 1, 10),
            Status = PosPrintJobStatus.Queued,
            RequestedByUserId = request.RequestedByUserId,
            RequestedByName = request.RequestedByName,
            ExpiresAt = DateTime.UtcNow.Add(JobTtl),
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = request.RequestedByUserId,
        };

        db.PosPrintJobs.Add(job);
        await db.SaveChangesAsync(ct);

        await BroadcastJobAsync("PrintJobNew", job, tracked, ct);
        logger.LogInformation("Print job {JobId} queued for printer {PrinterId} store {StoreId}",
            job.Id, tracked.Id, request.StoreId);

        return job;
    }

    public async Task<PosPrintJob?> ClaimNextJobAsync(Guid storeId, Guid agentId, CancellationToken ct = default)
    {
        var agent = await db.PosPrintAgents
            .FirstOrDefaultAsync(a => a.Id == agentId && a.StoreId == storeId && a.Deleted == null, ct);
        if (agent == null) return null;

        var assignedIds = ParsePrinterIds(agent.AssignedPrinterIdsJson);
        if (assignedIds.Count == 0)
        {
            logger.LogWarning(
                "ClaimNext skipped — agent {AgentId} has empty AssignedPrinterIdsJson", agentId);
            return null;
        }

        var now = DateTime.UtcNow;
        await ReclaimStuckJobsAsync(storeId, now, ct);

        var candidateId = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && j.Status == PosPrintJobStatus.Queued
                && assignedIds.Contains(j.PrinterId)
                && j.ExpiresAt > now)
            .OrderBy(j => j.CreatedAt)
            .Select(j => j.Id)
            .FirstOrDefaultAsync(ct);

        if (candidateId == Guid.Empty) return null;

        // Chỉ claim khi vẫn Queued — tránh 2 agent in trùng một job.
        var claimed = await db.PosPrintJobs
            .Where(j => j.Id == candidateId && j.Status == PosPrintJobStatus.Queued)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Claimed)
                .SetProperty(j => j.AgentId, agentId)
                .SetProperty(j => j.ClaimedAt, now)
                .SetProperty(j => j.UpdatedAt, now)
                .SetProperty(j => j.AttemptCount, j => j.AttemptCount + 1), ct);

        if (claimed == 0) return null;

        var job = await db.PosPrintJobs.FirstAsync(j => j.Id == candidateId, ct);

        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        printer.HealthStatus = PosPrinterHealthStatus.Busy;
        printer.LastSeenAt = now;
        await db.SaveChangesAsync(ct);

        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    /// <summary>Claim đúng 1 job (test cloud cùng máy / tránh lệch hàng đợi).</summary>
    public async Task<PosPrintJob?> ClaimJobByIdAsync(
        Guid storeId, Guid agentId, Guid jobId, CancellationToken ct = default)
    {
        var agent = await db.PosPrintAgents
            .FirstOrDefaultAsync(a => a.Id == agentId && a.StoreId == storeId && a.Deleted == null, ct);
        if (agent == null) return null;

        var assignedIds = ParsePrinterIds(agent.AssignedPrinterIdsJson);
        if (assignedIds.Count == 0)
        {
            logger.LogWarning(
                "ClaimById skipped — agent {AgentId} has empty AssignedPrinterIdsJson", agentId);
            return null;
        }

        var now = DateTime.UtcNow;
        await ReclaimStuckJobsAsync(storeId, now, ct);

        // Load lại sau reclaim — job kẹt có thể vừa về Queued.
        var job = await db.PosPrintJobs
            .FirstOrDefaultAsync(j => j.Id == jobId && j.StoreId == storeId && j.Deleted == null, ct);
        if (job == null) return null;

        // Đã claim bởi đúng agent này → trả lại để client in tiếp.
        if ((job.Status is PosPrintJobStatus.Claimed or PosPrintJobStatus.Printing)
            && job.AgentId == agentId)
        {
            return job;
        }

        // Job bị agent khác ôm rồi kẹt — reclaim xong mới claim lại.
        if (job.Status is PosPrintJobStatus.Claimed or PosPrintJobStatus.Printing)
            return null;

        if (job.Status != PosPrintJobStatus.Queued) return null;
        if (!assignedIds.Contains(job.PrinterId)) return null;
        if (job.ExpiresAt <= now) return null;

        var claimed = await db.PosPrintJobs
            .Where(j => j.Id == jobId && j.Status == PosPrintJobStatus.Queued)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Claimed)
                .SetProperty(j => j.AgentId, agentId)
                .SetProperty(j => j.ClaimedAt, now)
                .SetProperty(j => j.UpdatedAt, now)
                .SetProperty(j => j.AttemptCount, j => j.AttemptCount + 1), ct);

        if (claimed == 0) return null;

        job = await db.PosPrintJobs.FirstAsync(j => j.Id == jobId, ct);
        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        printer.HealthStatus = PosPrinterHealthStatus.Busy;
        printer.LastSeenAt = now;
        await db.SaveChangesAsync(ct);

        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> MarkPrintingAsync(Guid jobId, Guid agentId, CancellationToken ct = default)
    {
        var job = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId && j.AgentId == agentId, ct);
        if (job == null || job.Status is not (PosPrintJobStatus.Claimed or PosPrintJobStatus.Queued)) return null;

        job.Status = PosPrintJobStatus.Printing;
        job.StartedAt = DateTime.UtcNow;
        job.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> CompleteJobAsync(Guid jobId, Guid agentId, CancellationToken ct = default)
    {
        var job = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId && j.AgentId == agentId, ct);
        if (job == null) return null;

        job.Status = PosPrintJobStatus.Completed;
        job.CompletedAt = DateTime.UtcNow;
        job.UpdatedAt = DateTime.UtcNow;
        job.ErrorCode = null;
        job.ErrorMessage = null;

        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        printer.HealthStatus = PosPrinterHealthStatus.Online;
        printer.LastSeenAt = DateTime.UtcNow;
        printer.LastErrorMessage = null;

        await db.SaveChangesAsync(ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> FailJobAsync(Guid jobId, Guid? agentId, string errorCode, string errorMessage, CancellationToken ct = default)
    {
        var job = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId, ct);
        if (job == null) return null;
        // Cho phép fail job Queued (AgentId null) hoặc đúng agent đã claim.
        if (agentId.HasValue && job.AgentId != null && job.AgentId != agentId) {
            return null;
        }

        job.Status = PosPrintJobStatus.Failed;
        job.CompletedAt = DateTime.UtcNow;
        job.UpdatedAt = DateTime.UtcNow;
        job.ErrorCode = errorCode;
        job.ErrorMessage = errorMessage?.Length > 500 ? errorMessage[..500] : errorMessage;

        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        printer.HealthStatus = PosPrinterHealthStatus.Error;
        printer.LastSeenAt = DateTime.UtcNow;
        printer.LastErrorMessage = job.ErrorMessage;

        await db.SaveChangesAsync(ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task RegisterAgentHeartbeatAsync(
        Guid storeId, string deviceId, string? deviceName, string? employeeName,
        string? userId, IEnumerable<Guid> printerIds, string? appVersion, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var requested = printerIds.Distinct().ToList();
        var aliveIds = new List<Guid>();
        foreach (var pid in requested)
        {
            var printer = await db.PosStorePrinters
                .FirstOrDefaultAsync(p => p.Id == pid && p.StoreId == storeId && p.Deleted == null, ct);
            if (printer == null) continue;
            aliveIds.Add(pid);
            printer.HealthStatus = PosPrinterHealthStatus.Online;
            printer.LastSeenAt = now;
            printer.LastErrorMessage = null;
            printer.RequiresAgent = true;
        }
        if (aliveIds.Count == 0)
            throw new InvalidOperationException(
                "Không có máy in hợp lệ để gắn Agent (đã xóa hoặc sai cửa hàng)");

        var agent = await db.PosPrintAgents
            .FirstOrDefaultAsync(a => a.StoreId == storeId && a.DeviceId == deviceId && a.Deleted == null, ct);

        if (agent == null)
        {
            agent = new PosPrintAgent
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                DeviceId = deviceId,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = userId,
            };
            db.PosPrintAgents.Add(agent);
        }

        agent.DeviceName = deviceName;
        agent.EmployeeName = employeeName;
        agent.UserId = userId;
        agent.AssignedPrinterIdsJson = JsonSerializer.Serialize(aliveIds);
        agent.IsOnline = true;
        agent.LastHeartbeatAt = now;
        agent.AppVersion = appVersion;
        agent.UpdatedAt = now;

        // Mark stale agents offline
        var staleBefore = now.Subtract(AgentOfflineThreshold);
        var staleAgents = await db.PosPrintAgents
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.IsOnline
                && a.Id != agent.Id && (a.LastHeartbeatAt == null || a.LastHeartbeatAt < staleBefore))
            .ToListAsync(ct);
        foreach (var s in staleAgents) s.IsOnline = false;

        await db.SaveChangesAsync(ct);

        await hubContext.Clients.Group(StoreGroup(storeId)).SendAsync("PrinterAgentHeartbeat", new
        {
            agentId = agent.Id,
            deviceId = agent.DeviceId,
            deviceName = agent.DeviceName,
            employeeName = agent.EmployeeName,
            userId = agent.UserId,
            isOnline = true,
            printerIds = aliveIds,
            at = now,
        }, ct);
    }

    public async Task MarkAgentOfflineAsync(
        Guid storeId, string deviceId, CancellationToken ct = default)
    {
        var agent = await db.PosPrintAgents
            .FirstOrDefaultAsync(a => a.StoreId == storeId && a.DeviceId == deviceId && a.Deleted == null, ct);
        if (agent == null) return;

        agent.IsOnline = false;
        agent.LastHeartbeatAt = null; // tránh client vẫn coi «vừa heartbeat»
        agent.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        await hubContext.Clients.Group(StoreGroup(storeId)).SendAsync("PrinterAgentHeartbeat", new
        {
            agentId = agent.Id,
            deviceId = agent.DeviceId,
            deviceName = agent.DeviceName,
            employeeName = agent.EmployeeName,
            userId = agent.UserId,
            isOnline = false,
            forceStop = true, // client đích tắt Agent local
            printerIds = Array.Empty<Guid>(),
            at = DateTime.UtcNow,
        }, ct);
    }

    public async Task SetPrinterHealthAsync(Guid printerId, PosPrinterHealthStatus status, string? errorMessage, CancellationToken ct = default)
    {
        var printer = await db.PosStorePrinters.FirstOrDefaultAsync(p => p.Id == printerId && p.Deleted == null, ct);
        if (printer == null) return;

        printer.HealthStatus = status;
        printer.LastSeenAt = DateTime.UtcNow;
        printer.LastErrorMessage = errorMessage;
        printer.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        await hubContext.Clients.Group(StoreGroup(printer.StoreId)).SendAsync("PrinterStatusChanged", new
        {
            printerId = printer.Id,
            printerName = printer.Name,
            healthStatus = status.ToString(),
            errorMessage,
            at = printer.LastSeenAt,
        }, ct);
    }

    async Task UpsertRouteAsync(Guid storeId, Guid printerId, PosPrintDocumentType documentType, CancellationToken ct)
    {
        var existing = await db.PosPrinterDocumentRoutes
            .FirstOrDefaultAsync(r => r.StoreId == storeId && r.DocumentType == documentType && r.Deleted == null, ct);
        if (existing != null) return;

        db.PosPrinterDocumentRoutes.Add(new PosPrinterDocumentRoute
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            PrinterId = printerId,
            DocumentType = documentType,
            DefaultCopies = 1,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        });
    }

    async Task BroadcastJobAsync(string eventName, PosPrintJob job, PosStorePrinter printer, CancellationToken ct)
    {
        var payload = new
        {
            jobId = job.Id,
            printerId = printer.Id,
            printerName = printer.Name,
            documentType = job.DocumentType.ToString(),
            referenceNo = job.ReferenceNo,
            status = job.Status.ToString(),
            errorCode = job.ErrorCode,
            errorMessage = job.ErrorMessage,
            requestedByName = job.RequestedByName,
            createdAt = job.CreatedAt,
            completedAt = job.CompletedAt,
        };

        if (eventName == "PrintJobNew")
        {
            var jobNew = new
            {
                payload.jobId,
                payload.printerId,
                payload.documentType,
                payload.referenceNo,
                copies = job.Copies,
                payloadFormat = job.PayloadFormat.ToString(),
            };
            // Agent group (chính) + store group (fallback nếu JoinPrintAgentGroup trễ/reconnect).
            await hubContext.Clients.Group(AgentGroup(job.StoreId)).SendAsync(eventName, jobNew, ct);
            await hubContext.Clients.Group(StoreGroup(job.StoreId)).SendAsync(eventName, jobNew, ct);
            return;
        }

        await hubContext.Clients.Group(StoreGroup(job.StoreId)).SendAsync(eventName, payload, ct);
    }

    async Task ReclaimStuckJobsAsync(Guid storeId, DateTime now, CancellationToken ct)
    {
        var stuckBefore = now.Subtract(StuckClaimReclaimAfter);
        var n = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && (j.Status == PosPrintJobStatus.Claimed || j.Status == PosPrintJobStatus.Printing)
                && j.ClaimedAt != null && j.ClaimedAt < stuckBefore)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Queued)
                .SetProperty(j => j.AgentId, (Guid?)null)
                .SetProperty(j => j.ClaimedAt, (DateTime?)null)
                .SetProperty(j => j.StartedAt, (DateTime?)null)
                .SetProperty(j => j.UpdatedAt, now), ct);
        if (n > 0)
            logger.LogWarning("Reclaimed {Count} stuck print job(s) in store {StoreId}", n, storeId);

        // Hủy job Queued quá lâu — tránh Agent xả cả loạt hàng đợi cũ khi vừa mở máy lại.
        var staleQueuedBefore = now.Subtract(StaleQueuedCancelAfter);
        var cancelled = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && j.Status == PosPrintJobStatus.Queued
                && j.CreatedAt < staleQueuedBefore)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Cancelled)
                .SetProperty(j => j.ErrorCode, "STALE_QUEUED")
                .SetProperty(j => j.ErrorMessage,
                    $"Job quá hạn hàng đợi (>{StaleQueuedCancelAfter.TotalMinutes:0} phút) — không có Agent online")
                .SetProperty(j => j.CompletedAt, now)
                .SetProperty(j => j.UpdatedAt, now), ct);
        if (cancelled > 0)
            logger.LogWarning("Cancelled {Count} stale queued print job(s) in store {StoreId}", cancelled, storeId);
    }

    static List<Guid> ParsePrinterIds(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<List<Guid>>(json) ?? [];
        }
        catch
        {
            return [];
        }
    }

    public static string StoreGroup(Guid storeId) => $"store_{storeId}";
    public static string AgentGroup(Guid storeId) => $"store_{storeId}_print_agents";
}
