using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Communications;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Cấu hình AI (Gemini) dùng chung toàn hệ thống — AppSettings StoreId = null.
/// Cửa hàng không nhập key riêng sẽ dùng cấu hình này (quét menu, phân tích mẫu Word...).
/// </summary>
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/ai-config")]
public class SystemAiConfigController(
    ZKTecoDbContext db,
    IConfiguration configuration,
    ILogger<GeminiAiService> geminiLogger) : AuthenticatedControllerBase
{
    private static readonly string[] Keys =
        ["gemini_api_key", "gemini_model", "gemini_max_tokens", "gemini_temperature", "gemini_enabled"];

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> Get(CancellationToken ct)
    {
        var cfg = await GeminiStoreConfigLoader.LoadPlatformAsync(db, ct);
        return Ok(AppResponse<object>.Success(new
        {
            apiKey = Mask(cfg?.ApiKey),
            apiKeys = (cfg?.ApiKeys ?? []).Select(GeminiKeyPool.Mask).ToList(),
            keyCount = cfg?.ApiKeys.Count ?? 0,
            model = cfg?.Model ?? "gemini-2.5-flash",
            maxOutputTokens = cfg?.MaxOutputTokens ?? 8192,
            temperature = cfg?.Temperature ?? 0.7,
            enabled = cfg?.Enabled ?? false,
            isConfigured = cfg?.IsConfigured ?? false,
        }));
    }

    /// <summary>ApiKey để trống / null = giữ key cũ.</summary>
    [HttpPut]
    public async Task<ActionResult<AppResponse<object>>> Save([FromBody] UpdateGeminiConfigDto dto, CancellationToken ct)
    {
        var values = new Dictionary<string, string?>
        {
            ["gemini_api_key"] = null, // gộp nhiều khóa bên dưới (thêm / thay / xóa)
            ["gemini_model"] = string.IsNullOrWhiteSpace(dto.Model) ? null : dto.Model.Trim(),
            ["gemini_max_tokens"] = dto.MaxOutputTokens?.ToString(),
            ["gemini_temperature"] = dto.Temperature?.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["gemini_enabled"] = dto.Enabled?.ToString(),
        };

        var existing = await db.AppSettings.IgnoreQueryFilters().AsTracking()
            .Where(s => s.StoreId == null && s.Deleted == null && Keys.Contains(s.Key))
            .ToListAsync(ct);
        values["gemini_api_key"] = GeminiKeyPool.Merge(
            existing.FirstOrDefault(s => s.Key == "gemini_api_key")?.Value,
            dto.ApiKey, dto.AppendApiKey == true, dto.RemoveApiKeys);
        var now = DateTime.UtcNow;
        foreach (var (key, value) in values)
        {
            if (value == null) continue;
            var row = existing.FirstOrDefault(s => s.Key == key);
            if (row != null)
            {
                row.Value = value;
                row.LastModified = now;
                row.LastModifiedBy = CurrentUserEmail;
                continue;
            }
            db.AppSettings.Add(new AppSettings
            {
                Id = Guid.NewGuid(),
                Key = key,
                Value = value,
                Description = "AI dùng chung toàn hệ thống",
                Group = "AI",
                DataType = "text",
                IsPublic = false,
                IsActive = true,
                StoreId = null,
                CreatedAt = now,
                CreatedBy = CurrentUserEmail,
            });
        }
        await db.SaveChangesAsync(ct);
        return await Get(ct);
    }

    /// <summary>Gọi thử Gemini bằng cấu hình chung đã lưu.</summary>
    [HttpPost("test")]
    public async Task<ActionResult<AppResponse<object>>> Test(CancellationToken ct)
    {
        var cfg = await GeminiStoreConfigLoader.LoadPlatformAsync(db, ct);
        if (cfg == null || !cfg.IsConfigured)
            return BadRequest(AppResponse<object>.Fail("Chưa nhập API key."));

        // Kiểm tra từng khóa — khóa hết lượt / sai được đánh dấu để yêu cầu thật bỏ qua.
        var results = await GeminiKeyTester.TestAllAsync(cfg, configuration, geminiLogger, ct);
        var ok = results.Any(r => r.Status == "ok");
        var summary = GeminiKeyTester.Summary(results);
        return Ok(ok
            ? AppResponse<object>.Success(new { ok, model = cfg.Model, message = summary, detail = GeminiKeyTester.Detail(results), keys = results })
            : AppResponse<object>.Fail($"{summary} {GeminiKeyTester.Detail(results)}"));
    }

    private static string Mask(string? key)
    {
        if (string.IsNullOrWhiteSpace(key)) return "";
        return key.Length <= 8 ? "****" : key[..4] + new string('*', key.Length - 8) + key[^4..];
    }
}
