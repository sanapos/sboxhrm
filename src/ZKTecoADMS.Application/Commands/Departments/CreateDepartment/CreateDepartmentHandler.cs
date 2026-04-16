using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using System.Text.Json;

namespace ZKTecoADMS.Application.Commands.Departments.CreateDepartment;

public class CreateDepartmentHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateDepartmentCommand, AppResponse<DepartmentDto>>
{
    public async Task<AppResponse<DepartmentDto>> Handle(CreateDepartmentCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Check if code already exists in the same store
            var existingDepartment = await departmentRepository.GetSingleAsync(
                filter: d => d.Code == request.Code && d.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (existingDepartment != null)
            {
                return AppResponse<DepartmentDto>.Error($"Mã phòng ban '{request.Code}' đã tồn tại");
            }

            // Calculate level and hierarchy path
            int level = 0;
            string hierarchyPath = "/";
            Department? parentDepartment = null;

            if (request.ParentDepartmentId.HasValue)
            {
                parentDepartment = await departmentRepository.GetByIdAsync(
                    request.ParentDepartmentId.Value,
                    cancellationToken: cancellationToken);

                if (parentDepartment == null)
                {
                    return AppResponse<DepartmentDto>.Error("Phòng ban cha không tồn tại");
                }

                level = parentDepartment.Level + 1;
                hierarchyPath = $"{parentDepartment.HierarchyPath}{parentDepartment.Id}/";
            }

            // Get manager name if provided
            string? managerName = null;
            if (request.ManagerId.HasValue)
            {
                var manager = await employeeRepository.GetByIdAsync(
                    request.ManagerId.Value,
                    cancellationToken: cancellationToken);

                if (manager != null)
                {
                    managerName = $"{manager.LastName} {manager.FirstName}";
                }
            }

            var department = new Department
            {
                Id = Guid.NewGuid(),
                Code = request.Code,
                Name = request.Name,
                Description = request.Description,
                ParentDepartmentId = request.ParentDepartmentId,
                ManagerId = request.ManagerId,
                Level = level,
                SortOrder = request.SortOrder,
                StoreId = request.StoreId,
                HierarchyPath = hierarchyPath,
                IsActive = true,
                DirectEmployeeCount = 0,
                TotalEmployeeCount = 0,
                Positions = request.Positions != null && request.Positions.Count > 0
                    ? JsonSerializer.Serialize(request.Positions)
                    : null,
                CreatedAt = DateTime.UtcNow
            };

            await departmentRepository.AddAsync(department, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Phòng ban mới",
                    message: $"Đã tạo phòng ban \"{request.Name}\" ({request.Code})",
                    relatedEntityId: department.Id,
                    relatedEntityType: "Department",
                    categoryCode: "department",
                    storeId: request.StoreId);
            }
            catch { }

            var dto = new DepartmentDto
            {
                Id = department.Id,
                Code = department.Code,
                Name = department.Name,
                Description = department.Description,
                ParentDepartmentId = department.ParentDepartmentId,
                ParentDepartmentName = parentDepartment?.Name,
                ManagerId = department.ManagerId,
                ManagerName = managerName,
                Level = department.Level,
                SortOrder = department.SortOrder,
                StoreId = department.StoreId,
                HierarchyPath = department.HierarchyPath,
                DirectEmployeeCount = department.DirectEmployeeCount,
                TotalEmployeeCount = department.TotalEmployeeCount,
                IsActive = department.IsActive,
                CreatedAt = department.CreatedAt,
                Positions = !string.IsNullOrEmpty(department.Positions)
                    ? JsonSerializer.Deserialize<List<string>>(department.Positions)
                    : null
            };

            return AppResponse<DepartmentDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<DepartmentDto>.Error($"Lỗi khi tạo phòng ban: {ex.Message}");
        }
    }
}
