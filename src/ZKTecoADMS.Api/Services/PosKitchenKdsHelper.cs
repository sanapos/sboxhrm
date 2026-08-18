using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

internal static class PosKitchenKdsHelper
{
    public const string None = "none";
    public const string Queued = "queued";
    public const string Cooking = "cooking";
    public const string Ready = "ready";
    public const string Done = "done";

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

    public static void ApplyStatus(PosSaleOrderLine line, string status)
    {
        status = Normalize(status);
        if (status is not (Queued or Cooking or Ready or Done))
            return;
        if (status == Done)
        {
            line.KitchenDoneQty = line.KitchenSentQty;
            line.KitchenPrepStatus = Done;
            return;
        }
        if (OpenQty(line) <= 0 && line.KitchenSentQty > 0)
            line.KitchenDoneQty = Math.Max(0, line.KitchenSentQty - 0.001m);
        line.KitchenPrepStatus = status;
        Clamp(line);
    }

    public static void Bump(PosSaleOrderLine line)
    {
        if (line.KitchenSentQty <= 0) return;
        line.KitchenDoneQty = line.KitchenSentQty;
        line.KitchenPrepStatus = Done;
    }

    /// <summary>Thanh toán xong: đóng phiếu KDS còn treo (không chờ bếp bấm Xong).</summary>
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
            Queued or "new" => Queued,
            None or "" => None,
            _ => s,
        };
    }
}
