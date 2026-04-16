using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Departments.DeleteDepartment;

public class DeleteDepartmentHandler(
    IRepository<Department> departmentRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteDepartmentCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteDepartmentCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var department = await departmentRepository.GetSingleAsync(
                filter: d => d.Id == request.Id && d.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (department == null)
            {
                return AppResponse<bool>.Error("Phòng ban không tồn tại");
            }

            // Check if there are child departments
            var hasChildren = await departmentRepository.ExistsAsync(
                filter: d => d.ParentDepartmentId == request.Id,
                cancellationToken: cancellationToken);

            if (hasChildren)
            {
                return AppResponse<bool>.Error("Không thể xóa phòng ban có phòng ban con. Vui lòng xóa các phòng ban con trước.");
            }

            // Check if there are employees in this department
            var hasEmployees = await employeeRepository.ExistsAsync(
                filter: e => e.DepartmentId == request.Id,
                cancellationToken: cancellationToken);

            if (hasEmployees)
            {
                return AppResponse<bool>.Error("Không thể xóa phòng ban có nhân viên. Vui lòng chuyển nhân viên sang phòng ban khác trước.");
            }

            var deptName = department.Name;
            var deptCode = department.Code;
            await departmentRepository.DeleteAsync(department, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Warning,
                    title: "Xóa phòng ban",
                    message: $"Phòng ban \"{deptName}\" ({deptCode}) đã bị xóa",
                    relatedEntityType: "Department",
                    categoryCode: "department",
                    storeId: request.StoreId);
            }
            catch { }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi xóa phòng ban: {ex.Message}");
        }
    }
}
