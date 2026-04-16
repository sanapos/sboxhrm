namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Provides the current tenant (store) context for the request.
/// Used by EF Global Query Filters and repository to enforce data isolation.
/// </summary>
public interface ITenantProvider
{
    /// <summary>
    /// The current store/tenant ID. Null if user is SuperAdmin or no tenant context (e.g. background service).
    /// </summary>
    Guid? StoreId { get; }
    
    /// <summary>
    /// Whether the current user can access all tenants (SuperAdmin/Agent).
    /// When true, global query filters are bypassed.
    /// </summary>
    bool IsSuperAccess { get; }
}
