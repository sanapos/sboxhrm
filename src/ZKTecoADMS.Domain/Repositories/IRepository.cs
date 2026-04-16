using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore.Query;

namespace ZKTecoADMS.Domain.Repositories;

public interface IRepository<TEntity>
{
    
    Task<TEntity?> GetLastOrDefaultAsync(
        Expression<Func<TEntity, object>> keySelector,
        Expression<Func<TEntity, bool>>? filter = null,
        string[]? includeProperties = null,
        CancellationToken cancellationToken = default
    );

    Task<TEntity?> GetFirstOrDefaultAsync(
        Expression<Func<TEntity, object>> keySelector,
        Expression<Func<TEntity, bool>>? filter = null,
        string[]? includeProperties = null,
        CancellationToken cancellationToken = default
    );

    Task<List<TEntity>> GetAllAsync(
        Expression<Func<TEntity, bool>>? filter = null,
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null,
        string[]? includeProperties = null,
        int? skip = null,
        int? take = null,
        CancellationToken cancellationToken = default
    );

    Task<List<TEntity>> GetAllWithIncludeAsync(
        Expression<Func<TEntity, bool>>? filter = null,
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null,
        Func<IQueryable<TEntity>, IIncludableQueryable<TEntity, object>>? includes = null,
        int? skip = null,
        int? take = null,
        CancellationToken cancellationToken = default
    );

    Task<TEntity?> GetByIdAsync(
        Guid id,
        string[]? includeProperties = null,
        CancellationToken cancellationToken = default
    );

    Task<TEntity?> GetSingleAsync(
        Expression<Func<TEntity, bool>> filter,
        string[]? includeProperties = null,
        Func<IQueryable<TEntity>, IOrderedQueryable<TEntity>>? orderBy = null,
        CancellationToken cancellationToken = default
    );

    Task<TEntity> AddAsync(TEntity entity, CancellationToken cancellationToken = default);

    Task<bool> AddOrUpdateAsync(TEntity entity, CancellationToken cancellationToken = default);

    Task<bool> AddRangeAsync(IEnumerable<TEntity> entities, CancellationToken cancellationToken = default);

    Task<bool> UpdateAsync(TEntity entity, CancellationToken cancellationToken = default);

    Task<bool> UpdateRangeAsync(IEnumerable<TEntity> entities, CancellationToken cancellationToken = default);

    Task<bool> DeleteAsync(TEntity entity, CancellationToken cancellationToken = default);

    Task<bool> DeleteByIdAsync(Guid id, CancellationToken cancellationToken = default);

    Task<bool> ExistsAsync(Guid id);
    
    Task<bool> ExistsAsync(Expression<Func<TEntity, bool>> filter, CancellationToken cancellationToken = default);
    
    Task<bool> DeleteAsync(Expression<Func<TEntity, bool>> filter, CancellationToken cancellationToken = default);

    Task<int> CountAsync(Expression<Func<TEntity, bool>>? filter = null, CancellationToken cancellationToken = default);
}