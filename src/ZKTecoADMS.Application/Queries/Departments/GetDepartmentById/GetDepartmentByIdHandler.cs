using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Domain.Entities;
using System.Text.Json;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentById;

public class GetDepartmentByIdHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetDepartmentByIdQuery, AppResponse<DepartmentDto>>
{
    public async Task<AppResponse<DepartmentDto>> Handle(
        GetDepartmentByIdQuery request, 
        CancellationToken cancellationToken)
    {
        try
        {
            var department = await departmentRepository.GetSingleAsync(
                filter: d => d.Id == request.Id && d.StoreId == request.StoreId,
                includeProperties: [
                    nameof(Department.ParentDepartment),
                    nameof(Department.Manager),
                    nameof(Department.Store)
                ],
                cancellationToken: cancellationToken);

            if (department == null)
            {
                return AppResponse<DepartmentDto>.Error("Phòng ban không tồn tại");
            }

            // Count employees dynamically
            var directCount = await employeeRepository.CountAsync(
                filter: e => e.DepartmentId == department.Id,
                cancellationToken: cancellationToken);

            // Calculate total count including children
            var allChildDepts = await departmentRepository.GetAllAsync(
                filter: d => d.StoreId == request.StoreId && d.IsActive,
                cancellationToken: cancellationToken);
            var childrenLookup = allChildDepts
                .Where(d => d.ParentDepartmentId.HasValue)
                .GroupBy(d => d.ParentDepartmentId!.Value)
                .ToDictionary(g => g.Key, g => g.Select(d => d.Id).ToList());

            var allDeptIds = new List<Guid> { department.Id };
            void CollectChildIds(Guid parentId)
            {
                if (childrenLookup.TryGetValue(parentId, out var childIds))
                {
                    allDeptIds.AddRange(childIds);
                    foreach (var childId in childIds) CollectChildIds(childId);
                }
            }
            CollectChildIds(department.Id);

            var totalCount = await employeeRepository.CountAsync(
                filter: e => e.DepartmentId.HasValue && allDeptIds.Contains(e.DepartmentId.Value),
                cancellationToken: cancellationToken);

            var dto = new DepartmentDto
            {
                Id = department.Id,
                Code = department.Code,
                Name = department.Name,
                Description = department.Description,
                ParentDepartmentId = department.ParentDepartmentId,
                ParentDepartmentName = department.ParentDepartment?.Name,
                ManagerId = department.ManagerId,
                ManagerName = department.Manager != null 
                    ? $"{department.Manager.LastName} {department.Manager.FirstName}" 
                    : null,
                Level = department.Level,
                SortOrder = department.SortOrder,
                StoreId = department.StoreId,
                StoreName = department.Store?.Name,
                HierarchyPath = department.HierarchyPath,
                DirectEmployeeCount = directCount,
                TotalEmployeeCount = totalCount,
                IsActive = department.IsActive,
                CreatedAt = department.CreatedAt,
                UpdatedAt = department.UpdatedAt,
                Positions = !string.IsNullOrEmpty(department.Positions)
                    ? JsonSerializer.Deserialize<List<string>>(department.Positions)
                    : null
            };

            return AppResponse<DepartmentDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<DepartmentDto>.Error($"Lỗi khi lấy thông tin phòng ban: {ex.Message}");
        }
    }
}
