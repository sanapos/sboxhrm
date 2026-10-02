using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Base;

/// <summary>
/// Phạm vi chi nhánh khi XEM dữ liệu nhân sự: chi nhánh đang chọn (kèm chi nhánh con) hoặc các chi nhánh được phép.
/// Null = không lọc (cửa hàng chưa dùng chi nhánh / đang xem tất cả).
/// Nhân viên chưa gán chi nhánh được tính thuộc trụ sở.
/// </summary>
public static class BranchViewHelper
{
    public static async Task<HashSet<Guid>?> ViewBranchIdsAsync(HttpContext http, ZKTecoDbContext db, Guid storeId)
    {
        var ctx = http.BranchContext();
        if (ctx == null || !ctx.StoreUsesBranches) return null;
        IEnumerable<Guid>? roots = ctx.FilterBranchId is Guid f ? [f] : ctx.AllowedBranchIds;
        if (roots == null) return null;
        var branches = await db.Branches.AsNoTracking().Where(b => b.StoreId == storeId)
            .Select(b => new { b.Id, b.ParentBranchId }).ToListAsync();
        var set = new HashSet<Guid>(roots);
        var queue = new Queue<Guid>(set);
        while (queue.Count > 0)
        {
            var cur = queue.Dequeue();
            foreach (var c in branches.Where(b => b.ParentBranchId == cur))
                if (set.Add(c.Id)) queue.Enqueue(c.Id);
        }
        return set;
    }

    /// <summary>Nhân viên có thuộc phạm vi xem không (null branch = trụ sở).</summary>
    public static bool InView(HashSet<Guid>? view, Guid? employeeBranchId, Guid? headquarterId) =>
        view == null || view.Contains(employeeBranchId ?? headquarterId ?? Guid.Empty);
}
