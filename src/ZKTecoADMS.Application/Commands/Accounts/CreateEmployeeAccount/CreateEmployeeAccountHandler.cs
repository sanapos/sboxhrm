using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Accounts;
public class CreateEmployeeAccountHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateEmployeeAccountCommand, AppResponse<AccountDto>>
{
    public async Task<AppResponse<AccountDto>> Handle(CreateEmployeeAccountCommand request, CancellationToken cancellationToken)
    {
        if (!request.EmployeeId.HasValue)
        {
            return AppResponse<AccountDto>.Error("EmployeeId is required to create an employee account.");
        }
        // Validate manager exists if ManagerId is provided
        var manager = await userManager.FindByIdAsync(request.ManagerId.ToString());
        if (manager == null)
        {
            return AppResponse<AccountDto>.Error("Manager not found.");
        }

        // Optionally: Verify the manager has at least Manager role
        var isManager = await userManager.IsInRoleAsync(manager, nameof(Roles.Manager));
        var isAdmin = await userManager.IsInRoleAsync(manager, nameof(Roles.Admin));
        if (!isManager && !isAdmin)
        {
            return AppResponse<AccountDto>.Error("The specified user is not a manager or admin.");
        }

        var employee = await employeeRepository.GetByIdAsync(request.EmployeeId.Value);
        
        if(employee == null)
        {
            return AppResponse<AccountDto>.Error("Employee not found.");
        }

        var newUser = new ApplicationUser
        {
            UserName = request.UserName,
            Email = request.Email,
            FirstName = request.FirstName,
            LastName = request.LastName,
            PhoneNumber = request.PhoneNumber,
            CreatedAt = DateTime.Now,
            EmailConfirmed = true,
            PhoneNumberConfirmed = true,
            ManagerId  = request.ManagerId,
            StoreId = manager.StoreId,
            Role = request.Role ?? nameof(Roles.Employee)
        };

        var result = await userManager.CreateAsync(newUser, request.Password);

        if (!result.Succeeded)
        {
            return AppResponse<AccountDto>.Error(result.Errors.Select(e => e.Description).ToList());
        }

        var roleName = request.Role ?? nameof(Roles.Employee);
        if (!Enum.TryParse<Roles>(roleName, ignoreCase: true, out _))
        {
            return AppResponse<AccountDto>.Error($"Vai trò '{roleName}' không hợp lệ.");
        }
        var roleResult = await userManager.AddToRoleAsync(newUser, roleName);
        if (!roleResult.Succeeded)
        {
            return AppResponse<AccountDto>.Error(roleResult.Errors.Select(e => e.Description).ToList());
        }

        employee.ApplicationUserId = newUser.Id;
        await employeeRepository.UpdateAsync(employee);

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: newUser.Id,
                type: NotificationType.Success,
                title: "Tài khoản đã tạo",
                message: $"Tài khoản {newUser.UserName} ({request.FirstName} {request.LastName}) đã được tạo thành công",
                relatedEntityId: newUser.Id,
                relatedEntityType: "Account",
                categoryCode: "account",
                storeId: manager.StoreId);
        }
        catch { }

        return AppResponse<AccountDto>.Success(new AccountDto
        {
            Id = newUser.Id,
            Email = request.Email,
            UserName = newUser.UserName!,
            FirstName = request.FirstName,
            LastName = request.LastName,
            PhoneNumber = request.PhoneNumber,
            ManagerId = request.ManagerId,
            EmployeeId = request.EmployeeId,
            ManagerName = manager.GetFullName(),
            Roles = [request.Role ?? nameof(Roles.Employee)],
            CreatedAt = newUser.CreatedAt
        });
    }
}