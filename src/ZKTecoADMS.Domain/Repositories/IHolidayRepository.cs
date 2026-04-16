using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Domain.Repositories;

public interface IHolidayRepository : IRepository<Holiday>
{
    Task<IEnumerable<Holiday>> GetHolidaysByYearAsync(int year, string? region = null, CancellationToken cancellationToken = default);
    Task<IEnumerable<Holiday>> GetActiveHolidaysByYearAsync(int year, string? region = null, CancellationToken cancellationToken = default);
    Task<bool> IsHolidayAsync(DateTime date, string? region = null, CancellationToken cancellationToken = default);
    Task<Holiday?> GetHolidayByDateAsync(DateTime date, string? region = null, CancellationToken cancellationToken = default);
}
