using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Application.Models;

public class PaginationRequest
{
    public int PageNumber { get; set; } = 1;

    public int PageSize { get; set; } = 20;

    public string? SortBy { get; set; } = nameof(Entity<Guid>.CreatedAt);

    public string? SortOrder { get; set; } = "desc";

    /// <summary>False = skip COUNT(*) (dùng khi client đã có totalCount từ trang 1).</summary>
    public bool IncludeTotalCount { get; set; } = true;
}
