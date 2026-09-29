using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Middlewares;

/// <summary>
/// Điền <see cref="IBranchContext"/> cho request đã đăng nhập:
///  • Chi nhánh được xem: chủ / giám đốc / quản trị / kế toán → tất cả; người khác → chi nhánh
///    mình quản lý (Branch.ManagerId, BranchPermission) + chi nhánh của chính mình.
///  • Chi nhánh đang thao tác: header X-Branch-Id (nếu được phép) → chi nhánh của NV → trụ sở.
///  • Lọc báo cáo: query ?branchId= (nếu được phép).
/// </summary>
public sealed class BranchContextMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Branch-Id";

    private static readonly HashSet<string> AllBranchRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        nameof(Roles.Admin), nameof(Roles.Director), nameof(Roles.SuperAdmin), nameof(Roles.Agent), nameof(Roles.Accountant),
    };

    public async Task InvokeAsync(
        HttpContext http, IBranchContext branchContext, ZKTecoDbContext db, IDataScopeService dataScope, IMemoryCache cache)
    {
        try
        {
            if (http.User.Identity?.IsAuthenticated == true &&
                Guid.TryParse(http.User.FindFirst(ClaimTypeNames.StoreId)?.Value, out var storeId))
            {
                await FillAsync(http, branchContext, db, dataScope, cache, storeId);
            }
        }
        catch
        {
            // Không để lỗi phân quyền chi nhánh chặn request — ngữ cảnh trống = hành vi cũ (toàn cửa hàng).
        }
        await next(http);
    }

    private static async Task FillAsync(
        HttpContext http, IBranchContext ctx, ZKTecoDbContext db, IDataScopeService dataScope, IMemoryCache cache, Guid storeId)
    {
        var branches = await cache.GetOrCreateAsync($"branches:{storeId}", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(60);
            e.Size = 1;
            return await BranchStockService.GetStoreBranchesAsync(db, storeId);
        }) ?? [];
        if (branches.Count == 0) return; // cửa hàng chưa dùng chi nhánh

        var ids = branches.Select(b => b.Id).ToHashSet();
        ctx.StoreUsesBranches = true;
        ctx.HeadquarterBranchId = BranchStockService.ResolveHeadquarter(branches);

        var role = http.User.FindFirst(ClaimTypes.Role)?.Value ?? "";
        Guid.TryParse(http.User.FindFirst("id")?.Value ?? http.User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var userId);
        Guid.TryParse(http.User.FindFirst(ClaimTypeNames.EmployeeId)?.Value, out var employeeId);

        // Chi nhánh của chính NV
        Guid? ownBranch = null;
        if (employeeId != Guid.Empty)
        {
            ownBranch = await cache.GetOrCreateAsync($"emp-branch:{employeeId}", async e =>
            {
                e.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(60);
                e.Size = 1;
                return await db.Employees.AsNoTracking().Where(x => x.Id == employeeId).Select(x => x.BranchId).FirstOrDefaultAsync();
            });
            if (ownBranch.HasValue && !ids.Contains(ownBranch.Value)) ownBranch = null;
        }

        IReadOnlyCollection<Guid>? allowed = null;
        if (!AllBranchRoles.Contains(role) && userId != Guid.Empty)
        {
            var set = await cache.GetOrCreateAsync($"branch-scope:{storeId}:{userId}", async e =>
            {
                e.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(60);
                e.Size = 1;
                var managed = await dataScope.GetManagedBranchIdsAsync(userId, storeId);
                var s = managed.ToHashSet();
                if (ownBranch.HasValue)
                {
                    s.Add(ownBranch.Value);
                    // gồm chi nhánh con của chi nhánh mình
                    var queue = new Queue<Guid>([ownBranch.Value]);
                    while (queue.Count > 0)
                    {
                        var cur = queue.Dequeue();
                        foreach (var c in branches.Where(b => b.ParentBranchId == cur))
                            if (s.Add(c.Id)) queue.Enqueue(c.Id);
                    }
                }
                return s;
            }) ?? [];
            // Chưa gán chi nhánh nào → giữ hành vi cũ (xem toàn cửa hàng).
            allowed = set.Count == 0 ? null : set;
        }
        ctx.AllowedBranchIds = allowed;
        ctx.UserId = userId == Guid.Empty ? null : userId;
        ctx.RestrictWrites = userId != Guid.Empty && !AllBranchRoles.Contains(role);

        bool Ok(Guid id) => ids.Contains(id) && (allowed == null || allowed.Contains(id));

        // Chi nhánh đang thao tác
        Guid? current = null;
        if (Guid.TryParse(http.Request.Headers[HeaderName].FirstOrDefault(), out var hdr) && Ok(hdr)) current = hdr;
        current ??= ownBranch.HasValue && Ok(ownBranch.Value) ? ownBranch : null;
        current ??= allowed == null ? ctx.HeadquarterBranchId : allowed.FirstOrDefault();
        ctx.CurrentBranchId = current;

        // Lọc báo cáo theo 1 chi nhánh
        if (Guid.TryParse(http.Request.Query["branchId"].FirstOrDefault(), out var filter) && Ok(filter))
            ctx.FilterBranchId = filter;
    }
}

public static class BranchContextMiddlewareExtensions
{
    public static IApplicationBuilder UseBranchContext(this IApplicationBuilder app)
        => app.UseMiddleware<BranchContextMiddleware>();
}
