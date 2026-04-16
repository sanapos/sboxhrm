using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Repositories;
using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore.Query;

namespace ZKTecoADMS.Application.Interfaces
{
    public interface IRepositoryPagedQuery<TEntity> : IRepository<TEntity> where TEntity : Entity<Guid>
    {
        Task<PagedResult<TEntity>> GetPagedResultAsync(
            PaginationRequest request,
            Expression<Func<TEntity, bool>>? filter = null,
            string[]? includeProperties = null,
            CancellationToken cancellationToken = default
        );

        Task<PagedResult<TEntity>> GetPagedResultWithIncludesAsync(
            PaginationRequest request,
            Expression<Func<TEntity, bool>>? filter = null,
            Func<IQueryable<TEntity>, IIncludableQueryable<TEntity, object>>? includes = null,
            CancellationToken cancellationToken = default
        );

        Task<PagedResult<TProjection>> GetPagedResultWithProjectionAsync<TProjection>(
            PaginationRequest request,
            Expression<Func<TEntity, bool>>? filter = null,
            Expression<Func<TEntity, TProjection>>? projection = null,
            CancellationToken cancellationToken = default
        ) where TProjection : class;
    }
}
