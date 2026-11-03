using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Một lần: gửi lệnh in qua Print Agent từ máy nhân viên nay cần gói có «Máy in cloud»
/// (<see cref="PosPackageDefaults.PrintAgentModule"/>). Cửa hàng đã dùng Agent mà gói chưa tick (gói cơ bản
/// trước đây suy từ PosPrinters) → thêm vào chức năng riêng của cửa hàng, để không ai mất in sau khi cập nhật.
/// Cửa hàng bị chặn riêng chức năng này thì giữ nguyên.
/// </summary>
public static class PrintAgentPackageBackfill
{
    const string MigrationId = "print-agent-package-v1";

    public static async Task RunAsync(ZKTecoDbContext db, ILogger logger, CancellationToken ct = default)
    {
        await db.Database.ExecuteSqlRawAsync(
            @"CREATE TABLE IF NOT EXISTS ""SboxDataMigrations"" (""Id"" character varying(100) NOT NULL PRIMARY KEY, ""AppliedAt"" timestamp with time zone NOT NULL DEFAULT now());", ct);
        var done = await db.Database.SqlQueryRaw<int>(
                @"SELECT COUNT(*)::int AS ""Value"" FROM ""SboxDataMigrations"" WHERE ""Id"" = {0}", MigrationId)
            .FirstAsync(ct);
        if (done > 0) return;

        var granted = await ApplyAsync(db, ct);
        await db.Database.ExecuteSqlRawAsync(
            @"INSERT INTO ""SboxDataMigrations"" (""Id"") VALUES ({0}) ON CONFLICT DO NOTHING", [MigrationId], ct);
        logger.LogInformation("Print Agent package backfill: thêm «Máy in cloud» cho {Count} cửa hàng đang dùng Agent", granted);
    }

    /// <summary>Phần chuyển dữ liệu (không kèm cờ đã chạy) — trả số cửa hàng được thêm chức năng.</summary>
    public static async Task<int> ApplyAsync(ZKTecoDbContext db, CancellationToken ct = default)
    {
        var module = PosPackageDefaults.PrintAgentModule;
        var storeIds = await db.PosPrintAgents.IgnoreQueryFilters().AsNoTracking()
            .Where(a => a.Deleted == null)
            .Select(a => a.StoreId)
            .Distinct()
            .ToListAsync(ct);
        var granted = 0;
        foreach (var storeId in storeIds)
        {
            var store = await db.Stores.IgnoreQueryFilters().AsNoTracking()
                .Select(s => new { s.Id, s.ExtraModules, s.BlockedModules })
                .FirstOrDefaultAsync(s => s.Id == storeId, ct);
            if (store == null) continue;
            if (StorePackageHelper.DeserializeModules(store.BlockedModules)
                .Contains(module, StringComparer.OrdinalIgnoreCase)) continue;

            var extra = StorePackageHelper.DeserializeModules(store.ExtraModules);
            if (extra.Contains(module, StringComparer.OrdinalIgnoreCase)) continue;
            // Không có gói (chỉ chức năng tự phục vụ) thì chức năng riêng không áp dụng — Bán hàng cũng không có.
            var allowed = await StorePackageHelper.ResolveAllowedModulesAsync(db, storeId, ct);
            if (PosPackageDefaults.AllowsStaffCloudPrint(allowed) ||
                !allowed.Contains("PosSell", StringComparer.OrdinalIgnoreCase)) continue;

            extra.Add(module);
            var json = JsonSerializer.Serialize(extra);
            // ExecuteUpdate: DbContext NoTracking toàn cục — gán + SaveChanges không ghi.
            await db.Stores.IgnoreQueryFilters()
                .Where(s => s.Id == storeId)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.ExtraModules, json), ct);
            granted++;
        }
        return granted;
    }
}
