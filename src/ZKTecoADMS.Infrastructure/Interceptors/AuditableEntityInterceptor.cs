using ZKTecoADMS.Domain.Entities.Base;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Infrastructure.Interceptors;

public class AuditableEntityInterceptor : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        UpdateEntities(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        UpdateEntities(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    public static void UpdateEntities(DbContext? context)
    {
        if (context == null) return;

        foreach (var entry in context.ChangeTracker.Entries<AuditableEntity<Guid>>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    if (string.IsNullOrEmpty(entry.Entity.CreatedBy))
                        entry.Entity.CreatedBy = "API";
                    entry.Entity.CreatedAt = DateTime.Now;
                    entry.Entity.LastModified = DateTime.Now;
                    if (string.IsNullOrEmpty(entry.Entity.LastModifiedBy))
                        entry.Entity.LastModifiedBy = entry.Entity.CreatedBy;
                    break;
                case EntityState.Modified:
                    entry.Entity.LastModified = DateTime.Now;
                    if (string.IsNullOrEmpty(entry.Entity.LastModifiedBy))
                        entry.Entity.LastModifiedBy = "API";
                    break;
                case EntityState.Deleted:
                    entry.Entity.Deleted = DateTime.Now;
                    entry.Entity.DeletedBy = "API";
                    break;
            }
        }
    }
}

public static class Extensions
{
    public static bool HasChangedOwnedEntities(this EntityEntry entry) =>
        entry.References.Any(r =>
            r.TargetEntry != null &&
            r.TargetEntry.Metadata.IsOwned() &&
            (r.TargetEntry.State == EntityState.Added || r.TargetEntry.State == EntityState.Modified));
}