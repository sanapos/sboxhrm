using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

public class MarketingService : IMarketingService
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ZKTecoDbContext _db;
    private readonly IAnnouncementService _announcement;
    private readonly ILogger<MarketingService> _logger;

    public MarketingService(ZKTecoDbContext db, IAnnouncementService announcement, ILogger<MarketingService> logger)
    {
        _db = db; _announcement = announcement; _logger = logger;
    }

    // ---------- Templates ----------

    public async Task<List<NotificationTemplateDto>> ListTemplatesAsync(bool? activeOnly, CancellationToken ct = default)
    {
        var q = _db.NotificationTemplates.AsNoTracking().AsQueryable();
        if (activeOnly == true) q = q.Where(x => x.IsActive);
        var rows = await q.OrderBy(x => x.Code).Take(500).ToListAsync(ct);
        return rows.Select(MapTemplate).ToList();
    }

    public async Task<NotificationTemplateDto> CreateTemplateAsync(CreateNotificationTemplateDto dto, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(dto.Code)) throw new ArgumentException("Code không được trống");
        var exists = await _db.NotificationTemplates.AnyAsync(x => x.Code == dto.Code, ct);
        if (exists) throw new InvalidOperationException($"Template Code '{dto.Code}' đã tồn tại");

        var entity = new NotificationTemplate
        {
            Id = Guid.NewGuid(),
            Code = dto.Code.Trim(),
            Title = dto.Title,
            Body = dto.Body,
            Channels = dto.Channels,
            Locale = dto.Locale,
            IsActive = dto.IsActive,
            VariablesJson = dto.Variables is { Count: > 0 } ? JsonSerializer.Serialize(dto.Variables) : null,
            CreatedAt = DateTime.UtcNow
        };
        _db.NotificationTemplates.Add(entity);
        await _db.SaveChangesAsync(ct);
        return MapTemplate(entity);
    }

    public async Task<bool> UpdateTemplateAsync(Guid id, CreateNotificationTemplateDto dto, CancellationToken ct = default)
    {
        var ent = await _db.NotificationTemplates.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null) return false;
        ent.Title = dto.Title;
        ent.Body = dto.Body;
        ent.Channels = dto.Channels;
        ent.Locale = dto.Locale;
        ent.IsActive = dto.IsActive;
        ent.VariablesJson = dto.Variables is { Count: > 0 } ? JsonSerializer.Serialize(dto.Variables) : null;
        ent.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteTemplateAsync(Guid id, CancellationToken ct = default)
        => (await _db.NotificationTemplates.Where(x => x.Id == id).ExecuteDeleteAsync(ct)) > 0;

    // ---------- Campaigns ----------

    public async Task<List<MarketingCampaignDto>> ListCampaignsAsync(int page, int pageSize, CancellationToken ct = default)
    {
        var rows = await _db.MarketingCampaigns.AsNoTracking()
            .OrderByDescending(x => x.CreatedAt)
            .Skip(Math.Max(0, page - 1) * pageSize)
            .Take(Math.Max(1, Math.Min(pageSize, 200)))
            .ToListAsync(ct);
        return rows.Select(MapCampaign).ToList();
    }

    public async Task<MarketingCampaignDto?> GetCampaignAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.MarketingCampaigns.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return ent == null ? null : MapCampaign(ent);
    }

    public async Task<MarketingCampaignDto> CreateCampaignAsync(CreateMarketingCampaignDto dto, Guid actorUserId, CancellationToken ct = default)
    {
        var entity = new MarketingCampaign
        {
            Id = Guid.NewGuid(),
            Name = dto.Name,
            Description = dto.Description,
            TemplateId = dto.TemplateId,
            AudienceJson = JsonSerializer.Serialize(dto.Audience ?? new AudienceSpec { AllUsers = true }, Json),
            Channels = dto.Channels == 0 ? NotificationChannel.InApp | NotificationChannel.Banner : dto.Channels,
            ScheduleAt = dto.ScheduleAt,
            CreatedByUserId = actorUserId,
            CreatedAt = DateTime.UtcNow,
            Status = dto.LaunchNow ? CampaignStatus.Running : (dto.ScheduleAt.HasValue ? CampaignStatus.Scheduled : CampaignStatus.Draft)
        };
        _db.MarketingCampaigns.Add(entity);
        await _db.SaveChangesAsync(ct);

        if (dto.LaunchNow)
        {
            await LaunchInternal(entity, dto, actorUserId, ct);
        }
        return MapCampaign(entity);
    }

    public async Task<bool> LaunchCampaignAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.MarketingCampaigns.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null || ent.Status == CampaignStatus.Completed) return false;
        await LaunchInternal(ent, null, ent.CreatedByUserId, ct);
        return true;
    }

    public async Task<bool> CancelCampaignAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.MarketingCampaigns.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null) return false;
        ent.Status = CampaignStatus.Cancelled;
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteCampaignAsync(Guid id, CancellationToken ct = default)
        => (await _db.MarketingCampaigns.Where(x => x.Id == id).ExecuteDeleteAsync(ct)) > 0;

    // ---------- Internals ----------

    private async Task LaunchInternal(MarketingCampaign campaign, CreateMarketingCampaignDto? createDto, Guid actorUserId, CancellationToken ct)
    {
        try
        {
            string title;
            string body;

            if (campaign.TemplateId.HasValue)
            {
                var tpl = await _db.NotificationTemplates.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.Id == campaign.TemplateId.Value, ct);
                if (tpl == null) throw new InvalidOperationException("Template không tồn tại");
                title = ApplyMerge(createDto?.CustomTitle ?? tpl.Title, createDto?.Variables);
                body = ApplyMerge(createDto?.CustomBody ?? tpl.Body, createDto?.Variables);
            }
            else
            {
                title = ApplyMerge(createDto?.CustomTitle ?? campaign.Name, createDto?.Variables);
                body = ApplyMerge(createDto?.CustomBody ?? campaign.Description ?? string.Empty, createDto?.Variables);
            }

            var audience = string.IsNullOrEmpty(campaign.AudienceJson)
                ? new AudienceSpec { AllUsers = true }
                : JsonSerializer.Deserialize<AudienceSpec>(campaign.AudienceJson, Json) ?? new AudienceSpec { AllUsers = true };

            var ann = await _announcement.CreateAsync(new CreateSystemAnnouncementDto
            {
                Title = title,
                Content = body,
                Kind = AnnouncementKind.Marketing,
                Severity = AnnouncementSeverity.Info,
                Channels = campaign.Channels,
                Audience = audience,
                ScheduleAt = campaign.ScheduleAt,
                ExpiresAt = null,
                RequireAck = false,
                AllowDismiss = true,
                SendNow = !campaign.ScheduleAt.HasValue
            }, actorUserId, ct);

            campaign.AnnouncementId = ann.Id;
            campaign.RecipientCount = ann.RecipientCount;
            campaign.DeliveredCount = ann.DeliveredCount;
            campaign.LaunchedAt = DateTime.UtcNow;
            campaign.Status = campaign.ScheduleAt.HasValue && campaign.ScheduleAt > DateTime.UtcNow
                ? CampaignStatus.Scheduled
                : CampaignStatus.Completed;
            await _db.SaveChangesAsync(ct);
            _logger.LogInformation("Launched campaign {Id} → announcement {Ann}", campaign.Id, ann.Id);
        }
        catch (Exception ex)
        {
            campaign.Status = CampaignStatus.Failed;
            await _db.SaveChangesAsync(ct);
            _logger.LogError(ex, "Failed to launch campaign {Id}", campaign.Id);
            throw;
        }
    }

    private static readonly Regex MergeRegex = new(@"\{(\w+)\}", RegexOptions.Compiled);
    private static string ApplyMerge(string template, IDictionary<string, string>? vars)
    {
        if (string.IsNullOrEmpty(template) || vars is null || vars.Count == 0) return template;
        return MergeRegex.Replace(template, m =>
            vars.TryGetValue(m.Groups[1].Value, out var v) ? v : m.Value);
    }

    private static NotificationTemplateDto MapTemplate(NotificationTemplate e) => new()
    {
        Id = e.Id,
        Code = e.Code,
        Title = e.Title,
        Body = e.Body,
        Channels = e.Channels,
        Locale = e.Locale,
        IsActive = e.IsActive,
        Variables = ParseList(e.VariablesJson),
        CreatedAt = e.CreatedAt
    };

    private static MarketingCampaignDto MapCampaign(MarketingCampaign e) => new()
    {
        Id = e.Id,
        Name = e.Name,
        Description = e.Description,
        TemplateId = e.TemplateId,
        Channels = e.Channels,
        ScheduleAt = e.ScheduleAt,
        Status = e.Status,
        AnnouncementId = e.AnnouncementId,
        RecipientCount = e.RecipientCount,
        DeliveredCount = e.DeliveredCount,
        OpenedCount = e.OpenedCount,
        ClickedCount = e.ClickedCount,
        LaunchedAt = e.LaunchedAt,
        CreatedAt = e.CreatedAt
    };

    private static List<string>? ParseList(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<List<string>>(json); } catch { return null; }
    }
}
