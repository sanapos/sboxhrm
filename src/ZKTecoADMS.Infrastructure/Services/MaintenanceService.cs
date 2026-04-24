using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

public class MaintenanceService : IMaintenanceService
{
    private readonly ZKTecoDbContext _db;
    private readonly ILogger<MaintenanceService> _logger;

    public MaintenanceService(ZKTecoDbContext db, ILogger<MaintenanceService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<List<MaintenanceWindowDto>> ListAsync(bool? activeOnly, CancellationToken ct = default)
    {
        var q = _db.MaintenanceWindows.AsNoTracking().AsQueryable();
        if (activeOnly == true) q = q.Where(x => x.IsActive);
        var rows = await q.OrderByDescending(x => x.StartAt).Take(200).ToListAsync(ct);
        return rows.Select(Map).ToList();
    }

    public async Task<MaintenanceWindowDto> CreateAsync(CreateMaintenanceWindowDto dto, Guid userId, CancellationToken ct = default)
    {
        if (dto.EndAt <= dto.StartAt)
            throw new ArgumentException("EndAt phải lớn hơn StartAt");

        var entity = new MaintenanceWindow
        {
            Id = Guid.NewGuid(),
            Title = dto.Title,
            Message = dto.Message,
            StartAt = dto.StartAt,
            EndAt = dto.EndAt,
            AffectedModulesJson = dto.AffectedModules is { Count: > 0 }
                ? JsonSerializer.Serialize(dto.AffectedModules)
                : null,
            IsActive = dto.IsActive,
            BlockAccess = dto.BlockAccess,
            NotifyBeforeMinutesCsv = dto.NotifyBeforeMinutes is { Count: > 0 }
                ? string.Join(',', dto.NotifyBeforeMinutes.Where(x => x > 0).Distinct().OrderByDescending(x => x))
                : "60,15,5",
            CreatedByUserId = userId,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = userId.ToString()
        };
        _db.MaintenanceWindows.Add(entity);
        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("Created MaintenanceWindow {Id} by {User} window {Start}-{End}", entity.Id, userId, entity.StartAt, entity.EndAt);
        return Map(entity);
    }

    public async Task<bool> SetActiveAsync(Guid id, bool active, CancellationToken ct = default)
    {
        var n = await _db.MaintenanceWindows.Where(x => x.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.IsActive, active)
                                       .SetProperty(x => x.UpdatedAt, DateTime.UtcNow), ct);
        return n > 0;
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var n = await _db.MaintenanceWindows.Where(x => x.Id == id).ExecuteDeleteAsync(ct);
        return n > 0;
    }

    public async Task<ActiveMaintenanceDto> GetActiveAsync(CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var w = await _db.MaintenanceWindows.AsNoTracking()
            .Where(x => x.IsActive && x.StartAt <= now && x.EndAt > now)
            .OrderBy(x => x.StartAt)
            .FirstOrDefaultAsync(ct);
        if (w == null) return new ActiveMaintenanceDto { InMaintenance = false };
        return new ActiveMaintenanceDto
        {
            InMaintenance = true,
            Id = w.Id,
            Title = w.Title,
            Message = w.Message,
            StartAt = w.StartAt,
            EndAt = w.EndAt,
            BlockAccess = w.BlockAccess,
            AffectedModules = ParseModules(w.AffectedModulesJson)
        };
    }

    private static MaintenanceWindowDto Map(MaintenanceWindow e) => new()
    {
        Id = e.Id,
        Title = e.Title,
        Message = e.Message,
        StartAt = e.StartAt,
        EndAt = e.EndAt,
        AffectedModules = ParseModules(e.AffectedModulesJson),
        IsActive = e.IsActive,
        BlockAccess = e.BlockAccess,
        NotifyBeforeMinutes = ParseCsvInts(e.NotifyBeforeMinutesCsv),
        StartNotified = e.StartNotified,
        EndNotified = e.EndNotified,
        CreatedAt = e.CreatedAt
    };

    private static List<string>? ParseModules(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<List<string>>(json); }
        catch { return null; }
    }

    private static List<int>? ParseCsvInts(string? csv)
    {
        if (string.IsNullOrWhiteSpace(csv)) return null;
        var list = new List<int>();
        foreach (var p in csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            if (int.TryParse(p, out var v)) list.Add(v);
        return list;
    }
}
