using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Quy tắc chấm cơm dùng chung cho máy chấm công căn tin, QR và nhập tay:
/// chọn buổi ăn theo giờ, giá suất chốt tại lúc chấm, số phiếu ăn trong ngày.
/// </summary>
public static class MealRules
{
    /// <summary>Cho phép chấm sớm / trễ so với khung giờ buổi ăn (phút).</summary>
    public const int ToleranceMinutes = 30;

    /// <summary>Nguồn chấm cơm.</summary>
    public const int SourceDevice = 0, SourceQr = 1, SourceManual = 2;

    /// <summary>Buổi ăn qua nửa đêm (VD 23:00–01:00) khi giờ bắt đầu lớn hơn giờ kết thúc.</summary>
    public static bool InWindow(MealSession s, TimeSpan t) =>
        s.StartTime <= s.EndTime
            ? t >= s.StartTime && t <= s.EndTime
            : t >= s.StartTime || t <= s.EndTime;

    /// <summary>Số phút từ <paramref name="t"/> đến khung giờ buổi ăn (0 = nằm trong khung).</summary>
    public static double MinutesOutside(MealSession s, TimeSpan t)
    {
        if (InWindow(s, t)) return 0;
        static double Dist(TimeSpan a, TimeSpan b)
        {
            var d = Math.Abs((a - b).TotalMinutes);
            return Math.Min(d, 1440 - d); // tính vòng qua nửa đêm
        }
        return Math.Min(Dist(t, s.StartTime), Dist(t, s.EndTime));
    }

    /// <summary>
    /// Buổi ăn khớp giờ chấm: ưu tiên buổi chứa giờ chấm; nếu không, buổi gần nhất trong phạm vi
    /// ±<paramref name="toleranceMinutes"/>. Ngoài phạm vi → null (không tự gán vào buổi xa —
    /// trước đây chấm 3h sáng vẫn bị tính là bữa sáng và bị thu tiền).
    /// </summary>
    public static MealSession? MatchSession(IEnumerable<MealSession> sessions, TimeSpan t,
        int toleranceMinutes = ToleranceMinutes)
    {
        MealSession? best = null;
        var bestDist = double.MaxValue;
        foreach (var s in sessions)
        {
            var d = MinutesOutside(s, t);
            if (d < bestDist)
            {
                best = s;
                bestDist = d;
            }
        }
        return bestDist <= toleranceMinutes ? best : null;
    }

    /// <summary>Giá 1 suất: giá chốt lúc chấm, bản ghi cũ chưa có giá thì lấy giá buổi ăn.</summary>
    public static decimal PriceOf(MealRecord r, IReadOnlyDictionary<Guid, decimal> sessionPrices) =>
        r.Price ?? sessionPrices.GetValueOrDefault(r.MealSessionId);

    /// <summary>Số phiếu ăn tiếp theo trong ngày của cửa hàng.</summary>
    public static async Task<int> NextTicketNoAsync(IRepository<MealRecord> repo, Guid storeId, DateTime date,
        CancellationToken ct = default)
    {
        var day = date.Date;
        var last = await repo.GetAllAsync(
            r => r.StoreId == storeId && r.Date == day,
            orderBy: q => q.OrderByDescending(r => r.TicketNo),
            take: 1,
            cancellationToken: ct);
        return (last.FirstOrDefault()?.TicketNo ?? 0) + 1;
    }
}
