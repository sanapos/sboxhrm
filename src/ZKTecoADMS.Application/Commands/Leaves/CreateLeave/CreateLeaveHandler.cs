using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.CreateLeave;

public class CreateLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<LeaveApprovalRecord> approvalRecordRepository,
    IRepository<Employee> employeeRepository,
    IRepository<Department> departmentRepository,
    IRepository<AppSettings> appSettingsRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService,
    ILogger<CreateLeaveHandler> logger,
    DbContext dbContext
    ) : ICommandHandler<CreateLeaveCommand, AppResponse<LeaveDto>>
{
    public async Task<AppResponse<LeaveDto>> Handle(CreateLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            if (request.StartDate > request.EndDate)
            {
                return AppResponse<LeaveDto>.Error("Ngày bắt đầu phải trước ngày kết thúc");
            }

            if (request.ShiftId == Guid.Empty)
            {
                return AppResponse<LeaveDto>.Error("Vui lòng chọn ca làm việc");
            }

            var shiftTemplate = await shiftTemplateRepository.GetSingleAsync(
                filter: s => s.Id == request.ShiftId && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (shiftTemplate == null)
            {
                return AppResponse<LeaveDto>.Error("Ca làm việc không hợp lệ hoặc không tồn tại");
            }
            if (!shiftTemplate.IsActive)
            {
                return AppResponse<LeaveDto>.Error("Ca làm việc đã bị vô hiệu hóa, không thể tạo đơn nghỉ phép");
            }

            var overlapping = await leaveRepository.GetAllAsync(
                filter: l => l.EmployeeUserId == request.EmployeeUserId &&
                             l.StoreId == request.StoreId &&
                             l.Status != LeaveStatus.Rejected &&
                             l.StartDate <= request.EndDate &&
                             l.EndDate >= request.StartDate,
                cancellationToken: cancellationToken);

            if (overlapping != null && overlapping.Any())
            {
                return AppResponse<LeaveDto>.Error(
                    "Đã có đơn nghỉ phép trùng lịch trong khoảng thời gian này. " +
                    "Vui lòng chọn ngày khác hoặc hủy đơn cũ.");
            }

            // Read approval levels from settings
            int totalLevels = 1;
            try
            {
                var setting = await appSettingsRepository.GetSingleAsync(
                    s => s.StoreId == request.StoreId && s.Key == "leave_approval_levels",
                    cancellationToken: cancellationToken);
                if (setting != null && int.TryParse(setting.Value, out var lvl) && lvl >= 1)
                    totalLevels = lvl;
            }
            catch { /* fallback to 1 */ }

            var shiftIds = request.ShiftIds != null && request.ShiftIds.Count > 0
                ? new List<Guid>(request.ShiftIds)
                : new List<Guid> { shiftTemplate.Id };

            logger.LogWarning("[CreateLeave] request.ShiftIds={ReqShiftIds}, resolved shiftIds={ShiftIds}",
                request.ShiftIds != null ? string.Join(",", request.ShiftIds) : "null",
                string.Join(",", shiftIds));

            var leave = new Leave
            {
                EmployeeUserId = request.EmployeeUserId,
                ManagerId = request.ManagerId,
                Type = request.Type,
                ShiftId = shiftTemplate.Id,
                ShiftIds = shiftIds,
                StartDate = request.StartDate,
                EndDate = request.EndDate,
                IsHalfShift = request.IsHalfShift,
                Reason = request.Reason ?? string.Empty,
                Status = LeaveStatus.Pending,
                StoreId = request.StoreId,
                ReplacementEmployeeId = request.ReplacementEmployeeId,
                EmployeeId = request.EmployeeId,
                TotalApprovalLevels = totalLevels,
                CurrentApprovalStep = 0,
            };

            logger.LogWarning("[CreateLeave] Before AddAsync: leave.ShiftIds.Count={Count}, values={Values}",
                leave.ShiftIds.Count, string.Join(",", leave.ShiftIds));

            var createdLeave = await leaveRepository.AddAsync(leave, cancellationToken);

            // Force update ShiftIds via raw SQL (workaround for EF Core/Npgsql array issue)
            if (shiftIds.Count > 0)
            {
                var shiftIdsArray = shiftIds.ToArray();
                await dbContext.Database.ExecuteSqlRawAsync(
                    @"UPDATE ""Leaves"" SET ""ShiftIds"" = {0} WHERE ""Id"" = {1}",
                    shiftIdsArray, createdLeave.Id);
                logger.LogWarning("[CreateLeave] Raw SQL updated ShiftIds for LeaveId={LeaveId} with {Count} shifts",
                    createdLeave.Id, shiftIdsArray.Length);
            }

            // Build approval chain
            var approvalRecords = await BuildApprovalChainAsync(
                request.EmployeeUserId, request.ManagerId, request.StoreId, totalLevels, cancellationToken);

            foreach (var record in approvalRecords)
            {
                record.LeaveId = createdLeave.Id;
                record.StoreId = request.StoreId;
                await approvalRecordRepository.AddAsync(record, cancellationToken);
            }

            var leaveDto = leave.Adapt<LeaveDto>();

            // Notify all approvers + Admin in the chain
            try
            {
                var allApproverIds = approvalRecords
                    .Where(r => r.AssignedUserId.HasValue)
                    .Select(r => r.AssignedUserId!.Value)
                    .Distinct()
                    .ToList();

                // Always notify Admin users (so they see all leave requests)
                var adminUsers = await userManager.Users
                    .Where(u => u.IsActive && (u.Role == "Admin" || u.Role == "SuperAdmin") && u.StoreId == request.StoreId && u.Id != request.EmployeeUserId)
                    .Select(u => u.Id)
                    .ToListAsync(cancellationToken);
                foreach (var adminId in adminUsers)
                {
                    if (!allApproverIds.Contains(adminId))
                        allApproverIds.Add(adminId);
                }

                if (allApproverIds.Any())
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        allApproverIds, NotificationType.ApprovalRequired,
                        "Đơn nghỉ phép mới",
                        $"Có đơn nghỉ phép mới cần phê duyệt từ {request.StartDate:dd/MM/yyyy} đến {request.EndDate:dd/MM/yyyy}" +
                        (totalLevels > 1 ? $" ({totalLevels} cấp duyệt)" : ""),
                        relatedEntityId: createdLeave.Id, relatedEntityType: "Leave",
                        fromUserId: request.EmployeeUserId, categoryCode: "leave", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<LeaveDto>.Success(leaveDto);
        }
        catch (ArgumentException ex)
        {
            return AppResponse<LeaveDto>.Error(ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<LeaveDto>.Error(ex.Message);
        }
    }

    private async Task<List<LeaveApprovalRecord>> BuildApprovalChainAsync(
        Guid employeeUserId, Guid managerId, Guid storeId, int totalLevels, CancellationToken ct)
    {
        var records = new List<LeaveApprovalRecord>();

        var employee = await employeeRepository.GetSingleAsync(
            e => e.ApplicationUserId == employeeUserId, cancellationToken: ct);

        // Build manager chain - walk up via DirectManagerEmployeeId first (most explicit)
        var managerChain = new List<(Guid UserId, string Name)>();
        var visitedUserIds = new HashSet<Guid> { employeeUserId }; // Skip self

        // === Source 1: Walk up DirectManagerEmployeeId chain (explicitly configured per-employee) ===
        if (employee?.DirectManagerEmployeeId != null)
        {
            var currentEmp = employee;
            while (currentEmp?.DirectManagerEmployeeId != null && managerChain.Count < totalLevels)
            {
                var mgrEmp = await employeeRepository.GetSingleAsync(
                    e => e.Id == currentEmp.DirectManagerEmployeeId.Value, cancellationToken: ct);
                if (mgrEmp?.ApplicationUserId == null) break;
                if (visitedUserIds.Contains(mgrEmp.ApplicationUserId.Value)) break; // prevent cycles

                var mgrUser = await userManager.FindByIdAsync(mgrEmp.ApplicationUserId.Value.ToString());
                if (mgrUser == null || !mgrUser.IsActive) break;

                managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));
                visitedUserIds.Add(mgrUser.Id);
                currentEmp = mgrEmp;
            }
        }

        // === Source 2: Department.ManagerId (department head, if not already in chain) ===
        if (managerChain.Count < totalLevels && employee?.DepartmentId != null)
        {
            var dept = await departmentRepository.GetSingleAsync(
                d => d.Id == employee.DepartmentId.Value, cancellationToken: ct);
            if (dept?.ManagerId != null)
            {
                var deptMgr = await employeeRepository.GetSingleAsync(
                    e => e.Id == dept.ManagerId.Value, cancellationToken: ct);
                if (deptMgr?.ApplicationUserId != null && !visitedUserIds.Contains(deptMgr.ApplicationUserId.Value))
                {
                    var mgrUser = await userManager.FindByIdAsync(deptMgr.ApplicationUserId.Value.ToString());
                    if (mgrUser != null && mgrUser.IsActive)
                    {
                        managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));
                        visitedUserIds.Add(mgrUser.Id);
                    }
                }
            }
        }

        // === Source 3: Employee.ManagerId (FK → ApplicationUser, often store owner - only if non-Admin) ===
        if (managerChain.Count < totalLevels && employee != null &&
            employee.ManagerId != Guid.Empty && !visitedUserIds.Contains(employee.ManagerId))
        {
            var mgrUser = await userManager.FindByIdAsync(employee.ManagerId.ToString());
            if (mgrUser != null && mgrUser.IsActive && mgrUser.Role != "Admin")
            {
                managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));
                visitedUserIds.Add(mgrUser.Id);
            }
        }

        // === Source 4: ManagerId from controller (JWT claim) - only if non-Admin ===
        if (managerChain.Count < totalLevels && managerId != Guid.Empty && !visitedUserIds.Contains(managerId))
        {
            var mgrUser = await userManager.FindByIdAsync(managerId.ToString());
            if (mgrUser != null && mgrUser.IsActive && mgrUser.Role != "Admin")
            {
                managerChain.Add((mgrUser.Id, mgrUser.FullName ?? mgrUser.Email ?? "Manager"));
                visitedUserIds.Add(mgrUser.Id);
            }
        }

        // Admin fallback for remaining levels
        var admins = await userManager.Users
            .Where(u => u.IsActive && u.Role == "Admin" && u.StoreId == storeId && u.Id != employeeUserId)
            .ToListAsync(ct);
        var adminFirst = admins.FirstOrDefault();

        var levelNames = new[] { "Quản lý trực tiếp", "Quản lý cấp cao", "Admin", "Cấp 4", "Cấp 5" };

        for (int level = 1; level <= totalLevels; level++)
        {
            Guid? assignedUserId = null;
            string? assignedUserName = null;

            if (level - 1 < managerChain.Count)
            {
                assignedUserId = managerChain[level - 1].UserId;
                assignedUserName = managerChain[level - 1].Name;
            }
            else if (adminFirst != null)
            {
                assignedUserId = adminFirst.Id;
                assignedUserName = adminFirst.FullName ?? adminFirst.Email;
            }

            records.Add(new LeaveApprovalRecord
            {
                StepOrder = level,
                StepName = level <= levelNames.Length ? levelNames[level - 1] : $"Cấp {level}",
                AssignedUserId = assignedUserId,
                AssignedUserName = assignedUserName,
                Status = ApprovalStatus.Pending
            });
        }

        return records;
    }
}
