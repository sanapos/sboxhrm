using System.Collections.Concurrent;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// «Duyệt từ xa» POS: thu ngân bị chặn «Cần quản lý duyệt» gửi yêu cầu, chủ / quản lý duyệt trên SBOX BOSS
/// → máy chủ cấp đúng mã duyệt <see cref="PosAfterBillApproval"/> (5 phút) cho máy POS đang chờ.
/// Yêu cầu chỉ sống <see cref="RequestLifetime"/> nên giữ trong bộ nhớ tiến trình (không cần bảng DB);
/// API khởi động lại thì yêu cầu đang chờ mất — máy POS báo hết hạn, thu ngân gửi lại.
/// </summary>
public static class PosRemoteApprovals
{
    public static readonly TimeSpan RequestLifetime = TimeSpan.FromMinutes(3);
    /// <summary>Giữ kết quả (đã duyệt / từ chối) thêm một lúc để máy POS kịp hỏi lại.</summary>
    static readonly TimeSpan KeepDecided = TimeSpan.FromMinutes(6);
    const int MaxPendingPerStore = 20;

    public sealed class Request
    {
        public Guid Id { get; init; }
        public Guid StoreId { get; init; }
        public Guid? BranchId { get; init; }
        public string Reason { get; init; } = "";
        public string? Detail { get; init; }
        public decimal? Amount { get; init; }
        public string RequestedBy { get; init; } = "";
        public Guid RequestedByUserId { get; init; }
        public DateTime CreatedAt { get; init; }
        public DateTime ExpiresAt { get; init; }
        /// <summary>pending | approved | rejected | cancelled | expired</summary>
        public string Status { get; set; } = "pending";
        public string? DecidedBy { get; set; }
        public DateTime? DecidedAt { get; set; }
        public string? RejectReason { get; set; }
        public string? ApprovalToken { get; set; }
    }

    static readonly ConcurrentDictionary<Guid, Request> Items = new();

    static void Prune(DateTime now)
    {
        foreach (var (id, r) in Items)
        {
            lock (r)
            {
                if (r.Status == "pending" && now > r.ExpiresAt)
                {
                    r.Status = "expired";
                    r.DecidedAt = r.ExpiresAt;
                }
                if (r.Status != "pending" && now > (r.DecidedAt ?? r.ExpiresAt) + KeepDecided)
                    Items.TryRemove(id, out _);
            }
        }
    }

    public static Request? Create(Guid storeId, Guid? branchId, Guid userId, string requestedBy,
        string reason, string? detail, decimal? amount)
    {
        var now = DateTime.UtcNow;
        Prune(now);
        if (Items.Values.Count(x => x.StoreId == storeId && x.Status == "pending") >= MaxPendingPerStore) return null;
        var r = new Request
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            BranchId = branchId,
            Reason = reason.Length > 300 ? reason[..300] : reason,
            Detail = detail is { Length: > 500 } ? detail[..500] : detail,
            Amount = amount,
            RequestedBy = requestedBy,
            RequestedByUserId = userId,
            CreatedAt = now,
            ExpiresAt = now + RequestLifetime,
        };
        Items[r.Id] = r;
        return r;
    }

    public static Request? Get(Guid storeId, Guid id)
    {
        Prune(DateTime.UtcNow);
        return Items.TryGetValue(id, out var r) && r.StoreId == storeId ? r : null;
    }

    public static List<Request> Pending(Guid storeId)
    {
        Prune(DateTime.UtcNow);
        return Items.Values.Where(x => x.StoreId == storeId && x.Status == "pending")
            .OrderBy(x => x.CreatedAt).ToList();
    }

    /// <summary>Chốt quyết định một lần (hai người duyệt cùng lúc: người sau nhận false).</summary>
    public static bool Decide(Request r, string status, string decidedBy, string? token, string? rejectReason)
    {
        lock (r)
        {
            if (r.Status != "pending" || DateTime.UtcNow > r.ExpiresAt) return false;
            r.Status = status;
            r.DecidedBy = decidedBy;
            r.DecidedAt = DateTime.UtcNow;
            r.ApprovalToken = token;
            r.RejectReason = rejectReason;
            return true;
        }
    }
}
