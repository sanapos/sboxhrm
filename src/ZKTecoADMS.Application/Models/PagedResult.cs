namespace ZKTecoADMS.Application.Models;

public class PagedResult<T>
{
    public PagedResult()
    {
        Items = [];
    }

    public PagedResult(IEnumerable<T> items, int totalCount, int pageNumber, int pageSize)
    {
        Items = items;
        TotalCount = totalCount;
        PageNumber = pageNumber;
        PageSize = pageSize;
    }

    public PagedResult(IEnumerable<T> items, PagedResult<T> pagedResult)
    {
        Items = items;
        TotalCount = pagedResult.TotalCount;
        PageNumber = pagedResult.PageNumber;
        PageSize = pagedResult.PageSize;
    }

    public IEnumerable<T> Items { get; set; }

    public int TotalCount { get; set; }

    public int PageNumber { get; set; }

    public int PageSize { get; set; }

    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);

    public bool HasPreviousPage => PageNumber > 1;

    public bool HasNextPage => PageNumber < TotalPages;

    public int? PreviousPageNumber => HasPreviousPage ? PageNumber - 1 : null;

    public int? NextPageNumber => HasNextPage ? PageNumber + 1 : null;
}