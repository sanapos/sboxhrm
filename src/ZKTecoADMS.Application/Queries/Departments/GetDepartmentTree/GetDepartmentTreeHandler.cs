using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Queries.Departments.GetDepartmentTree;

public class GetDepartmentTreeHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetDepartmentTreeQuery, AppResponse<List<DepartmentTreeNodeDto>>>
{
    public async Task<AppResponse<List<DepartmentTreeNodeDto>>> Handle(
        GetDepartmentTreeQuery request, 
        CancellationToken cancellationToken)
    {
        try
        {
            // Get all departments for the store
            var allDepartments = await departmentRepository.GetAllWithIncludeAsync(
                filter: d => d.StoreId == request.StoreId 
                    && (request.IncludeInactive || d.IsActive),
                orderBy: q => q.OrderBy(d => d.Level).ThenBy(d => d.SortOrder).ThenBy(d => d.Name),
                includes: q => q.Include(d => d.Manager)!,
                cancellationToken: cancellationToken);

            // Count employees per department dynamically
            var departmentIds = allDepartments.Select(d => d.Id).ToList();
            var allEmployees = await employeeRepository.GetAllAsync(
                filter: e => e.DepartmentId.HasValue && departmentIds.Contains(e.DepartmentId.Value),
                cancellationToken: cancellationToken);
            var employeeCountByDept = allEmployees
                .GroupBy(e => e.DepartmentId!.Value)
                .ToDictionary(g => g.Key, g => g.Count());

            // Build tree structure
            var departmentLookup = allDepartments.ToDictionary(d => d.Id);
            var rootDepartments = new List<DepartmentTreeNodeDto>();

            foreach (var dept in allDepartments.Where(d => d.ParentDepartmentId == null))
            {
                var node = BuildTreeNode(dept, departmentLookup, employeeCountByDept);
                rootDepartments.Add(node);
            }

            return AppResponse<List<DepartmentTreeNodeDto>>.Success(rootDepartments);
        }
        catch (Exception ex)
        {
            return AppResponse<List<DepartmentTreeNodeDto>>.Error($"Lỗi khi lấy cây phòng ban: {ex.Message}");
        }
    }

    private DepartmentTreeNodeDto BuildTreeNode(
        Department department, 
        Dictionary<Guid, Department> lookup,
        Dictionary<Guid, int> employeeCountByDept)
    {
        var children = lookup.Values
            .Where(d => d.ParentDepartmentId == department.Id)
            .OrderBy(d => d.SortOrder)
            .ThenBy(d => d.Name)
            .Select(child => BuildTreeNode(child, lookup, employeeCountByDept))
            .ToList();

        var directCount = employeeCountByDept.GetValueOrDefault(department.Id, 0);
        var totalCount = directCount + children.Sum(c => c.TotalEmployeeCount);

        return new DepartmentTreeNodeDto
        {
            Id = department.Id,
            Code = department.Code,
            Name = department.Name,
            ParentDepartmentId = department.ParentDepartmentId,
            ManagerId = department.ManagerId,
            ManagerName = department.Manager != null 
                ? $"{department.Manager.LastName} {department.Manager.FirstName}" 
                : null,
            Level = department.Level,
            SortOrder = department.SortOrder,
            DirectEmployeeCount = directCount,
            TotalEmployeeCount = totalCount,
            IsActive = department.IsActive,
            HasChildren = children.Any(),
            IsExpanded = false,
            Children = children
        };
    }
}
