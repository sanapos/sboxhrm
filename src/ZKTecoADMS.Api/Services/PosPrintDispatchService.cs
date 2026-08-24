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
    /// Agent nhận nhầm (vd. USB không gắn) → trả Queued để máy Agent khác claim.
    Task<PosPrintJob?> ReleaseClaimAsync(Guid jobId, Guid agentId, string? reason, string? errorCode = null, CancellationToken ct = default);
    Task RegisterAgentHeartbeatAsync(Guid storeId, string deviceId, string? deviceName, string? employeeName, string? userId, IEnumerable<Guid> printerIds, string? appVersion, IEnumerable<Guid>? onlinePrinterIds = null, CancellationToken ct = default);
    Task MarkAgentOfflineAsync(Guid storeId, string deviceId, bool forceStop = true, CancellationToken ct = default);
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
    /// <summary>Claimed quá lâu chưa MarkPrinting → Queued lại.</summary>
    static readonly TimeSpan StuckClaimReclaimAfter = TimeSpan.FromSeconds(90);
    /// <summary>Printing quá lâu (Sunmi có thể &gt;40s) → Queued lại.</summary>
    static readonly TimeSpan StuckPrintingReclaimAfter = TimeSpan.FromSeconds(180);
    /// <summary>Reclaim quá số lần này → hủy (tránh in đôi). Trước = 2 dễ hủy sớm
    /// khi A7 claim+release outbound rồi A6 claim (AttemptCount=2).</summary>
    const int MaxPrintAttemptsBeforeCancel = 5;
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
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && !p.IsDeviceLocal)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.SortOrder)
            .ToListAsync(ct);

        if (printers.Count == 0) return;

        var defaultPrinter = printers.FirstOrDefault(p => p.IsDefault) ?? printers[0];
        if (!printers.Any(p => p.IsDefault))
        {
            var now = DateTime.UtcNow;
            await db.PosStorePrinters
                .Where(p => p.Id == defaultPrinter.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.IsDefault, true)
                    .SetProperty(p => p.UpdatedAt, now), ct);
            defaultPrinter.IsDefault = true;
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
            // Ưu tiên máy cloud/Agent — device-local không được Agent claim.
            .OrderBy(r => r.Printer!.IsDeviceLocal)
            .ThenBy(r => r.CreatedAt)
            .Select(r => r.Printer!)
            .ToListAsync(ct);

        if (routed.Count > 0)
        {
            var remapped = new List<PosStorePrinter>();
            var seen = new HashSet<Guid>();
            foreach (var p in routed)
            {
                var twin = await ResolveCloudAgentTwinAsync(p, ct);
                if (seen.Add(twin.Id)) remapped.Add(twin);
            }
            return remapped;
        }

        var fallback = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive && p.IsDefault)
            .FirstOrDefaultAsync(ct);

        return fallback != null ? [fallback] : [];
    }

    /// <summary>
    /// Máy device-local (sync từ A6) không nằm trong AssignedPrinterIds của Agent.
    /// Đổi sang bản cloud cùng cổng (USB/LAN/BT/Sunmi) để A7/web gửi job Agent nhận được.
    /// </summary>
    async Task<PosStorePrinter> ResolveCloudAgentTwinAsync(
        PosStorePrinter printer, CancellationToken ct = default)
    {
        if (!printer.IsDeviceLocal) return printer;

        var candidates = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == printer.StoreId
                && p.Deleted == null
                && p.IsActive
                && !p.IsDeviceLocal
                && p.ConnectionType == printer.ConnectionType)
            .OrderByDescending(p => p.RequiresAgent)
            .ThenBy(p => p.SortOrder)
            .ToListAsync(ct);

        PosStorePrinter? twin = null;
        switch (printer.ConnectionType)
        {
            case PosPrinterConnectionType.Usb:
                var usb = NormPortKey(printer.UsbDeviceName);
                if (usb.Length > 0)
                {
                    twin = candidates.FirstOrDefault(p =>
                        NormPortKey(p.UsbDeviceName) == usb
                        || NormPortKey(p.UsbDeviceName).StartsWith(usb)
                        || usb.StartsWith(NormPortKey(p.UsbDeviceName)));
                }
                // Fallback: cùng tên (bỏ prefix nội bộ) khi USB id lệch path.
                twin ??= candidates.FirstOrDefault(p =>
                    string.Equals(StripLocalPrefix(p.Name), StripLocalPrefix(printer.Name),
                        StringComparison.OrdinalIgnoreCase));
                break;
            case PosPrinterConnectionType.Lan:
                var host = (printer.LanHost ?? "").Trim().ToLowerInvariant();
                if (host.Length > 0)
                    twin = candidates.FirstOrDefault(p =>
                        string.Equals((p.LanHost ?? "").Trim(), host, StringComparison.OrdinalIgnoreCase));
                twin ??= candidates.FirstOrDefault(p =>
                    string.Equals(StripLocalPrefix(p.Name), StripLocalPrefix(printer.Name),
                        StringComparison.OrdinalIgnoreCase));
                break;
            case PosPrinterConnectionType.Bluetooth:
                var bt = (printer.BluetoothAddress ?? "").Trim().ToLowerInvariant();
                if (bt.Length > 0)
                    twin = candidates.FirstOrDefault(p =>
                        string.Equals((p.BluetoothAddress ?? "").Trim(), bt,
                            StringComparison.OrdinalIgnoreCase));
                break;
            case PosPrinterConnectionType.Sunmi:
                twin = candidates.FirstOrDefault();
                break;
        }

        if (twin == null)
        {
            logger.LogWarning(
                "No cloud Agent twin for device-local printer {PrinterId} ({Name}/{Conn}) store {StoreId}",
                printer.Id, printer.Name, printer.ConnectionType, printer.StoreId);
            return printer;
        }

        logger.LogInformation(
            "Remap device-local printer {LocalId} → cloud Agent {CloudId} ({Name})",
            printer.Id, twin.Id, twin.Name);
        return twin;
    }

    static string NormPortKey(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        var t = raw.Trim();
        var pipe = t.IndexOf('|');
        if (pipe > 0) t = t[..pipe];
        return t.ToLowerInvariant();
    }

    /// <summary>
    /// Khóa nhận dạng «cùng một máy in vật lý»: VID:PID:serial cho USB (bỏ
    /// /dev/bus/usb/… vì đổi mỗi lần cắm lại), host:port cho LAN, MAC cho BT.
    /// Không có cổng thì rơi về tên đã bỏ prefix nội bộ.
    /// </summary>
    static string PhysicalPrinterKey(PosStorePrinter p)
    {
        var port = p.ConnectionType switch
        {
            PosPrinterConnectionType.Usb => NormPortKey(p.UsbDeviceName),
            PosPrinterConnectionType.Lan =>
                $"{(p.LanHost ?? "").Trim().ToLowerInvariant()}:{p.LanPort}",
            PosPrinterConnectionType.Bluetooth =>
                (p.BluetoothAddress ?? "").Trim().ToLowerInvariant(),
            _ => "",
        };
        if (p.ConnectionType == PosPrinterConnectionType.Lan &&
            port.StartsWith(':')) port = "";
        if (port.Length > 0) return $"{p.ConnectionType}|{port}";
        return $"{p.ConnectionType}|name:{StripLocalPrefix(p.Name).ToLowerInvariant()}";
    }

    /// <summary>
    /// Cùng một máy in vật lý thường có nhiều bản ghi cloud (cắm lại USB đổi
    /// /dev/bus/usb/… → app tạo chip mới). Agent chỉ claim theo đúng PrinterId
    /// đã chọn, nên job gửi vào bản ghi «anh em» sẽ nằm Queued tới khi hết hạn:
    /// người dùng thấy «gán máy in rồi mà không in, chỉ máy WiFi ra phiếu».
    /// Trước khi tạo job: nếu máy đích không Agent nào online phục vụ mà có bản
    /// ghi cùng cổng đang được phục vụ thì chuyển job sang bản ghi đó.
    /// </summary>
    async Task<PosStorePrinter> RedirectToLiveAgentTwinAsync(
        PosStorePrinter printer, CancellationToken ct = default)
    {
        if (printer.IsDeviceLocal) return printer;

        var staleBefore = DateTime.UtcNow.Subtract(AgentOfflineThreshold);
        var agentJsons = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == printer.StoreId && a.Deleted == null
                && a.IsOnline && a.LastHeartbeatAt != null
                && a.LastHeartbeatAt >= staleBefore)
            .Select(a => a.AssignedPrinterIdsJson)
            .ToListAsync(ct);
        if (agentJsons.Count == 0) return printer;

        var served = new HashSet<Guid>();
        foreach (var json in agentJsons)
        {
            foreach (var id in ParsePrinterIds(json)) served.Add(id);
        }
        if (served.Count == 0 || served.Contains(printer.Id)) return printer;

        var key = PhysicalPrinterKey(printer);
        var twins = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == printer.StoreId && p.Deleted == null
                && p.IsActive && !p.IsDeviceLocal && p.Id != printer.Id
                && p.ConnectionType == printer.ConnectionType
                && served.Contains(p.Id))
            .ToListAsync(ct);

        var twin = twins.FirstOrDefault(p => PhysicalPrinterKey(p) == key)
            ?? twins.FirstOrDefault(p => string.Equals(
                StripLocalPrefix(p.Name), StripLocalPrefix(printer.Name),
                StringComparison.OrdinalIgnoreCase));
        if (twin == null) return printer;

        logger.LogWarning(
            "Printer {PrinterId} ({Name}) has no online Agent — redirect job to twin {TwinId} store {StoreId}",
            printer.Id, printer.Name, twin.Id, printer.StoreId);
        return twin;
    }

    static string StripLocalPrefix(string? name)
    {
        var n = (name ?? "").Trim();
        if (n.StartsWith("[Nội bộ]", StringComparison.OrdinalIgnoreCase))
            n = n["[Nội bộ]".Length..].Trim();
        return n;
    }

    /// <summary>
    /// ReferenceNo là varchar(64). Client bếp/kho ghép order + id máy + id món nên
    /// dễ vượt 64 → insert lỗi 22001 → app không tạo được job, phiếu treo hàng chờ.
    /// Rút gọn ổn định (đầu chuỗi + hash) để dedup theo ReferenceNo vẫn đúng.
    /// </summary>
    internal static string? FitReferenceNo(string? referenceNo, int maxLen = 64)
    {
        var value = referenceNo?.Trim();
        if (string.IsNullOrEmpty(value) || value.Length <= maxLen) return value;

        var hash = 0x811c9dc5u;
        foreach (var c in value)
        {
            hash = (hash ^ c) * 0x01000193u;
        }
        var suffix = hash.ToString("x8");
        return string.Concat(value.AsSpan(0, maxLen - suffix.Length - 1), "~", suffix);
    }

    public async Task<PosPrintJob> EnqueueJobAsync(EnqueuePrintJobRequest request, CancellationToken ct = default)
    {
        request = request with { ReferenceNo = FitReferenceNo(request.ReferenceNo) };

        var printer = request.PrinterIdOverride.HasValue
            ? await db.PosStorePrinters.FirstOrDefaultAsync(p =>
                p.Id == request.PrinterIdOverride && p.StoreId == request.StoreId && p.Deleted == null, ct)
            : await ResolvePrinterAsync(request.StoreId, request.DocumentType, ct);

        if (printer == null)
            throw new InvalidOperationException("Chưa cấu hình máy in cho loại chứng từ này");

        printer = await ResolveCloudAgentTwinAsync(printer, ct);
        printer = await RedirectToLiveAgentTwinAsync(printer, ct);

        var tracked = await db.PosStorePrinters.FirstAsync(p => p.Id == printer.Id, ct);

        // Chặn in trùng khi job còn đang chạy (Queued/Claimed/Printing).
        // KHÔNG dedup Completed — nếu không, «In lại» trong 10 phút báo thành công
        // nhưng không ra giấy (sót bill khi khách xin thêm bản).
        var since = DateTime.UtcNow.AddMinutes(-10);
        PosPrintJob? duplicate = null;
        if (request.ReferenceId is { } refId && refId != Guid.Empty)
        {
            duplicate = await db.PosPrintJobs.AsNoTracking()
                .Where(j => j.StoreId == request.StoreId
                    && j.PrinterId == tracked.Id
                    && j.Deleted == null
                    && j.CreatedAt >= since
                    && j.ReferenceId == refId
                    && j.DocumentType == request.DocumentType
                    && (j.Status == PosPrintJobStatus.Queued
                        || j.Status == PosPrintJobStatus.Claimed
                        || j.Status == PosPrintJobStatus.Printing))
                .OrderByDescending(j => j.CreatedAt)
                .FirstOrDefaultAsync(ct);
        }
        duplicate ??= await db.PosPrintJobs.AsNoTracking()
            .Where(j => j.StoreId == request.StoreId
                && j.PrinterId == tracked.Id
                && j.Deleted == null
                && j.CreatedAt >= since
                && j.PayloadFormat == request.PayloadFormat
                && j.Payload == request.Payload
                && (j.Status == PosPrintJobStatus.Queued
                    || j.Status == PosPrintJobStatus.Claimed
                    || j.Status == PosPrintJobStatus.Printing))
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (duplicate != null)
        {
            logger.LogInformation(
                "Print job dedup hit — reuse {JobId} (printer {PrinterId}, age {AgeSec:F0}s)",
                duplicate.Id, tracked.Id,
                (DateTime.UtcNow - duplicate.CreatedAt).TotalSeconds);
            var reused = await db.PosPrintJobs.FirstAsync(j => j.Id == duplicate.Id, ct);
            // Job cũ còn nằm hàng đợi nghĩa là không Agent nào nhận được tín hiệu
            // lần trước (mất mạng / vừa mở lại app). Không phát lại thì lệnh in
            // thứ hai bị nuốt, treo tới lúc hết hạn rồi im lặng mất phiếu.
            if (reused.Status == PosPrintJobStatus.Queued)
                await BroadcastJobAsync("PrintJobNew", reused, tracked, ct);
            return reused;
        }

        // Dedup theo ReferenceNo (bếp/kho gửi chuỗi ổn định, không phải Guid).
        if (!string.IsNullOrWhiteSpace(request.ReferenceNo))
        {
            var refNo = request.ReferenceNo.Trim();
            duplicate = await db.PosPrintJobs.AsNoTracking()
                .Where(j => j.StoreId == request.StoreId
                    && j.PrinterId == tracked.Id
                    && j.Deleted == null
                    && j.CreatedAt >= since
                    && j.ReferenceNo == refNo
                    && j.DocumentType == request.DocumentType
                    && (j.Status == PosPrintJobStatus.Queued
                        || j.Status == PosPrintJobStatus.Claimed
                        || j.Status == PosPrintJobStatus.Printing))
                .OrderByDescending(j => j.CreatedAt)
                .FirstOrDefaultAsync(ct);
            if (duplicate != null)
            {
                logger.LogInformation(
                    "Print job dedup by ReferenceNo — reuse {JobId} ref={Ref}",
                    duplicate.Id, refNo);
                return await db.PosPrintJobs.FirstAsync(j => j.Id == duplicate.Id, ct);
            }
        }

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

        // Không SaveChanges sau claim — lỗi DB (vd. cột ngắn) để job kẹt Claimed
        // rồi STUCK_NO_REQUEUE (tem hay dính).
        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Busy)
                .SetProperty(p => p.LastSeenAt, now)
                .SetProperty(p => p.UpdatedAt, now), ct);

        var printer = await db.PosStorePrinters.AsNoTracking()
            .FirstAsync(p => p.Id == job.PrinterId, ct);
        try
        {
            await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Broadcast after claim failed for job {JobId}", job.Id);
        }
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
        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Busy)
                .SetProperty(p => p.LastSeenAt, now)
                .SetProperty(p => p.UpdatedAt, now), ct);

        var printer = await db.PosStorePrinters.AsNoTracking()
            .FirstAsync(p => p.Id == job.PrinterId, ct);
        try
        {
            await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Broadcast after ClaimById failed for job {JobId}", job.Id);
        }
        return job;
    }

    public async Task<PosPrintJob?> MarkPrintingAsync(Guid jobId, Guid agentId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var updated = await db.PosPrintJobs
            .Where(j => j.Id == jobId && j.AgentId == agentId &&
                        (j.Status == PosPrintJobStatus.Claimed || j.Status == PosPrintJobStatus.Queued))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Printing)
                .SetProperty(j => j.StartedAt, now)
                .SetProperty(j => j.UpdatedAt, now), ct);

        if (updated == 0)
        {
            var existing = await db.PosPrintJobs.AsNoTracking()
                .FirstOrDefaultAsync(j => j.Id == jobId && j.AgentId == agentId, ct);
            return existing?.Status == PosPrintJobStatus.Printing ? existing : null;
        }

        var job = await db.PosPrintJobs.FirstAsync(j => j.Id == jobId, ct);
        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> CompleteJobAsync(Guid jobId, Guid agentId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;

        // Đã complete rồi → idempotent OK (tránh Agent retry báo lỗi).
        var existing = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId, ct);
        if (existing == null) return null;
        if (existing.Status == PosPrintJobStatus.Completed) return existing;

        if (existing.AgentId != null && existing.AgentId != agentId)
            return null;

        if (existing.Status is not (PosPrintJobStatus.Claimed or PosPrintJobStatus.Printing
            or PosPrintJobStatus.Queued))
            return null;

        var updated = await db.PosPrintJobs
            .Where(j => j.Id == jobId &&
                        (j.AgentId == null || j.AgentId == agentId) &&
                        (j.Status == PosPrintJobStatus.Claimed
                         || j.Status == PosPrintJobStatus.Printing
                         || j.Status == PosPrintJobStatus.Queued))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Completed)
                .SetProperty(j => j.AgentId, agentId)
                .SetProperty(j => j.CompletedAt, now)
                .SetProperty(j => j.UpdatedAt, now)
                .SetProperty(j => j.ErrorCode, (string?)null)
                .SetProperty(j => j.ErrorMessage, (string?)null), ct);

        if (updated == 0)
        {
            existing = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId, ct);
            return existing?.Status == PosPrintJobStatus.Completed ? existing : null;
        }

        var job = await db.PosPrintJobs.FirstAsync(j => j.Id == jobId, ct);
        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Online)
                .SetProperty(p => p.LastSeenAt, now)
                .SetProperty(p => p.LastErrorMessage, (string?)null), ct);
        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> FailJobAsync(Guid jobId, Guid? agentId, string errorCode, string errorMessage, CancellationToken ct = default)
    {
        var job = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId, ct);
        if (job == null) return null;
        // Không ghi đè job đã xong — tránh Agent fail trùng sau khi đã in + Complete.
        if (job.Status is PosPrintJobStatus.Completed
            or PosPrintJobStatus.Cancelled)
        {
            return job;
        }
        // Cho phép fail job Queued (AgentId null) hoặc đúng agent đã claim.
        if (agentId.HasValue && job.AgentId != null && job.AgentId != agentId) {
            return null;
        }

        var now = DateTime.UtcNow;
        var safeError = errorMessage?.Length > 500 ? errorMessage[..500] : errorMessage;

        await db.PosPrintJobs
            .Where(j => j.Id == jobId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(j => j.Status, PosPrintJobStatus.Failed)
                .SetProperty(j => j.CompletedAt, now)
                .SetProperty(j => j.UpdatedAt, now)
                .SetProperty(j => j.ErrorCode, errorCode)
                .SetProperty(j => j.ErrorMessage, safeError), ct);

        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Error)
                .SetProperty(p => p.LastSeenAt, now)
                .SetProperty(p => p.LastErrorMessage, safeError), ct);

        job.Status = PosPrintJobStatus.Failed;
        job.CompletedAt = now;
        job.UpdatedAt = now;
        job.ErrorCode = errorCode;
        job.ErrorMessage = safeError;

        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        return job;
    }

    public async Task<PosPrintJob?> ReleaseClaimAsync(
        Guid jobId, Guid agentId, string? reason, string? errorCode = null,
        CancellationToken ct = default)
    {
        var job = await db.PosPrintJobs.FirstOrDefaultAsync(j => j.Id == jobId, ct);
        if (job == null) return null;
        if (job.Status is PosPrintJobStatus.Completed
            or PosPrintJobStatus.Cancelled
            or PosPrintJobStatus.Failed)
        {
            return job;
        }

        if (job.AgentId != null && job.AgentId != agentId)
            return null;

        if (job.Status is not (PosPrintJobStatus.Claimed or PosPrintJobStatus.Printing
            or PosPrintJobStatus.Queued))
            return null;

        var now = DateTime.UtcNow;

        // Agent nhả vì không mở được cổng in (USB rút, LAN sai IP…). Nếu không
        // còn Agent nào khác nhận máy in này thì Queued = mất phiếu im lặng:
        // máy gửi chờ 60s mới báo treo, còn job nằm tới lúc hết hạn. Fail ngay
        // để thu ngân thấy lỗi và chọn máy khác / in lại trong 1 giây.
        if (IsPortUnavailableRelease(errorCode, reason)
            && !await HasOtherLiveAgentForPrinterAsync(job.StoreId, job.PrinterId, agentId, now, ct))
        {
            return await FailJobAsync(
                jobId, agentId, "NO_AGENT_PORT",
                "Không máy nào mở được cổng in này — kiểm tra dây USB/IP máy in "
                + "hoặc chọn máy in khác",
                ct);
        }

        var releaseError = string.IsNullOrWhiteSpace(reason)
            ? "Agent nhả job — máy khác claim"
            : (reason!.Length > 500 ? reason[..500] : reason);

        await db.PosPrintJobs
            .Where(j => j.Id == jobId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(j => j.Status, PosPrintJobStatus.Queued)
                .SetProperty(j => j.AgentId, (Guid?)null)
                .SetProperty(j => j.ClaimedAt, (DateTime?)null)
                .SetProperty(j => j.StartedAt, (DateTime?)null)
                .SetProperty(j => j.UpdatedAt, now)
                // Soft release (OUTBOUND_SKIP / NOT_LOCAL / …): hoàn AttemptCount —
                // nếu không, A7 claim+nhả rồi A6 claim dễ chạm MAX_ATTEMPTS và bị hủy.
                .SetProperty(j => j.AttemptCount,
                    j => j.AttemptCount > 0 ? j.AttemptCount - 1 : 0)
                .SetProperty(j => j.ErrorCode, "RELEASED")
                .SetProperty(j => j.ErrorMessage, releaseError), ct);

        job.Status = PosPrintJobStatus.Queued;
        job.AgentId = null;
        job.ClaimedAt = null;
        job.StartedAt = null;
        job.UpdatedAt = now;
        if (job.AttemptCount > 0) job.AttemptCount -= 1;
        job.ErrorCode = "RELEASED";
        job.ErrorMessage = releaseError;

        // Không đánh Error — chỉ nhả để Agent đúng máy nhận.
        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId
                && p.HealthStatus == PosPrinterHealthStatus.Busy)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Online), ct);
        await db.PosStorePrinters
            .Where(p => p.Id == job.PrinterId)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.LastSeenAt, now), ct);
        var printer = await db.PosStorePrinters.FirstAsync(p => p.Id == job.PrinterId, ct);

        // Báo lại PrintJobNew để Agent khác (A6) claim ngay.
        await BroadcastJobAsync("PrintJobNew", job, printer, ct);
        await BroadcastJobAsync("PrintJobStatusChanged", job, printer, ct);
        logger.LogInformation(
            "Print job {JobId} released by agent {AgentId}: {Reason}",
            jobId, agentId, job.ErrorMessage);
        return job;
    }

    /// <summary>
    /// Nhả vì cổng in không mở được (khác với OUTBOUND_SKIP — máy gửi nhường
    /// cho Agent thật, job đó vẫn có nơi để chạy).
    /// </summary>
    static bool IsPortUnavailableRelease(string? errorCode, string? reason) =>
        (errorCode != null && errorCode.Contains("NOT_LOCAL", StringComparison.OrdinalIgnoreCase))
        || (reason != null && reason.Contains("NOT_LOCAL", StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Còn Agent nào khác (ngoài <paramref name="excludeAgentId"/>) đang heartbeat
    /// và nhận máy in này không.
    /// </summary>
    async Task<bool> HasOtherLiveAgentForPrinterAsync(
        Guid storeId, Guid printerId, Guid excludeAgentId, DateTime now, CancellationToken ct)
    {
        var since = now.Subtract(AgentOfflineThreshold);
        var agents = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.Id != excludeAgentId
                && a.LastHeartbeatAt != null && a.LastHeartbeatAt >= since)
            .Select(a => a.AssignedPrinterIdsJson)
            .ToListAsync(ct);
        foreach (var json in agents)
        {
            if (string.IsNullOrWhiteSpace(json)) continue;
            try
            {
                var ids = JsonSerializer.Deserialize<List<Guid>>(json!);
                if (ids != null && ids.Contains(printerId)) return true;
            }
            catch { /* JSON hỏng → coi như agent đó không nhận máy in này */ }
        }
        return false;
    }

    public async Task RegisterAgentHeartbeatAsync(
        Guid storeId, string deviceId, string? deviceName, string? employeeName,
        string? userId, IEnumerable<Guid> printerIds, string? appVersion,
        IEnumerable<Guid>? onlinePrinterIds = null, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var requested = printerIds.Distinct().ToList();
        // Null = Agent cu (Win) chưa gửi onlinePrinterIds → KHÔNG stamp Online (tránh ghi đè Offline từ probe).
        // Có list (kể cả rỗng) = Agent mới đã probe → cập nhật Online/Offline theo probe.
        var healthKnown = onlinePrinterIds != null;
        var onlineSet = healthKnown
            ? onlinePrinterIds!.Distinct().ToHashSet()
            : new HashSet<Guid>();
        var aliveIds = new List<Guid>();
        foreach (var pid in requested)
        {
            var isOnline = healthKnown && onlineSet.Contains(pid);
            int updated;
            if (isOnline)
            {
                updated = await db.PosStorePrinters
                    .Where(p => p.Id == pid && p.StoreId == storeId && p.Deleted == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Online)
                        .SetProperty(p => p.LastSeenAt, now)
                        .SetProperty(p => p.LastErrorMessage, (string?)null)
                        .SetProperty(p => p.RequiresAgent, true)
                        .SetProperty(p => p.UpdatedAt, now), ct);
            }
            else
            {
                updated = await db.PosStorePrinters
                    .Where(p => p.Id == pid && p.StoreId == storeId && p.Deleted == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(p => p.RequiresAgent, true)
                        .SetProperty(p => p.UpdatedAt, now), ct);
            }
            if (updated > 0) aliveIds.Add(pid);
        }
        if (aliveIds.Count == 0)
            throw new InvalidOperationException(
                "Không có máy in hợp lệ để gắn Agent (đã xóa hoặc sai cửa hàng)");

        // Truncate to DB column limits — AppVersion varchar(32) từng làm SaveChanges
        // ném 22001 rồi client vẫn claim bằng agentId cũ → agentOnlineForPrinter=0.
        static string? TrimOrNull(string? v, int max)
        {
            if (string.IsNullOrWhiteSpace(v)) return null;
            var t = v.Trim();
            return t.Length <= max ? t : t[..max];
        }

        var safeDeviceName = TrimOrNull(deviceName, 200);
        var safeEmployeeName = TrimOrNull(employeeName, 200);
        var safeUserId = TrimOrNull(userId, 450);
        var safeAppVersion = TrimOrNull(appVersion, 32);
        var printersJson = JsonSerializer.Serialize(aliveIds);

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
                CreatedBy = safeUserId,
                DeviceName = safeDeviceName,
                EmployeeName = safeEmployeeName,
                UserId = safeUserId,
                AssignedPrinterIdsJson = printersJson,
                IsOnline = true,
                LastHeartbeatAt = now,
                AppVersion = safeAppVersion,
                UpdatedAt = now,
            };
            db.PosPrintAgents.Add(agent);
            await db.SaveChangesAsync(ct);
        }
        else
        {
            // ExecuteUpdate tránh change-tracker / interceptor làm heartbeat «OK» nhưng DB không đổi.
            var n = await db.PosPrintAgents
                .Where(a => a.Id == agent.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(a => a.DeviceName, safeDeviceName)
                    .SetProperty(a => a.EmployeeName, safeEmployeeName)
                    .SetProperty(a => a.UserId, safeUserId)
                    .SetProperty(a => a.AssignedPrinterIdsJson, printersJson)
                    .SetProperty(a => a.IsOnline, true)
                    .SetProperty(a => a.LastHeartbeatAt, now)
                    .SetProperty(a => a.AppVersion, safeAppVersion)
                    .SetProperty(a => a.UpdatedAt, now), ct);
            if (n == 0)
                throw new InvalidOperationException("Không cập nhật được Print Agent heartbeat");
            agent.DeviceName = safeDeviceName;
            agent.EmployeeName = safeEmployeeName;
            agent.UserId = safeUserId;
            agent.AssignedPrinterIdsJson = printersJson;
            agent.IsOnline = true;
            agent.LastHeartbeatAt = now;
            agent.AppVersion = safeAppVersion;
        }

        // Chỉ demote khi Agent đã gửi onlinePrinterIds (probe). Null = Agent cũ → bỏ qua.
        if (healthKnown)
        {
            foreach (var pid in requested.Where(id => !onlineSet.Contains(id)))
            {
                var coveredElsewhere = await HasOtherLiveAgentForPrinterAsync(
                    storeId, pid, agent.Id, now, ct);
                if (coveredElsewhere) continue;
                await db.PosStorePrinters
                    .Where(p => p.Id == pid && p.StoreId == storeId && p.Deleted == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Offline)
                        .SetProperty(p => p.LastSeenAt, now)
                        .SetProperty(p => p.LastErrorMessage, "Mất kết nối trên máy Agent")
                        .SetProperty(p => p.RequiresAgent, true)
                        .SetProperty(p => p.UpdatedAt, now), ct);
            }
        }

        // Mark stale agents offline
        var staleBefore = now.Subtract(AgentOfflineThreshold);
        await db.PosPrintAgents
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.IsOnline
                && a.Id != agent.Id
                && (a.LastHeartbeatAt == null || a.LastHeartbeatAt < staleBefore))
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.IsOnline, false)
                .SetProperty(a => a.UpdatedAt, now), ct);

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
        Guid storeId, string deviceId, bool forceStop = true, CancellationToken ct = default)
    {
        var agent = await db.PosPrintAgents
            .FirstOrDefaultAsync(a => a.StoreId == storeId && a.DeviceId == deviceId && a.Deleted == null, ct);
        if (agent == null) return;

        // ExecuteUpdate: DbContext chạy NoTracking toàn cục nên gán rồi SaveChanges
        // không ghi gì — Agent tắt máy vẫn «online», job cứ gửi vào máy đã tắt.
        await db.PosPrintAgents
            .Where(a => a.Id == agent.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.IsOnline, false)
                // tránh client vẫn coi «vừa heartbeat»
                .SetProperty(a => a.LastHeartbeatAt, (DateTime?)null)
                // Unshare hết chip → không giữ GUID máy đã xóa (orphan cleanup poison).
                .SetProperty(a => a.AssignedPrinterIdsJson, "[]")
                .SetProperty(a => a.UpdatedAt, DateTime.UtcNow), ct);

        await hubContext.Clients.Group(StoreGroup(storeId)).SendAsync("PrinterAgentHeartbeat", new
        {
            agentId = agent.Id,
            deviceId = agent.DeviceId,
            deviceName = agent.DeviceName,
            employeeName = agent.EmployeeName,
            userId = agent.UserId,
            isOnline = false,
            // Chỉ true khi máy khác bấm «Tắt Agent». Self-offline (hết chip / tắt local)
            // mà forceStop thì A6 tự nhận SignalR → báo nhầm «tắt từ máy khác».
            forceStop,
            printerIds = Array.Empty<Guid>(),
            at = DateTime.UtcNow,
        }, ct);
    }

    public async Task SetPrinterHealthAsync(Guid printerId, PosPrinterHealthStatus status, string? errorMessage, CancellationToken ct = default)
    {
        var printer = await db.PosStorePrinters.FirstOrDefaultAsync(p => p.Id == printerId && p.Deleted == null, ct);
        if (printer == null) return;

        var now = DateTime.UtcNow;
        await db.PosStorePrinters
            .Where(p => p.Id == printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, status)
                .SetProperty(p => p.LastSeenAt, now)
                .SetProperty(p => p.LastErrorMessage, errorMessage)
                .SetProperty(p => p.UpdatedAt, now), ct);
        printer.HealthStatus = status;
        printer.LastSeenAt = now;
        printer.LastErrorMessage = errorMessage;

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
        // Unique (StoreId, DocumentType, PrinterId) gồm cả bản soft-delete.
        // Unshare → reshare revive cùng PrinterId: nếu INSERT lại sẽ 23505
        // → client «Không tạo máy in Agent / đã xảy ra lỗi hệ thống».
        var samePrinter = await db.PosPrinterDocumentRoutes
            .IgnoreQueryFilters()
            .AsTracking()
            .FirstOrDefaultAsync(
                r => r.StoreId == storeId
                     && r.PrinterId == printerId
                     && r.DocumentType == documentType,
                ct);
        if (samePrinter != null)
        {
            if (samePrinter.Deleted != null || !samePrinter.IsActive)
            {
                samePrinter.Deleted = null;
                samePrinter.DeletedBy = null;
                samePrinter.IsActive = true;
                samePrinter.DefaultCopies = samePrinter.DefaultCopies <= 0 ? 1 : samePrinter.DefaultCopies;
                samePrinter.UpdatedAt = DateTime.UtcNow;
            }
            return;
        }

        // Đã có route sống cho loại chứng từ (máy khác) → không ép gán thêm.
        var liveOther = await db.PosPrinterDocumentRoutes
            .AsNoTracking()
            .AnyAsync(
                r => r.StoreId == storeId
                     && r.DocumentType == documentType
                     && r.Deleted == null,
                ct);
        if (liveOther) return;

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

    /// <summary>
    /// Lần dọn hàng đợi gần nhất theo cửa hàng. Mỗi Agent poll 3s/lần nên chuỗi
    /// cửa hàng đông thiết bị bắn hàng chục lượt dọn mỗi giây — toàn bộ là
    /// ExecuteUpdate ghi DB. Ngưỡng dọn nhỏ nhất là 90s nên dọn mỗi 15s là thừa
    /// nhanh, mà tải DB giảm theo số Agent.
    /// </summary>
    static readonly System.Collections.Concurrent.ConcurrentDictionary<Guid, DateTime>
        _lastReclaimAt = new();

    static readonly TimeSpan ReclaimThrottle = TimeSpan.FromSeconds(15);

    async Task ReclaimStuckJobsAsync(Guid storeId, DateTime now, CancellationToken ct)
    {
        if (_lastReclaimAt.TryGetValue(storeId, out var last)
            && now - last < ReclaimThrottle)
            return;
        _lastReclaimAt[storeId] = now;

        // Đã thử quá nhiều lần → hủy thay vì Queued lại (chống in trùng liên tục).
        var overAttempt = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && (j.Status == PosPrintJobStatus.Claimed || j.Status == PosPrintJobStatus.Printing)
                && j.AttemptCount >= MaxPrintAttemptsBeforeCancel)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Cancelled)
                .SetProperty(j => j.ErrorCode, "MAX_ATTEMPTS")
                .SetProperty(j => j.ErrorMessage,
                    $"Đã claim {MaxPrintAttemptsBeforeCancel}+ lần — hủy để tránh in trùng")
                .SetProperty(j => j.CompletedAt, now)
                .SetProperty(j => j.UpdatedAt, now), ct);
        if (overAttempt > 0)
            logger.LogWarning(
                "Cancelled {Count} over-attempt print job(s) in store {StoreId}",
                overAttempt, storeId);

        // Tem/label + phiếu bếp/hủy: Claimed lâu (chưa MarkPrinting) → requeue
        // thay vì STUCK_NO_REQUEUE (web→A6: hủy xong Busy treo, không ra giấy).
        var softRequeueTypes = new[]
        {
            PosPrintDocumentType.KitchenLabel,
            PosPrintDocumentType.BarcodeLabel,
            PosPrintDocumentType.KitchenSlip,
            PosPrintDocumentType.KitchenVoid,
        };
        var softClaimedBefore = now.Subtract(TimeSpan.FromSeconds(90));
        // Chỉ nhả job của Agent đã tắt/mất mạng. Agent còn sống mà claim lâu là
        // đang xếp hàng sau phiếu khác trên cùng máy in (bếp đông) — cướp job
        // của nó thì máy thứ hai in ra phiếu y hệt, bếp làm món hai lần.
        var liveAgentIds = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null
                && a.IsOnline && a.LastHeartbeatAt != null
                && a.LastHeartbeatAt >= now.Subtract(AgentOfflineThreshold))
            .Select(a => a.Id)
            .ToListAsync(ct);
        var softRequeued = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && j.Status == PosPrintJobStatus.Claimed
                && softRequeueTypes.Contains(j.DocumentType)
                && j.ClaimedAt != null
                && j.ClaimedAt < softClaimedBefore
                && (j.AgentId == null || !liveAgentIds.Contains(j.AgentId.Value))
                && j.AttemptCount < MaxPrintAttemptsBeforeCancel)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Queued)
                .SetProperty(j => j.AgentId, (Guid?)null)
                .SetProperty(j => j.ClaimedAt, (DateTime?)null)
                .SetProperty(j => j.ErrorCode, "SOFT_REQUEUE")
                .SetProperty(j => j.ErrorMessage,
                    "Claim quá lâu chưa in — xếp lại hàng đợi")
                .SetProperty(j => j.UpdatedAt, now), ct);
        if (softRequeued > 0)
            logger.LogWarning(
                "Requeued {Count} stuck kitchen/label job(s) in store {StoreId}",
                softRequeued, storeId);

        // Job đã Claimed/Printing quá lâu: Agent gần như đã in giấy rồi nhưng
        // không /complete. Reclaim → Queued gây in chồng (hóa đơn / kho).
        // Tem/bếp Claimed đã soft-requeue ở trên. Hủy các loại còn lại + Printing.
        var claimedBefore = now.Subtract(StuckClaimReclaimAfter);
        var printingBefore = now.Subtract(StuckPrintingReclaimAfter);
        var stuckCancelled = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && (j.Status == PosPrintJobStatus.Claimed
                    || j.Status == PosPrintJobStatus.Printing)
                // Bếp/tem Claimed được nhường cho nhánh soft-requeue ở trên, nhưng
                // chỉ trong 180s. Quá mốc đó mà Agent còn giữ job nghĩa là nó treo:
                // hủy để máy gửi thấy lỗi và in lại, thay vì Claimed vĩnh viễn.
                && !(j.Status == PosPrintJobStatus.Claimed
                     && softRequeueTypes.Contains(j.DocumentType)
                     && j.ClaimedAt >= printingBefore)
                && j.ClaimedAt != null
                && ((j.Status == PosPrintJobStatus.Claimed && j.ClaimedAt < claimedBefore)
                    || (j.Status == PosPrintJobStatus.Printing && j.ClaimedAt < printingBefore)))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(j => j.Status, PosPrintJobStatus.Cancelled)
                .SetProperty(j => j.ErrorCode, "STUCK_NO_REQUEUE")
                .SetProperty(j => j.ErrorMessage,
                    "Agent nhận job nhưng không complete — hủy để tránh in trùng")
                .SetProperty(j => j.CompletedAt, now)
                .SetProperty(j => j.UpdatedAt, now), ct);
        if (stuckCancelled > 0)
            logger.LogWarning(
                "Cancelled {Count} stuck print job(s) (no requeue) in store {StoreId}",
                stuckCancelled, storeId);

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

        // Claim set Busy nhưng STUCK/MAX_ATTEMPTS không clear → máy in «treo» trên UI
        // và hàng đợi trông như chết dù Agent vẫn poll.
        await ClearOrphanBusyPrintersAsync(storeId, now, ct);
    }

    async Task ClearOrphanBusyPrintersAsync(Guid storeId, DateTime now, CancellationToken ct)
    {
        var busyIds = await db.PosStorePrinters
            .Where(p => p.StoreId == storeId && p.Deleted == null
                && p.HealthStatus == PosPrinterHealthStatus.Busy)
            .Select(p => p.Id)
            .ToListAsync(ct);
        if (busyIds.Count == 0) return;

        var activePrinterIds = await db.PosPrintJobs
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && (j.Status == PosPrintJobStatus.Claimed
                    || j.Status == PosPrintJobStatus.Printing)
                && busyIds.Contains(j.PrinterId))
            .Select(j => j.PrinterId)
            .Distinct()
            .ToListAsync(ct);

        var orphanIds = busyIds.Except(activePrinterIds).ToList();
        if (orphanIds.Count == 0) return;

        var cleared = await db.PosStorePrinters
            .Where(p => orphanIds.Contains(p.Id))
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.HealthStatus, PosPrinterHealthStatus.Online)
                .SetProperty(p => p.LastErrorMessage, (string?)null)
                .SetProperty(p => p.UpdatedAt, now), ct);
        if (cleared > 0)
            logger.LogWarning(
                "Cleared Busy on {Count} orphan printer(s) in store {StoreId}",
                cleared, storeId);
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
