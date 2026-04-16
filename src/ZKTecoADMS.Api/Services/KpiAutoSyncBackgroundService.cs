using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Background service that automatically syncs KPI actuals from Google Sheet
/// based on configured time slots in each KPI period.
/// </summary>
public class KpiAutoSyncBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<KpiAutoSyncBackgroundService> _logger;

    // Check every 60 seconds — time slots are at minute precision
    private readonly TimeSpan _checkInterval = TimeSpan.FromSeconds(60);

    // Track which (periodId, timeSlot) was already synced to avoid duplicate runs
    private readonly HashSet<string> _syncedSlots = new();
    private string _lastDateKey = "";

    public KpiAutoSyncBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<KpiAutoSyncBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("⏰ KPI Auto-Sync Background Service started");

        // Wait for app to fully initialize
        await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Reset synced slots each new day
                var today = DateTime.Now.ToString("yyyy-MM-dd");
                if (today != _lastDateKey)
                {
                    _syncedSlots.Clear();
                    _lastDateKey = today;
                }

                await CheckAndSyncAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in KPI auto-sync check");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }

        _logger.LogInformation("⏰ KPI Auto-Sync Background Service stopped");
    }

    private async Task CheckAndSyncAsync(CancellationToken ct)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        // Find all periods with auto-sync enabled (no-tracking for read-only check)
        var periods = await dbContext.KpiPeriods
            .Where(p => p.AutoSyncEnabled
                        && p.GoogleSpreadsheetId != null
                        && p.AutoSyncTimeSlots != null
                        && p.Deleted == null)
            .Select(p => new { p.Id, p.Name, p.AutoSyncTimeSlots })
            .ToListAsync(ct);

        if (periods.Count == 0) return;

        var now = DateTime.Now;
        var currentTime = now.ToString("HH:mm");

        foreach (var period in periods)
        {
            var slots = ParseTimeSlots(period.AutoSyncTimeSlots);
            if (slots.Count == 0) continue;

            foreach (var slot in slots)
            {
                var slotKey = $"{period.Id}_{slot}_{_lastDateKey}";

                // Already synced this slot today
                if (_syncedSlots.Contains(slotKey)) continue;

                // Check if current time matches the slot (within 1-minute window)
                if (!IsTimeMatch(currentTime, slot)) continue;

                _logger.LogInformation("⏰ Auto-sync triggered for period '{Period}' at slot {Slot}",
                    period.Name, slot);

                _syncedSlots.Add(slotKey);

                try
                {
                    await SyncPeriodAsync(dbContext, scope.ServiceProvider, period.Id, ct);
                    _logger.LogInformation("✅ Auto-sync completed for period '{Period}' - slot {Slot}",
                        period.Name, slot);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "❌ Auto-sync failed for period '{Period}' at slot {Slot}",
                        period.Name, slot);
                }
            }
        }
    }

    private async Task SyncPeriodAsync(ZKTecoDbContext dbContext, IServiceProvider sp,
        Guid periodId, CancellationToken ct)
    {
        var kpiSheetService = sp.GetRequiredService<IKpiGoogleSheetService>();

        var period = await dbContext.KpiPeriods.FindAsync(new object[] { periodId }, ct);
        if (period == null) return;

        var allTargets = await dbContext.KpiEmployeeTargets
            .AsTracking()
            .Include(t => t.Employee)
            .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
            .ToListAsync(ct);

        if (allTargets.Count == 0) return;

        int updatedCount = 0;
        var sheetName = period.GoogleSheetName ?? "Nhân viên";

        // ── Mode 1: Code-based lookup ──
        try
        {
            var rows = await kpiSheetService.ReadKpiDataAsync(period.GoogleSpreadsheetId!, sheetName);
            if (rows.Count == 0)
            {
                _logger.LogWarning("[AUTO-SYNC] Sheet is empty for period {Period}", period.Name);
                return;
            }

            // Determine KPI column
            string kpiColLetter = "C";
            if (rows.Count > 0)
            {
                var firstRow = rows[0];
                int colOffset = 0;
                foreach (var key in firstRow.KpiValues.Keys)
                {
                    if (key.Contains("Tổng KPI", StringComparison.OrdinalIgnoreCase)
                        || key.Contains("KPI", StringComparison.OrdinalIgnoreCase))
                    {
                        kpiColLetter = GetColumnLetter(2 + colOffset);
                        break;
                    }
                    colOffset++;
                }
            }

            var sheetUrl = $"https://docs.google.com/spreadsheets/d/{period.GoogleSpreadsheetId}";

            foreach (var row in rows)
            {
                var sheetCode = row.EmployeeCode.Trim();
                var target = allTargets.FirstOrDefault(t =>
                    t.Employee != null &&
                    NormalizeEmployeeCode(t.Employee.EmployeeCode ?? "")
                        .Equals(NormalizeEmployeeCode(sheetCode), StringComparison.OrdinalIgnoreCase));

                if (target == null) continue;

                // Auto-map cell position
                target.GoogleCellPosition = $"{kpiColLetter}{row.RowIndex}";
                target.GoogleSheetUrl = sheetUrl;
                target.GoogleSheetName = sheetName;

                // Read KPI value
                decimal? kpiValue = null;
                foreach (var key in row.KpiValues.Keys)
                {
                    if (key.Contains("Tổng KPI", StringComparison.OrdinalIgnoreCase)
                        || key.Contains("TongKPI", StringComparison.OrdinalIgnoreCase)
                        || key.Contains("Total KPI", StringComparison.OrdinalIgnoreCase)
                        || key.Contains("KPI", StringComparison.OrdinalIgnoreCase))
                    {
                        kpiValue = row.KpiValues[key];
                        break;
                    }
                }
                kpiValue ??= row.KpiValues.Values.FirstOrDefault();

                if (kpiValue.HasValue)
                {
                    target.ActualValue = kpiValue.Value;
                    target.CompletionRate = target.TargetValue > 0
                        ? Math.Round(kpiValue.Value / target.TargetValue * 100m, 2)
                        : 0m;
                }
                target.LastModified = DateTime.UtcNow;
                target.LastModifiedBy = "auto-sync";
                updatedCount++;
            }

            if (updatedCount > 0)
            {
                period.LastSyncedAt = DateTime.UtcNow;
                await dbContext.SaveChangesAsync(ct);
                _logger.LogInformation("[AUTO-SYNC] Updated {Count}/{Total} targets for period '{Period}'",
                    updatedCount, allTargets.Count, period.Name);
                return;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[AUTO-SYNC] Code-based sync failed for period '{Period}', trying cell-based",
                period.Name);
        }

        // ── Mode 2: Cell-position fallback ──
        var cellTargets = allTargets
            .Where(t => t.GoogleSheetUrl != null && t.GoogleCellPosition != null)
            .ToList();

        foreach (var target in cellTargets)
        {
            try
            {
                var spreadsheetId = ExtractSpreadsheetId(target.GoogleSheetUrl!);
                if (string.IsNullOrEmpty(spreadsheetId)) continue;

                var targetSheetName = target.GoogleSheetName ?? "Sheet1";
                var range = $"{targetSheetName}!{target.GoogleCellPosition}";
                var val = await kpiSheetService.ReadCellValueAsync(spreadsheetId, range);

                if (val.HasValue && val.Value > 0)
                {
                    target.ActualValue = val.Value;
                    target.CompletionRate = target.TargetValue > 0
                        ? Math.Round(val.Value / target.TargetValue * 100m, 2)
                        : 0m;
                    target.LastModified = DateTime.UtcNow;
                    target.LastModifiedBy = "auto-sync";
                    updatedCount++;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[AUTO-SYNC] Cell read failed for target {TargetId}", target.Id);
            }
        }

        if (updatedCount > 0)
        {
            period.LastSyncedAt = DateTime.UtcNow;
            await dbContext.SaveChangesAsync(ct);
            _logger.LogInformation("[AUTO-SYNC] Cell-based: updated {Count} targets for period '{Period}'",
                updatedCount, period.Name);
        }
    }

    // ── Helpers ──

    private static List<string> ParseTimeSlots(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<string>();
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    /// <summary>
    /// Check if current time matches a slot within a 1-minute window.
    /// E.g., slot "22:00" matches currentTime "22:00" or "22:01" (but not "22:02").
    /// </summary>
    private static bool IsTimeMatch(string currentTime, string slot)
    {
        if (!TimeSpan.TryParse(currentTime, out var now)) return false;
        if (!TimeSpan.TryParse(slot, out var target)) return false;
        var diff = (now - target).TotalMinutes;
        return diff >= 0 && diff < 1.5; // within 90 seconds after the slot
    }

    private static string GetColumnLetter(int colIndex)
    {
        var result = "";
        while (colIndex >= 0)
        {
            result = (char)('A' + colIndex % 26) + result;
            colIndex = colIndex / 26 - 1;
        }
        return result;
    }

    private static string NormalizeEmployeeCode(string code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "";
        if (double.TryParse(code, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var num))
            return ((long)num).ToString();
        return code.Trim();
    }

    private static string? ExtractSpreadsheetId(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        if (!url.Contains('/')) return url;
        var match = Regex.Match(url, @"/d/([a-zA-Z0-9_-]+)");
        return match.Success ? match.Groups[1].Value : null;
    }
}
