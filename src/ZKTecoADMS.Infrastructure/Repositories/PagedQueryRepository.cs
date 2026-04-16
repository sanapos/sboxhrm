using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Query;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Infrastructure.Repositories;

public class PagedQueryRepository<TEntity>(
    ZKTecoDbContext context, 
    ILogger<EfRepository<TEntity>> logger,
    ITenantProvider tenantProvider
    ) : EfRepository<TEntity>(context, logger, tenantProvider), IRepositoryPagedQuery<TEntity> where TEntity : Entity<Guid>
{
    public async Task<PagedResult<TEntity>> GetPagedResultAsync(
        PaginationRequest request,
        Expression<Func<TEntity, bool>>? filter = null,
        string[]? includeProperties = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet;

            // Apply filter
            if (filter != null)
            {
                query = query.Where(filter);
            }

            // Get total count before pagination
            var totalCount = await query.CountAsync(cancellationToken);

            // Apply includes
            if (includeProperties != null)
            {
                query = includeProperties.Aggregate(query, (current, includeProperty) => current.Include(includeProperty));
            }

            // Apply ordering based on PaginationRequest.SortBy and SortOrder
            if (!string.IsNullOrWhiteSpace(request.SortBy))
            {
                var sortBy = request.SortBy.Substring(0, 1).ToUpper() + request.SortBy.Substring(1);
                var prop = typeof(TEntity).GetProperty(sortBy);
                if(prop == null)
                {
                    logger.LogWarning("SortBy '{SortBy}' is not a valid property of {EntityType}. Falling back to Created desc.", request.SortBy, typeof(TEntity).Name);
                    throw new InvalidOperationException($"SortBy '{sortBy}' is not a valid property of {typeof(TEntity).Name}");
                }
                var parameter = Expression.Parameter(typeof(TEntity), "x");
                var property = Expression.Property(parameter, prop);
                var lambda = Expression.Lambda(property, parameter);

                var methodName = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? "OrderBy"
                    : "OrderByDescending";

                var resultExpression = Expression.Call(
                    typeof(Queryable),
                    methodName,
                    [typeof(TEntity), prop.PropertyType],
                    query.Expression,
                    Expression.Quote(lambda)
                );

                query = query.Provider.CreateQuery<TEntity>(resultExpression);
  
            }
            else
            {
                // Default ordering by Created if no SortBy is provided
                query = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? query.OrderBy(e => e.CreatedAt)
                    : query.OrderByDescending(e => e.CreatedAt);
            }

            // Apply pagination
            var items = await query
                .Skip((request.PageNumber - 1) * request.PageSize)
                .Take(request.PageSize)
                .ToListAsync(cancellationToken);

            var result = new PagedResult<TEntity>
            {
                Items = items,
                TotalCount = totalCount,
                PageNumber = request.PageNumber,
                PageSize = request.PageSize
            };

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving paged entities of type {EntityType} - Page: {PageNumber}, Size: {PageSize}",
                typeof(TEntity).Name, request.PageNumber, request.PageSize);
            throw;
        }
    }

    public async Task<PagedResult<TEntity>> GetPagedResultWithIncludesAsync(
        PaginationRequest request, 
        Expression<Func<TEntity, bool>>? filter = null, 
        Func<IQueryable<TEntity>, IIncludableQueryable<TEntity, object>>? includes = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            IQueryable<TEntity> query = dbSet;

            // Apply filter
            if (filter != null)
            {
                query = query.Where(filter);
            }

            // Apply includes using the fluent API
            if (includes != null)
            {
                query = includes(query);
            }

            // Get total count after filter but before pagination
            var totalCount = await query.CountAsync(cancellationToken);

            // Apply ordering based on PaginationRequest.SortBy and SortOrder
            if (!string.IsNullOrWhiteSpace(request.SortBy))
            {
                var sortBy = request.SortBy.Substring(0, 1).ToUpper() + request.SortBy.Substring(1);

                var prop = typeof(TEntity).GetProperty(sortBy);
                if (prop == null)
                {
                    logger.LogWarning("SortBy '{SortBy}' is not a valid property of {EntityType}. Falling back to Created desc.", 
                        request.SortBy, typeof(TEntity).Name);
                    throw new InvalidOperationException($"SortBy '{sortBy}' is not a valid property of {typeof(TEntity).Name}");
                }
                
                var parameter = Expression.Parameter(typeof(TEntity), "x");
                var property = Expression.Property(parameter, prop);
                var lambda = Expression.Lambda(property, parameter);

                var methodName = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? "OrderBy"
                    : "OrderByDescending";

                var resultExpression = Expression.Call(
                    typeof(Queryable),
                    methodName,
                    [typeof(TEntity), prop.PropertyType],
                    query.Expression,
                    Expression.Quote(lambda)
                );

                query = query.Provider.CreateQuery<TEntity>(resultExpression);
            }
            else
            {
                // Default ordering by Created if no SortBy is provided
                query = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? query.OrderBy(e => e.CreatedAt)
                    : query.OrderByDescending(e => e.CreatedAt);
            }

            // Apply pagination
            var items = await query
                .Skip((request.PageNumber - 1) * request.PageSize)
                .Take(request.PageSize)
                .ToListAsync(cancellationToken);

            var result = new PagedResult<TEntity>
            {
                Items = items,
                TotalCount = totalCount,
                PageNumber = request.PageNumber,
                PageSize = request.PageSize
            };

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving paged entities of type {EntityType} with includes - Page: {PageNumber}, Size: {PageSize}",
                typeof(TEntity).Name, request.PageNumber, request.PageSize);
            throw;
        }
    }

    public async Task<PagedResult<TProjection>> GetPagedResultWithProjectionAsync<TProjection>(
        PaginationRequest request,
        Expression<Func<TEntity, bool>>? filter = null,
        Expression<Func<TEntity, TProjection>>? projection = null,
        CancellationToken cancellationToken = default) where TProjection : class
    {
        try
        {
            IQueryable<TEntity> query = dbSet;

            // Apply filter
            if (filter != null)
            {
                query = query.Where(filter);
            }

            // Get total count after filter but before projection
            var totalCount = await query.CountAsync(cancellationToken);

            // Apply ordering based on PaginationRequest.SortBy and SortOrder
            if (!string.IsNullOrWhiteSpace(request.SortBy))
            {
                var sortBy = request.SortBy.Substring(0, 1).ToUpper() + request.SortBy.Substring(1);
    
                var prop = typeof(TEntity).GetProperty(sortBy);

                if (prop == null)
                {
                    logger.LogWarning("SortBy '{SortBy}' is not a valid property of {EntityType}. Falling back to Created desc.",
                        request.SortBy, typeof(TEntity).Name);
                    throw new InvalidOperationException($"SortBy '{sortBy}' is not a valid property of {typeof(TEntity).Name}");
                }

                var parameter = Expression.Parameter(typeof(TEntity), "x");
                var property = Expression.Property(parameter, prop);
                var lambda = Expression.Lambda(property, parameter);

                var methodName = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? "OrderBy"
                    : "OrderByDescending";

                var resultExpression = Expression.Call(
                    typeof(Queryable),
                    methodName,
                    [typeof(TEntity), prop.PropertyType],
                    query.Expression,
                    Expression.Quote(lambda)
                );

                query = query.Provider.CreateQuery<TEntity>(resultExpression);
            }
            else
            {
                // Default ordering by Created if no SortBy is provided
                query = string.Equals(request.SortOrder, "asc", StringComparison.OrdinalIgnoreCase)
                    ? query.OrderBy(e => e.CreatedAt)
                    : query.OrderByDescending(e => e.CreatedAt);
            }

            // Apply projection
            IQueryable<TProjection> projectedQuery;
            if (projection != null)
            {
                projectedQuery = query.Select(projection);
            }
            else
            {
                throw new InvalidOperationException("Projection expression is required for GetPagedResultWithProjectionAsync");
            }

            // Apply pagination
            var items = await projectedQuery
                .Skip((request.PageNumber - 1) * request.PageSize)
                .Take(request.PageSize)
                .ToListAsync(cancellationToken);

            var result = new PagedResult<TProjection>
            {
                Items = items,
                TotalCount = totalCount,
                PageNumber = request.PageNumber,
                PageSize = request.PageSize
            };

            return result;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving paged entities of type {EntityType} with projection - Page: {PageNumber}, Size: {PageSize}",
                typeof(TEntity).Name, request.PageNumber, request.PageSize);
            throw;
        }
    }
} 