using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public interface IPosPlatformTingeeSettingService
{
    Task<PlatformTingeeSettingDto> GetSettingsAsync(CancellationToken ct = default);
    Task<PlatformTingeeSettingDto> UpsertSettingsAsync(
        PlatformTingeeSettingUpsertRequest req, string? actor, CancellationToken ct = default);
    Task<string?> ResolveWebhookSecretAsync(CancellationToken ct = default);
    string ResolveApiBaseUrl(PlatformTingeeSettingDto? settings = null);
}

public sealed record PlatformTingeeSettingUpsertRequest(
    bool? TingeeEnabled,
    string? TingeeClientId,
    string? TingeeSecretKey,
    string? TingeeWebhookSecret,
    string? ApiEnvironment,
    string? ApiBaseUrlOverride,
    string? DefaultVaAccountNumber);

public sealed class PosPlatformTingeeSettingService(
    ZKTecoDbContext db,
    IConfiguration configuration) : IPosPlatformTingeeSettingService
{
    static readonly Guid SingletonId = Guid.Parse("00000000-0000-0000-0000-000000000002");

    public async Task<PlatformTingeeSettingDto> GetSettingsAsync(CancellationToken ct = default)
    {
        var row = await GetOrCreateAsync(ct);
        return Map(row);
    }

    public async Task<PlatformTingeeSettingDto> UpsertSettingsAsync(
        PlatformTingeeSettingUpsertRequest req, string? actor, CancellationToken ct = default)
    {
        var row = await GetOrCreateAsync(ct);
        if (req.TingeeEnabled.HasValue) row.TingeeEnabled = req.TingeeEnabled.Value;
        if (req.TingeeClientId != null) row.TingeeClientId = req.TingeeClientId.Trim();
        if (!string.IsNullOrWhiteSpace(req.TingeeSecretKey))
            row.TingeeSecretKey = req.TingeeSecretKey.Trim();
        if (!string.IsNullOrWhiteSpace(req.TingeeWebhookSecret))
            row.TingeeWebhookSecret = req.TingeeWebhookSecret.Trim();
        if (!string.IsNullOrWhiteSpace(req.ApiEnvironment))
            row.ApiEnvironment = req.ApiEnvironment.Trim();
        if (req.ApiBaseUrlOverride != null)
            row.ApiBaseUrlOverride = string.IsNullOrWhiteSpace(req.ApiBaseUrlOverride)
                ? null
                : req.ApiBaseUrlOverride.Trim();
        if (req.DefaultVaAccountNumber != null)
            row.DefaultVaAccountNumber = req.DefaultVaAccountNumber.Trim();
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        return Map(row);
    }

    public async Task<string?> ResolveWebhookSecretAsync(CancellationToken ct = default)
    {
        var row = await db.PosPlatformTingeeSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == SingletonId && x.Deleted == null, ct);
        if (row == null) return null;
        var secret = row.TingeeWebhookSecret ?? row.TingeeSecretKey;
        return string.IsNullOrWhiteSpace(secret) ? null : secret;
    }

    public string ResolveApiBaseUrl(PlatformTingeeSettingDto? settings = null)
    {
        if (!string.IsNullOrWhiteSpace(settings?.ApiBaseUrlOverride))
            return settings.ApiBaseUrlOverride!.TrimEnd('/');

        var env = (settings?.ApiEnvironment ?? "Production").Trim();
        if (env.Equals("UAT", StringComparison.OrdinalIgnoreCase)
            || env.Equals("Sandbox", StringComparison.OrdinalIgnoreCase))
        {
            return configuration["Tingee:UatApiBaseUrl"]?.TrimEnd('/')
                ?? "https://uat-open-api.tingee.vn/v1";
        }

        return configuration["Tingee:ProductionApiBaseUrl"]?.TrimEnd('/')
            ?? "https://open-api.tingee.vn/v1";
    }

    async Task<PosPlatformTingeeSetting> GetOrCreateAsync(CancellationToken ct)
    {
        var row = await db.PosPlatformTingeeSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == SingletonId && x.Deleted == null, ct);
        if (row != null) return row;

        row = new PosPlatformTingeeSetting
        {
            Id = SingletonId,
            ApiEnvironment = "Production",
            IsActive = true,
            CreatedBy = "system",
        };
        db.PosPlatformTingeeSettings.Add(row);

        // Bootstrap từ credentials legacy per-store (migration mềm).
        var legacy = await db.PosPaymentGatewaySettings.AsNoTracking()
            .Where(x => x.TingeeEnabled && x.Deleted == null && x.TingeeClientId != null)
            .OrderByDescending(x => x.UpdatedAt ?? x.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (legacy != null)
        {
            row.TingeeEnabled = true;
            row.TingeeClientId = legacy.TingeeClientId;
            row.TingeeSecretKey = legacy.TingeeSecretKey;
            row.TingeeWebhookSecret = legacy.TingeeWebhookSecret ?? legacy.TingeeSecretKey;
            row.DefaultVaAccountNumber = legacy.TingeeVaAccountNumber;
        }

        await db.SaveChangesAsync(ct);
        return row;
    }

    static PlatformTingeeSettingDto Map(PosPlatformTingeeSetting s) => new(
        s.TingeeEnabled,
        s.TingeeClientId,
        !string.IsNullOrWhiteSpace(s.TingeeSecretKey),
        !string.IsNullOrWhiteSpace(s.TingeeWebhookSecret),
        s.ApiEnvironment,
        s.ApiBaseUrlOverride,
        s.DefaultVaAccountNumber,
        "https://sboxhrm.com/api/webhooks/payment/tingee");
}
