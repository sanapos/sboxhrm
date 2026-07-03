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
    Task EnsureDefaultRoutesAsync(Guid storeId, CancellationToken ct = default);
    Task<PosPrintJob> EnqueueJobAsync(EnqueuePrintJobRequest request, CancellationToken ct = default);
    Task<PosPrintJob?> ClaimNextJobAsync(Guid storeId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> MarkPrintingAsync(Guid jobId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> CompleteJobAsync(Guid jobId, Guid agentId, CancellationToken ct = default);
    Task<PosPrintJob?> FailJobAsync(Guid jobId, Guid? agentId, string errorCode, string errorMessage, CancellationToken ct = default);
    Task RegisterAgentHeartbeatAsync(Guid storeId, string deviceId, string? deviceName, string? employeeName, string? userId, IEnumerable<Guid> printerIds, string? appVersion, CancellationToken ct = default);
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
        await EnsureDefaultRoutesAsync(storeId, ct);

        var route = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Include(r => r.Printer)
            .FirstOrDefaultAsync(r => r.StoreId == storeId && r.DocumentType == documentType
                && r.Deleted == null && r.IsActive && r.Printer != null
                && r.Printer.Deleted == null && r.Printer.IsActive, ct);

        if (route?.Printer != null) return route.Printer;

        return await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDefault)
            .FirstOrDefaultAsync(ct);
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
        if (assignedIds.Count == 0) return null;

        var now = DateTime.UtcNow;
        var job = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && j.Status == PosPrintJobStatus.Queued
                && assignedIds.Contains(j.PrinterId)
                && j.ExpiresAt > now)
            .OrderBy(j => j.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (job == null) return null;

        job.Status = PosPrintJobStatus.Claimed;
        job.AgentId = agentId;
        job.ClaimedAt = now;
        job.AttemptCount += 1;
        job.UpdatedAt = now;

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
        if (agentId.HasValue && job.AgentId != agentId) return null;

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
        var idsJson = JsonSerializer.Serialize(printerIds.Distinct().ToList());

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
        agent.AssignedPrinterIdsJson = idsJson;
        agent.IsOnline = true;
        agent.LastHeartbeatAt = now;
        agent.AppVersion = appVersion;
        agent.UpdatedAt = now;

        foreach (var pid in printerIds)
        {
            var printer = await db.PosStorePrinters
                .FirstOrDefaultAsync(p => p.Id == pid && p.StoreId == storeId && p.Deleted == null, ct);
            if (printer == null) continue;
            printer.HealthStatus = PosPrinterHealthStatus.Online;
            printer.LastSeenAt = now;
            printer.LastErrorMessage = null;
            printer.RequiresAgent = true;
        }

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
            isOnline = true,
            printerIds = printerIds.ToList(),
            at = now,
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

        await hubContext.Clients.Group(StoreGroup(job.StoreId)).SendAsync(eventName, payload, ct);

        if (eventName == "PrintJobNew" && printer.RequiresAgent)
        {
            await hubContext.Clients.Group(AgentGroup(job.StoreId)).SendAsync(eventName, new
            {
                payload.jobId,
                payload.printerId,
                payload.documentType,
                payload.referenceNo,
                copies = job.Copies,
                payloadFormat = job.PayloadFormat.ToString(),
                // Payload chỉ gửi cho agent khi claim qua API (bảo mật)
            }, ct);
        }
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
