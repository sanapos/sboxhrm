using System.Text.Json;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

public static class PayslipAttendanceSnapshotHelper
{
    public static async Task SaveSnapshotAsync(
        IRepository<PayslipAttendanceSnapshot> snapshotRepository,
        Guid payslipId,
        Guid storeId,
        Guid userId,
        DateTime periodStart,
        DateTime periodEnd,
        JsonElement? snapshotElement,
        CancellationToken cancellationToken)
    {
        if (snapshotElement == null || snapshotElement.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            return;

        var json = snapshotElement.Value.GetRawText();
        if (string.IsNullOrWhiteSpace(json) || json == "null")
            return;

        var existing = await snapshotRepository.GetSingleAsync(
            filter: s => s.PayslipId == payslipId,
            cancellationToken: cancellationToken);

        var now = DateTime.UtcNow;
        if (existing != null)
        {
            existing.StoreId = storeId;
            existing.PeriodStart = periodStart;
            existing.PeriodEnd = periodEnd;
            existing.SnapshotJson = json;
            existing.CapturedAt = now;
            existing.CapturedByUserId = userId;
            await snapshotRepository.UpdateAsync(existing, cancellationToken);
            return;
        }

        await snapshotRepository.AddAsync(new PayslipAttendanceSnapshot
        {
            Id = Guid.NewGuid(),
            PayslipId = payslipId,
            StoreId = storeId,
            PeriodStart = periodStart,
            PeriodEnd = periodEnd,
            SnapshotJson = json,
            CapturedAt = now,
            CapturedByUserId = userId
        }, cancellationToken);
    }

    public static object? ParseSnapshotJson(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
            return null;

        try
        {
            return JsonSerializer.Deserialize<object>(json);
        }
        catch
        {
            return null;
        }
    }
}
