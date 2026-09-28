using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers.Base;

/// <summary>
/// Lọc chứng từ theo chi nhánh của người xem:
///  • ?branchId= hợp lệ → chỉ chi nhánh đó;
///  • người bị giới hạn chi nhánh → chỉ các chi nhánh được phép;
///  • chủ / quản trị không lọc gì → toàn cửa hàng (như trước).
/// Chứng từ chưa gắn chi nhánh (null) được tính là của trụ sở.
/// </summary>
public static class BranchScopeExtensions
{
    public static IQueryable<T> ApplyBranchScope<T>(this IQueryable<T> query, IBranchContext? ctx)
        where T : class, IBranchScoped
    {
        if (ctx == null || !ctx.StoreUsesBranches) return query;
        var hq = ctx.HeadquarterBranchId ?? Guid.Empty;
        if (ctx.FilterBranchId is Guid f)
            return query.Where(x => (x.BranchId ?? hq) == f);
        if (ctx.AllowedBranchIds is { } allowed)
        {
            var list = allowed.ToList();
            return query.Where(x => list.Contains(x.BranchId ?? hq));
        }
        return query;
    }

    public static IBranchContext? BranchContext(this HttpContext? http)
        => http?.RequestServices.GetService(typeof(IBranchContext)) as IBranchContext;
}
