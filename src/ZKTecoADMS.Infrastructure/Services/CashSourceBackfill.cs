using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Một lần: phiếu thu / chi cũ chỉ có chuỗi liên kết trong ghi chú → ghi SourceType/SourceId, nhân viên, chi nhánh
/// của chứng từ gốc. Phiếu bán hàng lấy chi nhánh của chứng từ (sửa cả phiếu đơn online / webhook trước bị tính về
/// trụ sở); phiếu nhân sự chỉ điền khi chưa có chi nhánh (giữ số quỹ chi nhánh đã chốt). Phiếu không có liên kết
/// → «manual» (lập tay).
/// </summary>
public static class CashSourceBackfill
{
    const string MigrationId = "cash-source-v1";

    public static async Task RunAsync(ZKTecoDbContext db, ILogger logger, CancellationToken ct = default)
    {
        await db.Database.ExecuteSqlRawAsync(
            @"CREATE TABLE IF NOT EXISTS ""SboxDataMigrations"" (""Id"" character varying(100) NOT NULL PRIMARY KEY, ""AppliedAt"" timestamp with time zone NOT NULL DEFAULT now());", ct);
        var done = await db.Database.SqlQueryRaw<int>(
                @"SELECT COUNT(*)::int AS ""Value"" FROM ""SboxDataMigrations"" WHERE ""Id"" = {0}", MigrationId)
            .FirstAsync(ct);
        if (done > 0) return;

        var (linked, branched, total) = await ApplyAsync(db, ct);
        await db.Database.ExecuteSqlRawAsync(
            @"INSERT INTO ""SboxDataMigrations"" (""Id"") VALUES ({0}) ON CONFLICT DO NOTHING", [MigrationId], ct);
        logger.LogInformation("Cash source backfill: {Linked} phiếu gắn nguồn, {Branched} phiếu sửa chi nhánh / {Total} phiếu xét",
            linked, branched, total);
    }

    /// <summary>Phần chuyển dữ liệu (không kèm cờ đã chạy) — trả (gắn nguồn, sửa chi nhánh, tổng xét).</summary>
    public static async Task<(int Linked, int Branched, int Total)> ApplyAsync(ZKTecoDbContext db, CancellationToken ct = default)
    {
        var rows = await db.CashTransactions.IgnoreQueryFilters().AsTracking()
            .Where(c => c.SourceType == null || c.BranchId == null || c.EmployeeId == null)
            .ToListAsync(ct);
        var linked = 0;
        var branched = 0;
        var penaltyCodes = new Dictionary<(Guid?, string), Guid?>();
        foreach (var c in rows)
        {
            var src = CashSources.Resolve(c.SourceType, c.SourceId, c.InternalNote);
            if (src == null && c.SourceType == null && c.InternalNote is { } note
                && note.StartsWith("Tạo từ phiếu phạt ", StringComparison.Ordinal))
            {
                // Phiếu phạt cũ ghi mã phiếu (không phải GUID).
                var code = note["Tạo từ phiếu phạt ".Length..].Split('|', ' ')[0].Trim();
                if (!penaltyCodes.TryGetValue((c.StoreId, code), out var tid))
                    penaltyCodes[(c.StoreId, code)] = tid = await db.PenaltyTickets.IgnoreQueryFilters()
                        .Where(t => t.TicketCode == code && t.StoreId == c.StoreId)
                        .Select(t => (Guid?)t.Id).FirstOrDefaultAsync(ct);
                if (tid is Guid t) src = (CashSources.PenaltyTicket, t);
            }

            if (src == null)
            {
                c.SourceType ??= CashSources.Manual;
                continue;
            }

            var info = await CashSourceResolver.ResolveAsync(db, c.StoreId, src.Value.Type, src.Value.Id, ct);
            if (c.SourceType == null || c.SourceType == CashSources.Manual) linked++;
            c.SourceType = info.Type;
            c.SourceId = src.Value.Id;
            c.EmployeeId ??= info.EmployeeId;
            if (info.BranchId is Guid b && c.BranchId != b && (c.BranchId == null || CashSources.IsPos(info.Type)))
            {
                c.BranchId = b;
                branched++;
            }
        }
        await db.SaveChangesAsync(ct);
        return (linked, branched, rows.Count);
    }
}
