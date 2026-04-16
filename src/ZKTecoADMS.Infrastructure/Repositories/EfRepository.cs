using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Query;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Domain.Exceptions;

namespace ZKTecoADMS.Infrastructure.Repositories;

public class EfRepository<TEntity>(
    ZKTecoDbContext context, 
    ILogger<EfRepository<TEntity>> logger,
    ITenantProvider tenantProvider
    ) : Repository<TEntity>, IRepository<TEntity> where TEntity : Entity<Guid>
{
    protected readonly DbSet<TEntity> dbSet = context.Set<TEntity>();

    public DbSet<TEntity> DbSet => dbSet;

    public override async Task<List<TEntity>> GetAllAsync(
        Expression<Func<TEntity, bool>>? filter = null,
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null,
        string[]? includeProperties = null,
        int? skip = null,
        int? take = null,
        CancellationToken cancellationToken = default)
    {
        logger.LogDebug("Getting all entities of type {EntityType} with filter: {HasFilter}, orderBy: {HasOrderBy}, includes: {Includes}",
            typeof(TEntity).Name, filter != null, orderBy != null, includeProperties?.Length ?? 0);

        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (filter != null)
            {
                query = query.Where(filter);
            }

            if (includeProperties != null)
            {
                query = includeProperties.Aggregate(query, (current, includeProperty) => current.Include(includeProperty));
            }

            if (skip.HasValue)
            {
                query = query.Skip(skip.Value);
            }

            if (take.HasValue)
            {
                query = query.Take(take.Value);
            }

            List<TEntity> result;
            if (orderBy != null)
            {
                result = await orderBy(query).ToListAsync(cancellationToken);
            }
            else
            {
                result = await query.ToListAsync(cancellationToken);
            }


            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving all entities of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<List<TEntity>> GetAllWithIncludeAsync(
        Expression<Func<TEntity, bool>>? filter = null, 
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null, 
        Func<IQueryable<TEntity>, IIncludableQueryable<TEntity, object>>? includes = null, 
        int? skip = null, 
        int? take = null,
        CancellationToken cancellationToken = default)
    {
        logger.LogDebug("Getting all entities of type {EntityType} with filter: {HasFilter}, orderBy: {HasOrderBy}, includes: {Includes}",
            typeof(TEntity).Name, filter != null, orderBy != null, includes != null);

        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (filter != null)
            {
                query = query.Where(filter);
            }

            if (includes != null)
            {
                query = includes(query);
            }
            
            if (skip.HasValue)
            {
                query = query.Skip(skip.Value);
            }

            if (take.HasValue)
            {
                query = query.Take(take.Value);
            }

            List<TEntity> result;
            if (orderBy != null)
            {
                result = await orderBy(query).ToListAsync(cancellationToken);
            }
            else
            {
                result = await query.ToListAsync(cancellationToken);
            }


            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving all entities of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<TEntity?> GetByIdAsync(Guid id, string[]? includeProperties = null, CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (includeProperties != null)
            {
                query = includeProperties.Aggregate(query, (current, includeProperty) => current.Include(includeProperty));
            }

            var result = await query.FirstOrDefaultAsync(e => e.Id.Equals(id), cancellationToken);

            if (result == null)
            {
                logger.LogWarning("Entity of type {EntityType} with ID {Id} not found", 
                    typeof(TEntity).Name, id);
            }
            
            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving entity of type {EntityType} with ID: {Id}", 
                typeof(TEntity).Name, id);
            throw;
        }
    }


    public override async Task<TEntity?> GetSingleAsync(
        Expression<Func<TEntity, bool>> filter, 
        string[]? includeProperties = null, 
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (includeProperties != null)
            {
                query = includeProperties.Aggregate(query, (current, includeProperty) => current.Include(includeProperty));
            }

            if (orderBy != null)
            {
                query = orderBy(query);
            }

            var result = await query.FirstOrDefaultAsync(filter, cancellationToken);
            
            if(result == null)
            {
                logger.LogWarning("Entity of type {EntityType} with filter {Filter} not found", 
                    typeof(TEntity).Name, filter);
            }

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving entity of type {EntityType} with ID: {Id}",
                typeof(TEntity).Name, filter);
            throw;
        }
    }

    public override async Task<TEntity> AddAsync(TEntity entity, CancellationToken cancellationToken = default)
    {
        if (entity == null)
        {
            logger.LogWarning("Attempted to insert null entity of type {EntityType}", typeof(TEntity).Name);
            throw new ArgumentNullException(nameof(entity));
        }

        try
        {
            // Auto-set StoreId from tenant context if not already set
            StampTenantId(entity);
            
            await dbSet.AddAsync(entity, cancellationToken);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;

            if (result)
            {
                logger.LogInformation("Successfully inserted entity of type {EntityType} with ID: {Id}",
                    typeof(TEntity).Name, entity.Id);
            }
            else
            {
                logger.LogWarning("Insert operation for entity of type {EntityType} with ID: {Id} returned false",
                    typeof(TEntity).Name, entity.Id);
            }

            return entity;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error inserting entity of type {EntityType} with ID: {Id}",
                typeof(TEntity).Name, entity.Id);

            throw;
        }
    }

    public async override Task<bool> AddOrUpdateAsync(TEntity entity, CancellationToken cancellationToken = default)
    {
        var exists = await ExistsAsync(entity.Id);
        if (exists)
        {
            return await UpdateAsync(entity, cancellationToken);
        }
        else
        {
            await AddAsync(entity, cancellationToken);
            return true;
        }
    }
    
    public override async Task<bool> AddRangeAsync(IEnumerable<TEntity> entities, CancellationToken cancellationToken = default)
    {
        if (entities == null || !entities.Any())
        {
            logger.LogWarning("Attempted to insert null or empty entity collection of type {EntityType}", typeof(TEntity).Name);
            throw new ArgumentNullException(nameof(entities));
        }

        try
        {
            // Auto-set StoreId from tenant context if not already set
            foreach (var entity in entities)
            {
                StampTenantId(entity);
            }
            
            await dbSet.AddRangeAsync(entities, cancellationToken);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;

            if (result)
            {
                logger.LogInformation("Successfully inserted {Count} entities of type {EntityType}",
                    entities.Count(), typeof(TEntity).Name);
            }
            else
            {
                logger.LogWarning("Insert operation for entities of type {EntityType} returned false",
                    typeof(TEntity).Name);
            }

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error inserting entities of type {EntityType}",
                typeof(TEntity).Name);

            throw;
        }
    }

    public override async Task<bool> UpdateAsync(TEntity entity, CancellationToken cancellationToken = default)
    {
        if (entity == null)
        {
            logger.LogWarning("Attempted to update null entity of type {EntityType}", typeof(TEntity).Name);
            throw new ArgumentNullException(nameof(entity));
        }

        try
        {
            entity.UpdatedAt = DateTime.Now;
            dbSet.Update(entity);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;
            
            if (result)
            {
                logger.LogInformation("Successfully updated entity of type {EntityType} with ID: {Id}", 
                    typeof(TEntity).Name, entity.Id);
            }
            else
            {
                logger.LogWarning("Update operation for entity of type {EntityType} with ID: {Id} returned false", 
                    typeof(TEntity).Name, entity.Id);
            }
            
            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating entity of type {EntityType} with ID: {Id}", 
                typeof(TEntity).Name, entity.Id);
            
            throw;
        }
    }

    public override async Task<bool> UpdateRangeAsync(IEnumerable<TEntity> entities, CancellationToken cancellationToken = default)
    {
        if (entities == null || !entities.Any())
        {
            logger.LogWarning("Attempted to update null or empty entity collection of type {EntityType}", typeof(TEntity).Name);
            throw new ArgumentNullException(nameof(entities));
        }

        try
        {
            var now = DateTime.Now;
            foreach (var entity in entities)
            {
                entity.UpdatedAt = now;
            }
            dbSet.UpdateRange(entities);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;

            if (result)
            {
                logger.LogInformation("Successfully updated {Count} entities of type {EntityType}",
                    entities.Count(), typeof(TEntity).Name);
            }

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error batch updating entities of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<bool> DeleteAsync(TEntity entity, CancellationToken cancellationToken = default)
    {
        if (entity == null)
        {
            logger.LogWarning("Attempted to delete null entity of type {EntityType}", typeof(TEntity).Name);
            throw new ArgumentNullException(nameof(entity));
        }

        try
        {
            dbSet.Remove(entity);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;
            
            if (result)
            {
                logger.LogInformation("Successfully deleted entity of type {EntityType} with ID: {Id}", 
                    typeof(TEntity).Name, entity.Id);
            }
            else
            {
                logger.LogWarning("Delete operation for entity of type {EntityType} with ID: {Id} returned false", 
                    typeof(TEntity).Name, entity.Id);
            }
            
            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting entity of type {EntityType} with ID: {Id}", 
                typeof(TEntity).Name, entity.Id);
            throw;
        }
    }

    public override async Task<bool> DeleteByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        try
        {
            var entity = await dbSet.FirstOrDefaultAsync(e => e.Id.Equals(id), cancellationToken);
            if (entity == null)
            {
                logger.LogWarning("Entity of type {EntityType} with ID {Id} not found for deletion", 
                    typeof(TEntity).Name, id);
                throw new NotFoundException(typeof(TEntity).Name, id);
            }

            dbSet.Remove(entity);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;
            
            if (result)
            {
                logger.LogInformation("Successfully deleted entity of type {EntityType} with ID: {Id}", 
                    typeof(TEntity).Name, id);
            }
            else
            {
                logger.LogWarning("Delete operation for entity of type {EntityType} with ID: {Id} returned false", 
                    typeof(TEntity).Name, id);
            }
            
            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting entity of type {EntityType} by ID: {Id}", 
                typeof(TEntity).Name, id);
            throw;
        }
    }
    public override async Task<bool> ExistsAsync(Guid id)
    {
        return await dbSet.FindAsync(id) != null;
    }

    public override async Task<bool> ExistsAsync(Expression<Func<TEntity, bool>> filter, CancellationToken cancellationToken = default)
    {
        return await dbSet.AnyAsync(filter, cancellationToken);
    }

    public async override Task<bool> DeleteAsync(Expression<Func<TEntity, bool>> filter, CancellationToken cancellationToken = default)
    {
        try
        {
            var entities = await dbSet.Where(filter).ToListAsync(cancellationToken);
            
            if (!entities.Any())
            {
                logger.LogWarning("No entities of type {EntityType} found matching the filter for deletion", 
                    typeof(TEntity).Name);
                return false;
            }

            dbSet.RemoveRange(entities);
            var result = await context.SaveChangesAsync(cancellationToken) > 0;
            
            if (result)
            {
                logger.LogInformation("Successfully deleted {Count} entities of type {EntityType}", 
                    entities.Count, typeof(TEntity).Name);
            }
            else
            {
                logger.LogWarning("Delete operation for entities of type {EntityType} returned false", 
                    typeof(TEntity).Name);
            }
            
            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting entities of type {EntityType} with filter", 
                typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<TEntity?> GetLastOrDefaultAsync(
        Expression<Func<TEntity, object>> keySelector,
        Expression<Func<TEntity, bool>>? filter = null, 
        string[]? includeProperties = null, 
        CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (filter != null)
            {
                query = query.Where(filter);
            }

            if (includeProperties != null)
            {
                foreach (var includeProperty in includeProperties)
                {
                    query = query.Include(includeProperty);
                }
            }

            return await query.OrderByDescending(keySelector).FirstOrDefaultAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving last or default entity of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<TEntity?> GetFirstOrDefaultAsync(
        Expression<Func<TEntity, object>> keySelector,
        Expression<Func<TEntity, bool>>? filter = null, 
        string[]? includeProperties = null, 
        CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet.AsNoTracking();

            if (filter != null)
            {
                query = query.Where(filter);
            }

            if (includeProperties != null)
            {
                foreach (var includeProperty in includeProperties)
                {
                    query = query.Include(includeProperty);
                }
            }

            return await query.OrderBy(keySelector).FirstOrDefaultAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving last or default entity of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    public override async Task<int> CountAsync(Expression<Func<TEntity, bool>>? filter = null, CancellationToken cancellationToken = default)
    {
        try
        {
            if (filter != null)
            {
                return await dbSet.CountAsync(filter, cancellationToken);
            }
            else
            {
                return await dbSet.CountAsync(cancellationToken);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error counting entities of type {EntityType}", typeof(TEntity).Name);
            throw;
        }
    }

    /// <summary>
    /// Auto-stamps StoreId on entities that have the property, using the current tenant context.
    /// Only sets StoreId if it's currently null/default and a tenant context is available.
    /// </summary>
    private void StampTenantId(TEntity entity)
    {
        if (tenantProvider.StoreId == null) return;

        var storeIdProp = typeof(TEntity).GetProperty("StoreId");
        if (storeIdProp == null) return;

        var currentValue = storeIdProp.GetValue(entity);
        
        // Only stamp if StoreId is null or default(Guid)
        if (currentValue == null || (currentValue is Guid g && g == Guid.Empty))
        {
            storeIdProp.SetValue(entity, tenantProvider.StoreId);
        }
    }
}