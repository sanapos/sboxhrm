using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.AdvanceRequests;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.AdvanceRequests;

// Create Advance Request Command
public record CreateAdvanceRequestCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    decimal Amount,
    string? Reason,
    string? Note,
    int? ForMonth = null,
    int? ForYear = null,
    Guid? EmployeeId = null) : ICommand<AppResponse<AdvanceRequestDto>>;

public class CreateAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<Employee> employeeRepository,
    IRepository<AdvanceApprovalRecord> approvalRecordRepository,
    IRepository<AppSettings> appSettingsRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateAdvanceRequestCommand, AppResponse<AdvanceRequestDto>>
{
    public async Task<AppResponse<AdvanceRequestDto>> Handle(CreateAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            if (request.Amount <= 0)
            {
                return AppResponse<AdvanceRequestDto>.Error("Số tiền ứng lương phải lớn hơn 0");
            }

            Guid? employeeUserId = null;
            Guid? employeeId = request.EmployeeId;

            var inputId = request.EmployeeUserId;
            var user = await userManager.FindByIdAsync(inputId.ToString());
            if (user != null)
            {
                employeeUserId = inputId;
                if (employeeId == null)
                {
                    var emp = await employeeRepository.GetSingleAsync(
                        e => e.ApplicationUserId == inputId, cancellationToken: cancellationToken);
                    employeeId = emp?.Id;
                }
            }
            else
            {
                var employee = await employeeRepository.GetByIdAsync(inputId, cancellationToken: cancellationToken);
                if (employee != null)
                {
                    employeeId = employee.Id;
                    if (employee.ApplicationUserId != null)
                        employeeUserId = employee.ApplicationUserId.Value;
                }
                else
                {
                    return AppResponse<AdvanceRequestDto>.Error("Không tìm thấy nhân viên");
                }
            }

            if (employeeId == null)
            {
                return AppResponse<AdvanceRequestDto>.Error("Không tìm thấy hồ sơ nhân viên. Vui lòng kiểm tra nhân viên đã được tạo hồ sơ chưa.");
            }

            var existingRequests = await advanceRequestRepository.GetAllAsync(
                ar => ar.StoreId == request.StoreId &&
                      ar.EmployeeId == employeeId
                      && ar.Status == AdvanceRequestStatus.Pending,
                cancellationToken: cancellationToken);

            if (existingRequests.Any())
            {
                return AppResponse<AdvanceRequestDto>.Error("Nhân viên đã có yêu cầu ứng lương đang chờ duyệt");
            }

            // Read approval levels from settings
            int totalLevels = 1;
            try
            {
                var setting = await appSettingsRepository.GetSingleAsync(
                    s => s.StoreId == request.StoreId && s.Key == "advance_approval_levels",
                    cancellationToken: cancellationToken);
                if (setting != null && int.TryParse(setting.Value, out var lvl) && lvl >= 1)
                    totalLevels = lvl;
            }
            catch { /* fallback to 1 */ }

            var advanceRequest = new AdvanceRequest
            {
                StoreId = request.StoreId,
                EmployeeUserId = employeeUserId,
                EmployeeId = employeeId,
                Amount = request.Amount,
                Reason = request.Reason ?? string.Empty,
                Note = request.Note,
                RequestDate = DateTime.UtcNow,
                Status = AdvanceRequestStatus.Pending,
                ForMonth = request.ForMonth,
                ForYear = request.ForYear,
                TotalApprovalLevels = totalLevels,
                CurrentApprovalStep = 0
            };

            var created = await advanceRequestRepository.AddAsync(advanceRequest, cancellationToken);

            // Build approval chain
            var approvalRecords = await BuildApprovalChainAsync(
                employeeUserId, request.StoreId, totalLevels, cancellationToken);

            foreach (var record in approvalRecords)
            {
                record.AdvanceRequestId = created.Id;
                record.StoreId = request.StoreId;
                await approvalRecordRepository.AddAsync(record, cancellationToken);
            }

            var result = await advanceRequestRepository.GetByIdAsync(
                created.Id,
                [nameof(AdvanceRequest.EmployeeUser), nameof(AdvanceRequest.Employee)],
                cancellationToken: cancellationToken);

            // Notify first-level approver only
            try
            {
                var employeeName = result?.EmployeeUser != null
                    ? $"{result.EmployeeUser.LastName} {result.EmployeeUser.FirstName}".Trim()
                    : "Nhân viên";

                var firstApprover = approvalRecords.FirstOrDefault();
                if (firstApprover?.AssignedUserId != null)
                {
                    await notificationService.CreateAndSendAsync(
                        firstApprover.AssignedUserId.Value, NotificationType.ApprovalRequired,
                        "Yêu cầu ứng lương mới",
                        $"{employeeName} yêu cầu ứng lương {request.Amount:N0}đ" +
                        (totalLevels > 1 ? $" (Bước 1/{totalLevels})" : ""),
                        relatedEntityId: created.Id, relatedEntityType: "AdvanceRequest",
                        fromUserId: request.EmployeeUserId, categoryCode: "approval", storeId: request.StoreId);
                }
                else
                {
                    // Fallback: broadcast to all managers
                    var managers = await userManager.GetUsersInRoleAsync(nameof(Roles.Manager));
                    var admins = await userManager.GetUsersInRoleAsync(nameof(Roles.Admin));
                    var targetUsers = managers.Concat(admins)
                        .Where(u => u.StoreId == request.StoreId && u.Id != request.EmployeeUserId)
                        .Select(u => u.Id).Distinct().ToList();
                    if (targetUsers.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            targetUsers, NotificationType.ApprovalRequired,
                            "Yêu cầu ứng lương mới",
                            $"{employeeName} yêu cầu ứng lương {request.Amount:N0}đ",
                            relatedEntityId: created.Id, relatedEntityType: "AdvanceRequest",
                            fromUserId: request.EmployeeUserId, categoryCode: "approval", storeId: request.StoreId);
                    }
                }
            }
            catch { }

            return AppResponse<AdvanceRequestDto>.Success(result!.Adapt<AdvanceRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AdvanceRequestDto>.Error(ex.Message);
        }
    }

    private async Task<List<AdvanceApprovalRecord>> BuildApprovalChainAsync(
        Guid? employeeUserId, Guid storeId, int totalLevels, CancellationToken ct)
    {
        var records = new List<AdvanceApprovalRecord>();
        var managerChain = new List<(Guid UserId, string Name)>();

        if (employeeUserId.HasValue)
        {
            var employee = await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == employeeUserId.Value, cancellationToken: ct);

            if (employee?.DirectManagerEmployeeId != null)
            {
                var mgr = await employeeRepository.GetSingleAsync(
                    e => e.Id == employee.DirectManagerEmployeeId.Value, cancellationToken: ct);
                if (mgr?.ApplicationUserId != null)
                {
                    var mUser = await userManager.FindByIdAsync(mgr.ApplicationUserId.Value.ToString());
                    if (mUser != null)
                        managerChain.Add((mUser.Id, mUser.FullName ?? mUser.Email ?? "Manager"));

                    if (mgr.DirectManagerEmployeeId != null)
                    {
                        var gp = await employeeRepository.GetSingleAsync(
                            e => e.Id == mgr.DirectManagerEmployeeId.Value, cancellationToken: ct);
                        if (gp?.ApplicationUserId != null)
                        {
                            var gpUser = await userManager.FindByIdAsync(gp.ApplicationUserId.Value.ToString());
                            if (gpUser != null)
                                managerChain.Add((gpUser.Id, gpUser.FullName ?? gpUser.Email ?? "Director"));
                        }
                    }
                }
            }
        }

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

            records.Add(new AdvanceApprovalRecord
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

// Approve Advance Request Command
public record ApproveAdvanceRequestCommand(
    Guid StoreId,
    Guid RequestId,
    Guid ApprovedById,
    bool IsApproved,
    string? RejectionReason) : ICommand<AppResponse<AdvanceRequestDto>>;

public class ApproveAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<AdvanceApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
) : ICommandHandler<ApproveAdvanceRequestCommand, AppResponse<AdvanceRequestDto>>
{
    public async Task<AppResponse<AdvanceRequestDto>> Handle(ApproveAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.RequestId && a.StoreId == request.StoreId,
                includeProperties: [nameof(AdvanceRequest.EmployeeUser), nameof(AdvanceRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            if (advanceRequest == null)
            {
                return AppResponse<AdvanceRequestDto>.Error("Advance request not found");
            }

            if (advanceRequest.Status != AdvanceRequestStatus.Pending)
            {
                return AppResponse<AdvanceRequestDto>.Error("This request has already been processed");
            }

            var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
            var approverName = approver?.FullName ?? approver?.Email ?? "Unknown";

            // Get approval records
            var approvalRecords = (await approvalRecordRepository.GetAllAsync(
                filter: r => r.AdvanceRequestId == advanceRequest.Id,
                cancellationToken: cancellationToken))
                .OrderBy(r => r.StepOrder).ToList();

            if (request.IsApproved)
            {
                if (approvalRecords.Count == 0)
                {
                    // Legacy record - approve directly
                    advanceRequest.Status = AdvanceRequestStatus.Approved;
                    advanceRequest.ApprovedById = request.ApprovedById;
                    advanceRequest.ApprovedDate = DateTime.UtcNow;
                    await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);
                }
                else
                {
                    var currentStep = approvalRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
                    if (currentStep == null)
                        return AppResponse<AdvanceRequestDto>.Error("Không có bước duyệt nào đang chờ");

                    currentStep.Status = ApprovalStatus.Approved;
                    currentStep.ActualUserId = request.ApprovedById;
                    currentStep.ActualUserName = approverName;
                    currentStep.ActionDate = DateTime.UtcNow;
                    currentStep.Note = "Đã phê duyệt";
                    await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);

                    advanceRequest.CurrentApprovalStep = currentStep.StepOrder;
                    advanceRequest.UpdatedAt = DateTime.UtcNow;

                    var nextStep = approvalRecords.FirstOrDefault(r => r.StepOrder > currentStep.StepOrder && r.Status == ApprovalStatus.Pending);

                    if (nextStep == null)
                    {
                        // All steps done - finalize
                        advanceRequest.Status = AdvanceRequestStatus.Approved;
                        advanceRequest.ApprovedById = request.ApprovedById;
                        advanceRequest.ApprovedDate = DateTime.UtcNow;
                        await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);

                        try
                        {
                            if (advanceRequest.EmployeeUserId.HasValue)
                            {
                                await notificationService.CreateAndSendAsync(
                                    advanceRequest.EmployeeUserId.Value, NotificationType.Success,
                                    "Yêu cầu ứng lương đã duyệt",
                                    $"Yêu cầu ứng lương {advanceRequest.Amount:N0}đ đã được phê duyệt hoàn tất" +
                                    (advanceRequest.TotalApprovalLevels > 1 ? $" ({advanceRequest.TotalApprovalLevels}/{advanceRequest.TotalApprovalLevels} cấp)" : ""),
                                    relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                                    fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                            }
                        }
                        catch { }
                    }
                    else
                    {
                        // More steps - notify next approver
                        await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);

                        try
                        {
                            if (nextStep.AssignedUserId.HasValue)
                            {
                                await notificationService.CreateAndSendAsync(
                                    nextStep.AssignedUserId.Value, NotificationType.ApprovalRequired,
                                    "Yêu cầu ứng lương cần phê duyệt",
                                    $"Yêu cầu ứng lương cần phê duyệt (Bước {nextStep.StepOrder}/{advanceRequest.TotalApprovalLevels}) - {advanceRequest.Amount:N0}đ",
                                    relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                                    fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                            }

                            if (advanceRequest.EmployeeUserId.HasValue)
                            {
                                await notificationService.CreateAndSendAsync(
                                    advanceRequest.EmployeeUserId.Value, NotificationType.Info,
                                    "Tiến trình duyệt ứng lương",
                                    $"Yêu cầu ứng lương đã duyệt bước {currentStep.StepOrder}/{advanceRequest.TotalApprovalLevels} ({currentStep.StepName}) bởi {approverName}",
                                    relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                                    fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                            }
                        }
                        catch { }
                    }
                }

                return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
            }
            else
            {
                // Reject
                if (approvalRecords.Count > 0)
                {
                    var currentStep = approvalRecords.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
                    if (currentStep != null)
                    {
                        currentStep.Status = ApprovalStatus.Rejected;
                        currentStep.ActualUserId = request.ApprovedById;
                        currentStep.ActualUserName = approverName;
                        currentStep.ActionDate = DateTime.UtcNow;
                        currentStep.Note = request.RejectionReason;
                        await approvalRecordRepository.UpdateAsync(currentStep, cancellationToken);
                    }

                    foreach (var record in approvalRecords.Where(r => r.Status == ApprovalStatus.Pending))
                    {
                        record.Status = ApprovalStatus.Cancelled;
                        record.ActionDate = DateTime.UtcNow;
                        await approvalRecordRepository.UpdateAsync(record, cancellationToken);
                    }
                }

                advanceRequest.Status = AdvanceRequestStatus.Rejected;
                advanceRequest.ApprovedById = request.ApprovedById;
                advanceRequest.ApprovedDate = DateTime.UtcNow;
                advanceRequest.RejectionReason = request.RejectionReason;
                await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);

                try
                {
                    if (advanceRequest.EmployeeUserId.HasValue)
                    {
                        var stepInfo = approvalRecords.Count > 1
                            ? $" (bởi {approverName})"
                            : "";
                        await notificationService.CreateAndSendAsync(
                            advanceRequest.EmployeeUserId.Value, NotificationType.Warning,
                            "Yêu cầu ứng lương bị từ chối",
                            $"Yêu cầu ứng lương {advanceRequest.Amount:N0}đ đã bị từ chối{stepInfo}. Lý do: {request.RejectionReason}",
                            relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                            fromUserId: request.ApprovedById, categoryCode: "approval", storeId: request.StoreId);
                    }
                }
                catch { }

                return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
            }
        }
        catch (Exception ex)
        {
            return AppResponse<AdvanceRequestDto>.Error(ex.Message);
        }
    }
}

// Delete Advance Request Command
public record DeleteAdvanceRequestCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteAdvanceRequestCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (advanceRequest == null)
            {
                return AppResponse<bool>.Error("Advance request not found");
            }

            if (advanceRequest.IsPaid)
            {
                var advanceIdStr = advanceRequest.Id.ToString();
                var linkedCashTx = await cashTransactionRepository.GetSingleAsync(
                    c => c.IsActive && c.InternalNote != null && c.InternalNote.Contains(advanceIdStr),
                    cancellationToken: cancellationToken);
                if (linkedCashTx != null)
                {
                    linkedCashTx.IsActive = false;
                    linkedCashTx.Deleted = DateTime.UtcNow;
                    await cashTransactionRepository.UpdateAsync(linkedCashTx, cancellationToken);
                }
            }

            await advanceRequestRepository.DeleteAsync(advanceRequest, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Undo Approve Advance Request Command (Hoàn duyệt)
public record UndoApproveAdvanceRequestCommand(
    Guid StoreId,
    Guid RequestId,
    Guid CurrentUserId) : ICommand<AppResponse<AdvanceRequestDto>>;

public class UndoApproveAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<AdvanceApprovalRecord> approvalRecordRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UndoApproveAdvanceRequestCommand, AppResponse<AdvanceRequestDto>>
{
    public async Task<AppResponse<AdvanceRequestDto>> Handle(UndoApproveAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.RequestId && a.StoreId == request.StoreId,
                includeProperties: [nameof(AdvanceRequest.EmployeeUser), nameof(AdvanceRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            if (advanceRequest == null)
            {
                return AppResponse<AdvanceRequestDto>.Error("Advance request not found");
            }

            if (advanceRequest.Status != AdvanceRequestStatus.Approved && advanceRequest.Status != AdvanceRequestStatus.Rejected)
            {
                return AppResponse<AdvanceRequestDto>.Error("Chỉ có thể hoàn duyệt đơn đã duyệt hoặc đã từ chối");
            }

            if (advanceRequest.IsPaid)
            {
                return AppResponse<AdvanceRequestDto>.Error("Cannot undo approval for paid requests");
            }

            advanceRequest.Status = AdvanceRequestStatus.Pending;
            advanceRequest.ApprovedById = null;
            advanceRequest.ApprovedDate = null;
            advanceRequest.RejectionReason = null;
            advanceRequest.CurrentApprovalStep = 0;

            await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);

            // Reset all approval records to Pending
            var approvalRecords = await approvalRecordRepository.GetAllAsync(
                filter: r => r.AdvanceRequestId == advanceRequest.Id,
                cancellationToken: cancellationToken);
            foreach (var record in approvalRecords)
            {
                record.Status = ApprovalStatus.Pending;
                record.ActualUserId = null;
                record.ActualUserName = null;
                record.ActionDate = null;
                record.Note = null;
                await approvalRecordRepository.UpdateAsync(record, cancellationToken);
            }

            try
            {
                if (advanceRequest.EmployeeUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        advanceRequest.EmployeeUserId.Value, NotificationType.Warning,
                        "Yêu cầu ứng lương hoàn duyệt",
                        $"Yêu cầu ứng lương {advanceRequest.Amount:N0}đ đã được hoàn duyệt về trạng thái chờ",
                        relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                        fromUserId: request.CurrentUserId, categoryCode: "approval", storeId: request.StoreId);
                }
            }
            catch { }

            return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AdvanceRequestDto>.Error(ex.Message);
        }
    }
}

// Cancel Advance Request Command
public record CancelAdvanceRequestCommand(
    Guid StoreId,
    Guid RequestId,
    Guid ApplicationUserId,
    bool IsManager) : ICommand<AppResponse<bool>>;

public class CancelAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<AdvanceApprovalRecord> approvalRecordRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CancelAdvanceRequestCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(CancelAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.RequestId && a.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (advanceRequest == null)
                return AppResponse<bool>.Error("Advance request not found");

            if (!request.IsManager && advanceRequest.EmployeeUserId != request.ApplicationUserId)
                return AppResponse<bool>.Error("You are not authorized to cancel this request");

            if (advanceRequest.Status != AdvanceRequestStatus.Pending)
                return AppResponse<bool>.Error($"Cannot cancel request with status: {advanceRequest.Status}");

            advanceRequest.Status = AdvanceRequestStatus.Cancelled;
            await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);

            // Cancel all pending approval records
            var approvalRecords = await approvalRecordRepository.GetAllAsync(
                filter: r => r.AdvanceRequestId == advanceRequest.Id && r.Status == ApprovalStatus.Pending,
                cancellationToken: cancellationToken);
            foreach (var record in approvalRecords)
            {
                record.Status = ApprovalStatus.Cancelled;
                record.ActionDate = DateTime.UtcNow;
                await approvalRecordRepository.UpdateAsync(record, cancellationToken);
            }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Pay Advance Request Command (Thanh toán)
public record PayAdvanceRequestCommand(
    Guid StoreId,
    Guid RequestId,
    Guid PerformedById,
    string? PaymentMethod = null) : ICommand<AppResponse<AdvanceRequestDto>>;

public class PayAdvanceRequestHandler(
    IRepository<AdvanceRequest> advanceRequestRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<TransactionCategory> categoryRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<PayAdvanceRequestCommand, AppResponse<AdvanceRequestDto>>
{
    private static Domain.Enums.PaymentMethodType ParsePaymentMethod(string? method)
    {
        return method?.ToLowerInvariant() switch
        {
            "banktransfer" or "bank_transfer" or "bank" => Domain.Enums.PaymentMethodType.BankTransfer,
            "vietqr" or "qr" => Domain.Enums.PaymentMethodType.VietQR,
            "card" => Domain.Enums.PaymentMethodType.Card,
            "ewallet" or "e_wallet" or "wallet" => Domain.Enums.PaymentMethodType.EWallet,
            _ => Domain.Enums.PaymentMethodType.Cash,
        };
    }

    private static string GetPaymentMethodLabel(Domain.Enums.PaymentMethodType method)
    {
        return method switch
        {
            Domain.Enums.PaymentMethodType.BankTransfer => "Chuyển khoản",
            Domain.Enums.PaymentMethodType.VietQR => "VietQR",
            Domain.Enums.PaymentMethodType.Card => "Thẻ",
            Domain.Enums.PaymentMethodType.EWallet => "Ví điện tử",
            _ => "Tiền mặt",
        };
    }

    public async Task<AppResponse<AdvanceRequestDto>> Handle(PayAdvanceRequestCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var advanceRequest = await advanceRequestRepository.GetSingleAsync(
                a => a.Id == request.RequestId && a.StoreId == request.StoreId,
                includeProperties: [nameof(AdvanceRequest.Employee), nameof(AdvanceRequest.EmployeeUser), nameof(AdvanceRequest.ApprovedBy)],
                cancellationToken: cancellationToken);

            if (advanceRequest == null)
            {
                return AppResponse<AdvanceRequestDto>.Error("Advance request not found");
            }

            if (advanceRequest.Status != AdvanceRequestStatus.Approved)
            {
                return AppResponse<AdvanceRequestDto>.Error("Only approved requests can be paid");
            }

            var paymentMethodEnum = ParsePaymentMethod(request.PaymentMethod);
            var paymentMethodLabel = GetPaymentMethodLabel(paymentMethodEnum);
            // Lấy tên từ Employee (nhân viên) thay vì EmployeeUser (tài khoản đăng nhập)
            var employeeName = advanceRequest.Employee != null
                ? $"{advanceRequest.Employee.LastName} {advanceRequest.Employee.FirstName}".Trim()
                : $"{advanceRequest.EmployeeUser?.LastName} {advanceRequest.EmployeeUser?.FirstName}".Trim();
            var internalNoteMarker = $"Tự động tạo từ thanh toán ứng lương #{advanceRequest.Id}";

            // Nếu đã thanh toán, kiểm tra xem phiếu chi đã tồn tại chưa
            if (advanceRequest.IsPaid)
            {
                var advanceIdStr = advanceRequest.Id.ToString();
                var existingCashTx = await cashTransactionRepository.GetSingleAsync(
                    c => c.IsActive && c.InternalNote != null && c.InternalNote.Contains(advanceIdStr),
                    cancellationToken: cancellationToken);

                if (existingCashTx != null)
                {
                    return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
                }
                // Phiếu chi chưa tồn tại → tạo bù bên dưới
            }

            // Create PaymentTransaction (chỉ khi chưa thanh toán)
            if (!advanceRequest.IsPaid)
            {
                var paymentTransaction = new PaymentTransaction
                {
                    EmployeeUserId = advanceRequest.EmployeeUserId ?? Guid.Empty,
                    Type = "AdvancePayment",
                    ForMonth = advanceRequest.ForMonth,
                    ForYear = advanceRequest.ForYear,
                    TransactionDate = DateTime.UtcNow,
                    Amount = advanceRequest.Amount,
                    Description = $"Thanh toán ứng lương ({paymentMethodLabel}) - {employeeName}",
                    PaymentMethod = paymentMethodLabel,
                    Status = "Completed",
                    PerformedById = request.PerformedById,
                    AdvanceRequestId = advanceRequest.Id,
                    Note = advanceRequest.Reason
                };

                await paymentTransactionRepository.AddAsync(paymentTransaction, cancellationToken);
            }

            // Create CashTransaction (phiếu chi)
            var advanceCategory = await categoryRepository.GetSingleAsync(
                c => c.Name == "Ứng lương" && c.Type == Domain.Enums.CashTransactionType.Expense && c.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            // Tự động tạo category "Ứng lương" nếu chưa tồn tại
            if (advanceCategory == null)
            {
                advanceCategory = new TransactionCategory
                {
                    Id = Guid.NewGuid(),
                    Name = "Ứng lương",
                    Description = "Chi ứng lương cho nhân viên",
                    Type = Domain.Enums.CashTransactionType.Expense,
                    Icon = "money_off",
                    Color = "#FF9800",
                    IsSystem = true,
                    IsActive = true,
                    StoreId = request.StoreId
                };
                await categoryRepository.AddAsync(advanceCategory, cancellationToken);
            }

            {
                var now = DateTime.UtcNow;
                var cashTransaction = new CashTransaction
                {
                    TransactionCode = $"CH-{now:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpperInvariant()}",
                    Type = Domain.Enums.CashTransactionType.Expense,
                    CategoryId = advanceCategory.Id,
                    Amount = advanceRequest.Amount,
                    TransactionDate = now,
                    Description = $"Chi ứng lương ({paymentMethodLabel}) - {employeeName}",
                    PaymentMethod = paymentMethodEnum,
                    Status = Domain.Enums.CashTransactionStatus.Completed,
                    ContactName = employeeName,
                    CreatedByUserId = advanceRequest.EmployeeUserId ?? request.PerformedById,
                    IsPaid = true,
                    PaidDate = now,
                    InternalNote = internalNoteMarker,
                    IsActive = true,
                    StoreId = request.StoreId
                };

                await cashTransactionRepository.AddAsync(cashTransaction, cancellationToken);
            }

            // Update advance request
            if (!advanceRequest.IsPaid)
            {
                advanceRequest.IsPaid = true;
                advanceRequest.PaymentMethod = paymentMethodLabel;
                advanceRequest.PaidDate = DateTime.UtcNow;
                await advanceRequestRepository.UpdateAsync(advanceRequest, cancellationToken);
            }

            try
            {
                if (advanceRequest.EmployeeUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        advanceRequest.EmployeeUserId.Value, NotificationType.Success,
                        "Ứng lương đã thanh toán",
                        $"Yêu cầu ứng lương {advanceRequest.Amount:N0}đ đã được thanh toán ({paymentMethodLabel})",
                        relatedEntityId: advanceRequest.Id, relatedEntityType: "AdvanceRequest",
                        fromUserId: request.PerformedById, categoryCode: "payroll", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return AppResponse<AdvanceRequestDto>.Success(advanceRequest.Adapt<AdvanceRequestDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<AdvanceRequestDto>.Error(ex.Message);
        }
    }
}
