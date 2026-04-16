using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;
using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Benefits.AssignEmployee;

public class AssignBenefitHandler(
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<Benefit> benefitRepository,
    IRepository<Employee> employeeRepository,
    BenefitAssignmentStrategyFactory strategyFactory,
    ISystemNotificationService notificationService,
    UserManager<ApplicationUser> userManager) 
    : ICommandHandler<AssignBenefitCommand, AppResponse<EmployeeBenefitDto>>
{
    public async Task<AppResponse<EmployeeBenefitDto>> Handle(AssignBenefitCommand request, CancellationToken cancellationToken)
    {
        // Validate employee exists
        var employee = await employeeRepository.GetByIdAsync(request.EmployeeId, cancellationToken: cancellationToken);
        if (employee == null)
        {
            return AppResponse<EmployeeBenefitDto>.Error("Employee not found");
        }

        // Validate benefit exists
        var benefit = await benefitRepository.GetByIdAsync(request.BenefitId, cancellationToken: cancellationToken);
        if (benefit == null)
        {
            return AppResponse<EmployeeBenefitDto>.Error("Benefit not found");
        }

        if (!benefit.IsActive)
        {
            return AppResponse<EmployeeBenefitDto>.Error("Benefit is not active");
        }

        // Sync employee's EmploymentType with the benefit's RateType
        // EmploymentType only has Hourly(0) and Monthly(1), map Daily/Shift to Monthly
        var targetEmploymentType = (int)benefit.RateType <= 1 
            ? (EmploymentType)(int)benefit.RateType 
            : EmploymentType.Monthly;
        if (employee.EmploymentType != targetEmploymentType)
        {
            employee.EmploymentType = targetEmploymentType;
            await employeeRepository.UpdateAsync(employee, cancellationToken);
        }

        // Get the appropriate strategy for the benefit type
        var strategy = strategyFactory.GetStrategy(benefit.RateType);
        
        // Validate the assignment using the strategy
        var (isValid, errorMessage) = await strategy.ValidateAssignmentAsync(benefit, employee, cancellationToken);
        if (!isValid)
        {
            return AppResponse<EmployeeBenefitDto>.Error(errorMessage ?? "Validation failed");
        }

        var employeeBenefit = await strategy.ConfigEmployeeBenefitAsync(benefit, employee);
        if (employeeBenefit == null)
        {
            return AppResponse<EmployeeBenefitDto>.Error("Failed to configure employee benefit");
        }

        employeeBenefit.EffectiveDate = request.EffectiveDate;
        employeeBenefit.Notes = request.Notes;

        await employeeBenefitRepository.AddAsync(employeeBenefit, cancellationToken);

        var othersEmployeeBenefits = await employeeBenefitRepository.GetAllAsync(
            eb => eb.EmployeeId == request.EmployeeId && eb.Id != employeeBenefit.Id && eb.IsActive,
            cancellationToken: cancellationToken
        );

        // Deactivate other active benefits
        foreach (var otherBenefit in othersEmployeeBenefits)
        {
            otherBenefit.IsActive = false;
            otherBenefit.EndDate = DateTime.Now;
            
            await employeeBenefitRepository.UpdateAsync(otherBenefit, cancellationToken);
        }

        // Send notification to employee and admins
        try
        {
            var employeeName = $"{employee.LastName} {employee.FirstName}".Trim();
            var rateTypeNames = new Dictionary<SalaryRateType, string>
            {
                { SalaryRateType.Hourly, "theo giờ" },
                { SalaryRateType.Monthly, "tháng" },
                { SalaryRateType.Daily, "ngày" },
                { SalaryRateType.Shift, "theo ca" }
            };
            var rateTypeName = rateTypeNames.GetValueOrDefault(benefit.RateType, "");

            // Notify the employee
            if (employee.ApplicationUserId.HasValue)
            {
                await notificationService.CreateAndSendAsync(
                    employee.ApplicationUserId.Value, NotificationType.Info,
                    "Thiết lập lương mới",
                    $"Bạn đã được thiết lập bảng lương {rateTypeName} với mức {benefit.Rate:N0}đ",
                    relatedEntityId: benefit.Id, relatedEntityType: "Benefit",
                    fromUserId: null, categoryCode: "employee", storeId: employee.StoreId);
            }

            // Notify admins
            var admins = await userManager.GetUsersInRoleAsync(nameof(Roles.Admin));
            var adminIds = admins
                .Where(u => u.StoreId == employee.StoreId && u.Id != employee.ApplicationUserId)
                .Select(u => u.Id).Distinct().ToList();
            if (adminIds.Count > 0)
            {
                await notificationService.CreateAndSendToUsersAsync(
                    adminIds, NotificationType.Info,
                    "Thiết lập lương nhân viên",
                    $"Đã thiết lập bảng lương {rateTypeName} cho {employeeName} - {benefit.Rate:N0}đ",
                    relatedEntityId: benefit.Id, relatedEntityType: "Benefit",
                    fromUserId: null, categoryCode: "employee", storeId: employee.StoreId);
            }
        }
        catch { /* Don't fail the operation if notification fails */ }

        return AppResponse<EmployeeBenefitDto>.Success(employeeBenefit.Adapt<EmployeeBenefitDto>());
    }
}
