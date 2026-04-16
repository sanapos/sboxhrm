using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Domain.Entities;
using System.Text.Json;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentsForSelect;

public class GetDepartmentsForSelectHandler(
    IRepository<Department> departmentRepository
) : IQueryHandler<GetDepartmentsForSelectQuery, AppResponse<List<DepartmentSelectDto>>>
{
    public async Task<AppResponse<List<DepartmentSelectDto>>> Handle(
        GetDepartmentsForSelectQuery request, 
        CancellationToken cancellationToken)
    {
        try
        {
            var departments = await departmentRepository.GetAllAsync(
                filter: d => d.StoreId == request.StoreId && d.IsActive,
                orderBy: q => q.OrderBy(d => d.Level).ThenBy(d => d.SortOrder).ThenBy(d => d.Name),
                cancellationToken: cancellationToken);

            var dtos = departments.Select(d => new DepartmentSelectDto
            {
                Id = d.Id,
                Code = d.Code,
                Name = d.Name,
                Level = d.Level,
                ParentDepartmentId = d.ParentDepartmentId,
                Positions = !string.IsNullOrEmpty(d.Positions)
                    ? JsonSerializer.Deserialize<List<string>>(d.Positions)
                    : null
            }).ToList();

            return AppResponse<List<DepartmentSelectDto>>.Success(dtos);
        }
        catch (Exception ex)
        {
            return AppResponse<List<DepartmentSelectDto>>.Error($"Lỗi khi lấy danh sách phòng ban: {ex.Message}");
        }
    }
}
