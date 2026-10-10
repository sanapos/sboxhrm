using ZKTecoADMS.Infrastructure.Interceptors;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Ghi bù «Lịch sử thao tác» cho thao tác cập nhật thẳng DB (ExecuteUpdate / ExecuteDelete):
/// các lệnh này không qua ChangeTracker nên bộ ghi tự động không thấy (xóa hàng hóa, xóa chấm công,
/// xóa bàn / máy in, hủy đơn tạm…). Gọi SAU khi lệnh chạy thành công.
/// </summary>
public static class ActivityTrail
{
    public static void Deleted(HttpContext http, string type, object? id, string? label, int count = 1) =>
        Record(http, type, id, "Delete", count > 1 ? $"{label} ({count} bản ghi)" : label);

    public static void Updated(HttpContext http, string type, object? id, string? label,
        params (string Field, string? Old, string? New)[] fields) =>
        Record(http, type, id, "Update", label, fields);

    public static void Record(HttpContext http, string type, object? id, string op, string? label,
        params (string Field, string? Old, string? New)[] fields)
    {
        var collector = http.RequestServices.GetService<ActivityAuditCollector>();
        if (collector == null || collector.Suspended || collector.Changes.Count >= ActivityAuditCollector.MaxEntities) return;
        collector.Changes.Add(new ActivityEntityChange(
            type,
            id?.ToString(),
            op,
            string.IsNullOrWhiteSpace(label) ? null : label.Trim(),
            fields.Select(f => new ActivityFieldChange(f.Field, f.Old, f.New)).ToList()));
    }
}
