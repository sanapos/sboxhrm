using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using System.Text.Json;

namespace ZKTecoADMS.Application.Commands.Departments.UpdateDepartment;

public class UpdateDepartmentHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UpdateDepartmentCommand, AppResponse<DepartmentDto>>
{
    public async Task<AppResponse<DepartmentDto>> Handle(UpdateDepartmentCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var department = await departmentRepository.GetSingleAsync(
                filter: d => d.Id == request.Id && d.StoreId == request.StoreId,
                includeProperties: [nameof(Department.ParentDepartment)],
                cancellationToken: cancellationToken);

            if (department == null)
            {
                return AppResponse<DepartmentDto>.Error("Phòng ban không tồn tại");
            }

            // Check if code already exists (excluding current department)
            var existingDepartment = await departmentRepository.GetSingleAsync(
                filter: d => d.Code == request.Code && d.StoreId == request.StoreId && d.Id != request.Id,
                cancellationToken: cancellationToken);

            if (existingDepartment != null)
            {
                return AppResponse<DepartmentDto>.Error($"Mã phòng ban '{request.Code}' đã tồn tại");
            }

            // Prevent setting itself as parent
            if (request.ParentDepartmentId.HasValue && request.ParentDepartmentId.Value == request.Id)
            {
                return AppResponse<DepartmentDto>.Error("Không thể đặt chính phòng ban này làm phòng ban cha");
            }

            // Calculate new level and hierarchy path if parent changed
            int newLevel = 0;
            string newHierarchyPath = "/";
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

                // Check for circular reference
                if (parentDepartment.HierarchyPath?.Contains($"/{request.Id}/") == true)
                {
                    return AppResponse<DepartmentDto>.Error("Không thể tạo vòng lặp trong cấu trúc phòng ban");
                }

                newLevel = parentDepartment.Level + 1;
                newHierarchyPath = $"{parentDepartment.HierarchyPath}{parentDepartment.Id}/";
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

            // Update department
            department.Code = request.Code;
            department.Name = request.Name;
            department.Description = request.Description;
            department.ParentDepartmentId = request.ParentDepartmentId;
            department.ManagerId = request.ManagerId;
            department.Level = newLevel;
            department.SortOrder = request.SortOrder;
            department.HierarchyPath = newHierarchyPath;
            department.IsActive = request.IsActive;
            department.Positions = request.Positions != null && request.Positions.Count > 0
                ? JsonSerializer.Serialize(request.Positions)
                : null;
            department.UpdatedAt = DateTime.UtcNow;

            await departmentRepository.UpdateAsync(department, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Cập nhật phòng ban",
                    message: $"Phòng ban \"{request.Name}\" ({request.Code}) đã được cập nhật",
                    relatedEntityId: department.Id,
                    relatedEntityType: "Department",
                    categoryCode: "department",
                    storeId: request.StoreId);
            }
            catch { }

            // If hierarchy changed, update all children
            if (department.ParentDepartmentId != request.ParentDepartmentId)
            {
                await UpdateChildrenHierarchy(department, cancellationToken);
            }

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
                UpdatedAt = department.UpdatedAt,
                Positions = !string.IsNullOrEmpty(department.Positions)
                    ? JsonSerializer.Deserialize<List<string>>(department.Positions)
                    : null
            };

            return AppResponse<DepartmentDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<DepartmentDto>.Error($"Lỗi khi cập nhật phòng ban: {ex.Message}");
        }
    }

    private async Task UpdateChildrenHierarchy(Department parent, CancellationToken cancellationToken)
    {
        var children = await departmentRepository.GetAllAsync(
            filter: d => d.ParentDepartmentId == parent.Id,
            cancellationToken: cancellationToken);

        foreach (var child in children)
        {
            child.Level = parent.Level + 1;
            child.HierarchyPath = $"{parent.HierarchyPath}{parent.Id}/";
            child.UpdatedAt = DateTime.UtcNow;
            await departmentRepository.UpdateAsync(child, cancellationToken);

            // Recursively update children
            await UpdateChildrenHierarchy(child, cancellationToken);
        }
    }
}
