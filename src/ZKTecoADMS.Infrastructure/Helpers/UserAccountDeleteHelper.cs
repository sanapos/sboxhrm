using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Gỡ / chuyển FK trỏ tới AspNetUsers trước khi hard-delete tài khoản đăng nhập.
/// Không xóa dữ liệu nghiệp vụ dùng chung (chấm công thô, thiết bị, phiếu lương…) —
/// chỉ NULL / reassign / xóa bản ghi cá nhân bắt buộc.
/// </summary>
public static class UserAccountDeleteHelper
{
    private sealed record UserFkRef(string TableName, string ColumnName, string IsNullable);

    public static async Task DetachReferencesAsync(
        DbContext db,
        Guid userId,
        Guid reassignToUserId,
        CancellationToken cancellationToken = default)
    {
        // Identity adjunct (also CASCADE, but clear early)
        await db.Database.ExecuteSqlRawAsync(
            @"DELETE FROM ""UserRefreshTokens"" WHERE ""ApplicationUserId"" = {0}",
            [userId],
            cancellationToken);

        // Soft-deleted + active employees: drop login link
        await db.Database.ExecuteSqlRawAsync(
            @"UPDATE ""Employees"" SET ""ApplicationUserId"" = NULL
              WHERE ""ApplicationUserId"" = {0}",
            [userId],
            cancellationToken);

        List<UserFkRef> fkRefs;
        try
        {
            fkRefs = await db.Database
                .SqlQueryRaw<UserFkRef>(
                    @"SELECT tc.table_name AS ""TableName"",
                             kcu.column_name AS ""ColumnName"",
                             col.is_nullable AS ""IsNullable""
                      FROM information_schema.table_constraints tc
                      JOIN information_schema.key_column_usage kcu
                        ON tc.constraint_name = kcu.constraint_name
                       AND tc.table_schema = kcu.table_schema
                      JOIN information_schema.constraint_column_usage ccu
                        ON ccu.constraint_name = tc.constraint_name
                       AND ccu.table_schema = tc.table_schema
                      JOIN information_schema.columns col
                        ON col.table_schema = kcu.table_schema
                       AND col.table_name = kcu.table_name
                       AND col.column_name = kcu.column_name
                      WHERE tc.constraint_type = 'FOREIGN KEY'
                        AND tc.table_schema = 'public'
                        AND ccu.table_name = 'AspNetUsers'
                        AND ccu.column_name = 'Id'")
                .ToListAsync(cancellationToken);
        }
        catch
        {
            return;
        }

        foreach (var fk in fkRefs)
        {
            if (string.IsNullOrWhiteSpace(fk.TableName) || string.IsNullOrWhiteSpace(fk.ColumnName))
                continue;

            // Identity tables cascade with UserManager.DeleteAsync
            if (fk.TableName.StartsWith("AspNet", StringComparison.OrdinalIgnoreCase))
                continue;
            if (fk.TableName is "UserRefreshTokens" or "Stores")
                continue;

            // Identifiers from information_schema only — safe to interpolate as quoted identifiers.
            var table = fk.TableName.Replace("\"", "");
            var column = fk.ColumnName.Replace("\"", "");

            try
            {
                if (string.Equals(fk.IsNullable, "YES", StringComparison.OrdinalIgnoreCase))
                {
                    await db.Database.ExecuteSqlRawAsync(
                        $@"UPDATE ""{table}"" SET ""{column}"" = NULL WHERE ""{column}"" = {{0}}",
                        [userId],
                        cancellationToken);
                    continue;
                }

                if (IsManagerialOrAuditColumn(column))
                {
                    await db.Database.ExecuteSqlRawAsync(
                        $@"UPDATE ""{table}"" SET ""{column}"" = {{0}} WHERE ""{column}"" = {{1}}",
                        [reassignToUserId, userId],
                        cancellationToken);
                }
                else
                {
                    // Personal required rows (EmployeeUserId, swap requests, prefs…) — remove so delete can proceed.
                    await db.Database.ExecuteSqlRawAsync(
                        $@"DELETE FROM ""{table}"" WHERE ""{column}"" = {{0}}",
                        [userId],
                        cancellationToken);
                }
            }
            catch
            {
                // Best-effort per FK; remaining blockers surface on DeleteAsync.
            }
        }
    }

    private static bool IsManagerialOrAuditColumn(string columnName)
    {
        var c = columnName;
        return c.Contains("Manager", StringComparison.OrdinalIgnoreCase)
            || c.Contains("Owner", StringComparison.OrdinalIgnoreCase)
            || c.Contains("Approved", StringComparison.OrdinalIgnoreCase)
            || c.Contains("CreatedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("GeneratedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("UploadedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("PerformedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("AssignedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("ProcessedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("CheckedBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("Responsible", StringComparison.OrdinalIgnoreCase)
            || c.Contains("Evaluator", StringComparison.OrdinalIgnoreCase)
            || c.Contains("SentBy", StringComparison.OrdinalIgnoreCase)
            || c.Contains("Author", StringComparison.OrdinalIgnoreCase)
            || c.Contains("FromUser", StringComparison.OrdinalIgnoreCase);
    }
}
