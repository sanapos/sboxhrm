using System.Collections;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Interceptors;

/// <summary>Một bản ghi bị thêm / sửa / xóa trong một lần lưu (phục vụ Lịch sử thao tác).</summary>
public sealed record ActivityEntityChange(
    string Type,
    string? Id,
    string Op,
    string? Label,
    List<ActivityFieldChange> Fields);

public sealed record ActivityFieldChange(string Field, string? Old, string? New);

/// <summary>Thu thập thay đổi dữ liệu trong một request (scoped) — bộ lọc API ghi thành AuditLog.</summary>
public sealed class ActivityAuditCollector
{
    public const int MaxEntities = 40;
    public List<ActivityEntityChange> Changes { get; } = [];
    /// <summary>Tắt khi chính việc ghi nhật ký đang lưu (tránh ghi vòng).</summary>
    public bool Suspended { get; set; }
}

/// <summary>
/// Ghi lại bản ghi nào được thêm / sửa (trường nào: cũ → mới) / xóa (kể cả xóa mềm) trước khi lưu.
/// Không đọc lại DB, chỉ dùng ChangeTracker. Bỏ qua bảng kỹ thuật và che giá trị nhạy cảm.
/// </summary>
public sealed class ActivityAuditInterceptor(ActivityAuditCollector collector) : SaveChangesInterceptor
{
    static readonly HashSet<string> SkipTypes = new(StringComparer.Ordinal)
    {
        nameof(AuditLog), "RefreshToken", "UserToken", "DeviceCommand", "DeviceInfo", "Notification",
        "NotificationRecipient", "UserNotification", "PushSubscription", "FcmToken", "UserDeviceToken",
        "AttendanceSyncLog", "ErrorLog", "PosPrintJob", "LoginSession", "AccessDeviceSession",
    };

    static readonly HashSet<string> SkipFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "UpdatedAt", "UpdatedBy", "LastModified", "LastModifiedBy", "CreatedAt", "CreatedBy",
        "ConcurrencyStamp", "SecurityStamp", "RowVersion", "Timestamp", "HtmlContent", "DocxMappingJson",
        "ExtraJson", "Template", "PhotoBase64", "ImageBase64", "StampPngBase64", "LogoPngBase64",
        // Tự động / nền (khóa đơn đang sửa, tín hiệu online, đã xem / đã đọc) — không phải thao tác của người dùng.
        "LockExpiresAt", "LockedAt", "LockedByDeviceId", "LockedByDeviceName", "LockedByDisplayName", "LockedByUserId",
        "LastSeen", "LastSeenAt", "LastOnline", "LastActive", "LastActiveAt", "LastLogin", "LastLoginAt",
        "LastHeartbeat", "LastHeartbeatAt", "LastSyncAt", "LastSyncedAt", "IsRead", "ReadAt", "SeenAt",
        "DeviceStatus", "DisplayStateJson", "StateJson",
    };

    static readonly string[] SensitiveMarks = ["password", "secret", "token", "apikey", "api_key", "hash", "pin"];

    static readonly string[] LabelProps =
    [
        "OrderNo", "QuoteNo", "DocNo", "ReceiptNo", "ReturnNo", "PaymentNo", "TransactionNo", "Code",
        "EmployeeCode", "FullName", "Name", "Title", "PackageName", "ProductName", "Key", "Email", "Phone",
    ];

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        Capture(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        Capture(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    void Capture(DbContext? context)
    {
        if (context == null || collector.Suspended) return;
        try
        {
            foreach (var e in context.ChangeTracker.Entries())
            {
                if (collector.Changes.Count >= ActivityAuditCollector.MaxEntities) break;
                if (e.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted)) continue;
                var type = e.Entity.GetType().Name;
                if (SkipTypes.Contains(type) || e.Metadata.IsOwned() || type.Contains("CustomerDisplay")) continue;
                var change = Describe(e, type);
                if (change != null) collector.Changes.Add(change);
            }
        }
        catch
        {
            // Nhật ký không bao giờ được làm hỏng thao tác chính.
        }
    }

    static ActivityEntityChange? Describe(EntityEntry e, string type)
    {
        var id = e.Metadata.FindPrimaryKey()?.Properties
            .Select(p => e.Property(p.Name).CurrentValue?.ToString())
            .FirstOrDefault();
        var label = LabelProps
            .Select(n => e.Metadata.FindProperty(n) is null ? null : e.Property(n).CurrentValue?.ToString())
            .FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));
        var sensitiveKey = type == "AppSettings" && IsSensitive(label);

        if (e.State == EntityState.Added)
        {
            var fields = e.Properties
                .Where(p => !p.Metadata.IsPrimaryKey() && !SkipFields.Contains(p.Metadata.Name))
                // Bỏ giá trị trống, mảng byte / danh sách (ảnh, dữ liệu nhị phân).
                .Where(p => p.CurrentValue is string || p.CurrentValue is not (null or IEnumerable))
                .Where(p => Fmt(p.CurrentValue) is { Length: > 0 and <= 120 })
                .Where(p => p.Metadata.Name is not ("StoreId" or "IsActive" or "Deleted" or "DeletedBy"))
                .Take(12)
                .Select(p => new ActivityFieldChange(p.Metadata.Name, null,
                    Mask(p.Metadata.Name, sensitiveKey, Fmt(p.CurrentValue))))
                .ToList();
            return new ActivityEntityChange(type, id, "Create", label, fields);
        }
        if (e.State == EntityState.Deleted)
            return new ActivityEntityChange(type, id, "Delete", label, []);

        // Sửa: xóa mềm (Deleted: null → thời điểm) coi như Xóa.
        var deletedProp = e.Metadata.FindProperty("Deleted");
        if (deletedProp != null)
        {
            var dp = e.Property("Deleted");
            if (dp.IsModified && dp.OriginalValue == null && dp.CurrentValue != null)
                return new ActivityEntityChange(type, id, "Delete", label, []);
        }
        var changed = e.Properties
            .Where(p => p.IsModified && !SkipFields.Contains(p.Metadata.Name)
                && !Equals(p.OriginalValue, p.CurrentValue))
            .Take(20)
            .Select(p => new ActivityFieldChange(p.Metadata.Name,
                Mask(p.Metadata.Name, sensitiveKey, Fmt(p.OriginalValue)),
                Mask(p.Metadata.Name, sensitiveKey, Fmt(p.CurrentValue))))
            .ToList();
        return changed.Count == 0 ? null : new ActivityEntityChange(type, id, "Update", label, changed);
    }

    static bool IsSensitive(string? name) =>
        name != null && SensitiveMarks.Any(m => name.Contains(m, StringComparison.OrdinalIgnoreCase));

    static string? Mask(string field, bool sensitiveRow, string? value) =>
        value == null ? null : (sensitiveRow && field == "Value") || IsSensitive(field) ? "••••" : value;

    static string? Fmt(object? v)
    {
        if (v == null) return null;
        var s = v switch
        {
            DateTime d => d.ToString("yyyy-MM-dd HH:mm"),
            decimal m => m.ToString("0.##"),
            double d => d.ToString("0.##"),
            bool b => b ? "Có" : "Không",
            _ => v.ToString() ?? "",
        };
        return s.Length > 160 ? s[..160] + "…" : s;
    }
}
