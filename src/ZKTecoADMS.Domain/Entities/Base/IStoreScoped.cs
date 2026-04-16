namespace ZKTecoADMS.Domain.Entities.Base;

/// <summary>
/// Marker interface for entities that belong to a specific store (tenant).
/// Entities implementing this interface will have automatic EF Global Query Filters
/// applied to enforce tenant data isolation.
/// </summary>
public interface IStoreScoped
{
    Guid? StoreId { get; set; }
}
