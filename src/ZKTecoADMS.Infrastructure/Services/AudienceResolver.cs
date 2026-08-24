using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

public class AudienceResolver : IAudienceResolver
{
    private readonly ZKTecoDbContext _db;
    private readonly UserManager<ApplicationUser> _userManager;

    public AudienceResolver(ZKTecoDbContext db, UserManager<ApplicationUser> userManager)
    {
        _db = db;
        _userManager = userManager;
    }

    public async Task<List<AudienceMember>> ResolveAsync(AudienceSpec spec, CancellationToken ct = default)
    {
        var query = BuildQuery(spec);
        var users = await query
            .Select(u => new { u.Id, u.StoreId, u.Role })
            .ToListAsync(ct);

        var excluded = spec.ExcludeUserIds is { Count: > 0 }
            ? new HashSet<Guid>(spec.ExcludeUserIds)
            : null;

        return users
            .Where(u => excluded == null || !excluded.Contains(u.Id))
            .Select(u => new AudienceMember(u.Id, u.StoreId, u.Role))
            .ToList();
    }

    public async Task<AudiencePreviewDto> PreviewAsync(AudienceSpec spec, CancellationToken ct = default)
    {
        var members = await ResolveAsync(spec, ct);
        return new AudiencePreviewDto
        {
            TotalUsers = members.Count,
            TotalStores = members.Where(m => m.StoreId.HasValue).Select(m => m.StoreId!.Value).Distinct().Count(),
            ByRole = members
                .GroupBy(m => string.IsNullOrEmpty(m.Role) ? "(none)" : m.Role!)
                .ToDictionary(g => g.Key, g => g.Count())
        };
    }

    private IQueryable<ApplicationUser> BuildQuery(AudienceSpec spec)
    {
        IQueryable<ApplicationUser> q = _userManager.Users.Where(u => u.IsActive);

        // Resolve store ids implied by Package / Agent / LicenseStatus filters
        var storeIdSet = spec.StoreIds is { Count: > 0 }
            ? new HashSet<Guid>(spec.StoreIds)
            : null;

        if (spec.PackageIds is { Count: > 0 })
        {
            var pkgStores = _db.Stores
                .Where(s => s.ServicePackageId != null && spec.PackageIds.Contains(s.ServicePackageId!.Value))
                .Select(s => s.Id)
                .ToHashSet();
            storeIdSet = Intersect(storeIdSet, pkgStores);
        }

        if (spec.AgentIds is { Count: > 0 })
        {
            var agentStores = _db.Stores
                .Where(s => s.AgentId != null && spec.AgentIds.Contains(s.AgentId!.Value))
                .Select(s => s.Id)
                .ToHashSet();
            storeIdSet = Intersect(storeIdSet, agentStores);
        }

        if (!string.IsNullOrEmpty(spec.LicenseStatus))
        {
            var now = DateTime.UtcNow;
            var soon = now.AddDays(30);
            var statusStores = spec.LicenseStatus.ToLowerInvariant() switch
            {
                "expired" => _db.Stores.Where(s => s.ExpiryDate.HasValue && s.ExpiryDate.Value < now).Select(s => s.Id).ToHashSet(),
                "expiring_soon" => _db.Stores.Where(s => s.ExpiryDate.HasValue && s.ExpiryDate.Value >= now && s.ExpiryDate.Value <= soon).Select(s => s.Id).ToHashSet(),
                "active" => _db.Stores.Where(s => !s.ExpiryDate.HasValue || s.ExpiryDate.Value > now).Select(s => s.Id).ToHashSet(),
                _ => null
            };
            storeIdSet = Intersect(storeIdSet, statusStores);
        }

        if (storeIdSet != null)
        {
            // empty intersection ⇒ no users
            if (storeIdSet.Count == 0) return q.Where(_ => false);
            q = q.Where(u => u.StoreId.HasValue && storeIdSet.Contains(u.StoreId!.Value));
        }
        else if (!spec.AllUsers)
        {
            // Không AllUsers và không lọc store ⇒ không gửi (tránh nhầm toàn hệ thống).
            var hasOther = (spec.Roles is { Count: > 0 }) || spec.LastLoginBefore.HasValue;
            if (!hasOther)
                return q.Where(_ => false);
        }

        if (spec.Roles is { Count: > 0 })
        {
            var roles = spec.Roles.Select(r => r.ToLower()).ToList();
            q = q.Where(u => u.Role != null && roles.Contains(u.Role.ToLower()));
        }

        if (spec.LastLoginBefore.HasValue)
        {
            var threshold = spec.LastLoginBefore.Value;
            q = q.Where(u => !u.LastLoginAt.HasValue || u.LastLoginAt < threshold);
        }

        // If AllUsers flag is true and no filters applied at all, just return active users
        return q;
    }

    private static HashSet<Guid>? Intersect(HashSet<Guid>? a, HashSet<Guid>? b)
    {
        if (a == null) return b;
        if (b == null) return a;
        a.IntersectWith(b);
        return a;
    }
}
