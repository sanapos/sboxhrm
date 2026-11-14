using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

internal static class PosKitchenKdsHelper
{
    public const string None = "none";
    public const string Queued = "queued";
    public const string Cooking = "cooking";
    public const string Ready = "ready";
    public const string Done = "done";
    public const string Voided = "voided";

    public static decimal OpenQty(PosSaleOrderLine line) =>
        Math.Max(0, line.KitchenSentQty - line.KitchenDoneQty);

    public static void OnSent(PosSaleOrderLine line)
    {
        var s = Normalize(line.KitchenPrepStatus);
        if (s is None or Done)
            line.KitchenPrepStatus = Queued;
        if (line.KitchenDoneQty > line.KitchenSentQty)
            line.KitchenDoneQty = line.KitchenSentQty;
    }

    public static void Clamp(PosSaleOrderLine line)
    {
        if (line.KitchenDoneQty < 0) line.KitchenDoneQty = 0;
        if (line.KitchenDoneQty > line.KitchenSentQty)
            line.KitchenDoneQty = Math.Max(0, line.KitchenSentQty);
        if (line.KitchenSentQty <= 0)
        {
            line.KitchenPrepStatus = None;
            line.KitchenDoneQty = 0;
            return;
        }
        if (OpenQty(line) <= 0)
            line.KitchenPrepStatus = Done;
    }

    /// <param name="seenSentQty">
    /// Số đã báo bếp mà màn bếp ĐANG HIỆN lúc bấm (null = app cũ không gửi). Bấm «Xong» chỉ đóng tới số đó: thu
    /// ngân vừa báo thêm (x2 → x3) mà màn bếp chưa kịp tải lại thì phần mới gọi vẫn nằm lại trên màn, không bị
    /// đóng theo — trước đây đóng hết theo số trên máy chủ, phần gọi thêm không ai làm.
    /// </param>
    public static void ApplyStatus(PosSaleOrderLine line, string status, decimal? seenSentQty = null)
    {
        status = Normalize(status);
        if (status is not (Queued or Cooking or Ready or Done))
            return;
        if (status == Done)
        {
            if (DoneOnlySeen(line, seenSentQty)) return;
            line.KitchenDoneQty = line.KitchenSentQty;
            line.KitchenPrepStatus = Done;
            return;
        }
        if (OpenQty(line) <= 0 && line.KitchenSentQty > 0)
            line.KitchenDoneQty = Math.Max(0, line.KitchenSentQty - 0.001m);
        line.KitchenPrepStatus = status;
        Clamp(line);
    }

    public static void Bump(PosSaleOrderLine line, decimal? seenSentQty = null)
    {
        if (line.KitchenSentQty <= 0) return;
        if (DoneOnlySeen(line, seenSentQty)) return;
        line.KitchenDoneQty = line.KitchenSentQty;
        line.KitchenPrepStatus = Done;
    }

    /// <summary>
    /// Màn bếp thấy ít hơn số đã báo hiện tại → chỉ đóng phần đã thấy, phần còn lại quay về hàng chờ.
    /// Trả true nếu đã xử lý theo cách này.
    /// </summary>
    static bool DoneOnlySeen(PosSaleOrderLine line, decimal? seenSentQty)
    {
        if (seenSentQty is not decimal seen) return false;
        if (seen + 0.0001m >= line.KitchenSentQty) return false;
        line.KitchenDoneQty = Math.Max(line.KitchenDoneQty, Math.Max(0, seen));
        line.KitchenPrepStatus = Queued;
        return true;
    }

    /// <summary>
    /// Đơn vừa thanh toán. Đơn CÓ BÀN (ăn xong mới trả): đóng vé còn treo như trước, không chờ bếp bấm Xong.
    /// Đơn KHÔNG gắn bàn (bán tại quầy, đơn online — thu tiền trước, làm sau): GIỮ vé trên màn bếp tới khi bếp bấm
    /// Xong; trước đây vé biến mất ngay lúc thu tiền khi bếp chưa làm. Đơn bán lúc mất mạng gửi lên sau thì món
    /// đã giao từ lâu → đóng luôn.
    /// </summary>
    public static void OnOrderPaid(PosSaleOrder order, IEnumerable<PosSaleOrderLine> lines, bool offlineSync = false)
    {
        var hasTable = order.ServiceResourceId != null || order.ResourceSessionId != null;
        if (hasTable || offlineSync || order.OfflineNo != null)
        {
            CloseOpenOnPaid(lines);
            return;
        }
        foreach (var line in lines)
        {
            if (line.Deleted != null || OpenQty(line) <= 0) continue;
            // Dòng vừa tạo kèm «đã báo bếp» còn trạng thái trống → đưa vào hàng chờ của màn bếp.
            if (Normalize(line.KitchenPrepStatus) == None)
                line.KitchenPrepStatus = Queued;
        }
    }

    /// <summary>Đóng phiếu KDS còn treo (không chờ bếp bấm Xong).</summary>
    public static void CloseOpenOnPaid(IEnumerable<PosSaleOrderLine> lines)
    {
        foreach (var line in lines)
        {
            if (line.Deleted != null) continue;
            Bump(line);
        }
    }

    public static void Recall(PosSaleOrderLine line)
    {
        if (line.KitchenSentQty <= 0) return;
        line.KitchenDoneQty = 0;
        line.KitchenPrepStatus = Queued;
    }

    public static string MergeStatus(IEnumerable<string?> statuses, bool hasOpen)
    {
        if (!hasOpen) return Done;
        var set = new HashSet<string>(
            statuses.Select(Normalize).Where(s => s.Length > 0),
            StringComparer.OrdinalIgnoreCase);
        if (set.Contains(Cooking)) return Cooking;
        if (set.Contains(Ready)) return Ready;
        if (set.Contains(Queued)) return Queued;
        return Queued;
    }

    public static string Normalize(string? raw)
    {
        var s = (raw ?? "").Trim().ToLowerInvariant();
        return s switch
        {
            Cooking or "cook" or "doing" => Cooking,
            Ready or "plated" => Ready,
            Done or "bump" or "bumped" => Done,
            Voided or "void" or "cancel" or "cancelled" => Voided,
            Queued or "new" => Queued,
            None or "" => None,
            _ => s,
        };
    }
}
