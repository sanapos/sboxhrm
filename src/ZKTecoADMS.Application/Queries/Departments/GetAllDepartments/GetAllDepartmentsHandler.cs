using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Domain.Entities;
using System.Text.Json;

namespace ZKTecoADMS.Application.Queries.Departments.GetAllDepartments;

public class GetAllDepartmentsHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetAllDepartmentsQuery, AppResponse<PagedResult<DepartmentDto>>>
{
    public async Task<AppResponse<PagedResult<DepartmentDto>>> Handle(
        GetAllDepartmentsQuery request, 
        CancellationToken cancellationToken)
    {
        try
        {
            var departments = await departmentRepository.GetAllWithIncludeAsync(
                filter: d => d.StoreId == request.StoreId
                    && (string.IsNullOrEmpty(request.SearchTerm) || 
                        d.Name.Contains(request.SearchTerm) || 
                        d.Code.Contains(request.SearchTerm))
                    && (!request.IsActive.HasValue || d.IsActive == request.IsActive.Value),
                orderBy: q => q.OrderBy(d => d.Level).ThenBy(d => d.SortOrder).ThenBy(d => d.Name),
                includes: q => q
                    .Include(d => d.ParentDepartment)
                    .Include(d => d.Manager)
                    .Include(d => d.Store)!,
                skip: (request.PaginationRequest.PageNumber - 1) * request.PaginationRequest.PageSize,
                take: request.PaginationRequest.PageSize,
                cancellationToken: cancellationToken);

            var totalCount = await departmentRepository.CountAsync(
                filter: d => d.StoreId == request.StoreId
                    && (string.IsNullOrEmpty(request.SearchTerm) || 
                        d.Name.Contains(request.SearchTerm) || 
                        d.Code.Contains(request.SearchTerm))
                    && (!request.IsActive.HasValue || d.IsActive == request.IsActive.Value),
                cancellationToken: cancellationToken);

            // Count employees per department dynamically
            var departmentIds = departments.Select(d => d.Id).ToList();
            var employees = await employeeRepository.GetAllAsync(
                filter: e => e.DepartmentId.HasValue && departmentIds.Contains(e.DepartmentId.Value),
                cancellationToken: cancellationToken);
            var employeeCountByDept = employees
                .GroupBy(e => e.DepartmentId!.Value)
                .ToDictionary(g => g.Key, g => g.Count());

            // Build a set of all department IDs in store for calculating total counts
            var allStoreDepts = await departmentRepository.GetAllAsync(
                filter: d => d.StoreId == request.StoreId && d.IsActive,
                cancellationToken: cancellationToken);
            var allStoreDeptIds = allStoreDepts.Select(d => d.Id).ToList();
            var allStoreEmployees = await employeeRepository.GetAllAsync(
                filter: e => e.DepartmentId.HasValue && allStoreDeptIds.Contains(e.DepartmentId.Value),
                cancellationToken: cancellationToken);
            var allEmployeeCountByDept = allStoreEmployees
                .GroupBy(e => e.DepartmentId!.Value)
                .ToDictionary(g => g.Key, g => g.Count());

            // Build parent-child lookup for total count calculation
            var childrenLookup = allStoreDepts
                .Where(d => d.ParentDepartmentId.HasValue)
                .GroupBy(d => d.ParentDepartmentId!.Value)
                .ToDictionary(g => g.Key, g => g.Select(d => d.Id).ToList());

            int GetTotalCount(Guid deptId)
            {
                var direct = allEmployeeCountByDept.GetValueOrDefault(deptId, 0);
                if (childrenLookup.TryGetValue(deptId, out var childIds))
                {
                    direct += childIds.Sum(GetTotalCount);
                }
                return direct;
            }

            var dtos = departments.Select(d => new DepartmentDto
            {
                Id = d.Id,
                Code = d.Code,
                Name = d.Name,
                Description = d.Description,
                ParentDepartmentId = d.ParentDepartmentId,
                ParentDepartmentName = d.ParentDepartment?.Name,
                ManagerId = d.ManagerId,
                ManagerName = d.Manager != null ? $"{d.Manager.LastName} {d.Manager.FirstName}" : null,
                Level = d.Level,
                SortOrder = d.SortOrder,
                StoreId = d.StoreId,
                StoreName = d.Store?.Name,
                HierarchyPath = d.HierarchyPath,
                DirectEmployeeCount = employeeCountByDept.GetValueOrDefault(d.Id, 0),
                TotalEmployeeCount = GetTotalCount(d.Id),
                IsActive = d.IsActive,
                CreatedAt = d.CreatedAt,
                UpdatedAt = d.UpdatedAt,
                Positions = !string.IsNullOrEmpty(d.Positions)
                    ? JsonSerializer.Deserialize<List<string>>(d.Positions)
                    : null
            }).ToList();

            var pagedResult = new PagedResult<DepartmentDto>(
                dtos,
                totalCount,
                request.PaginationRequest.PageNumber,
                request.PaginationRequest.PageSize);

            return AppResponse<PagedResult<DepartmentDto>>.Success(pagedResult);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<DepartmentDto>>.Error($"Lỗi khi lấy danh sách phòng ban: {ex.Message}");
        }
    }
}
