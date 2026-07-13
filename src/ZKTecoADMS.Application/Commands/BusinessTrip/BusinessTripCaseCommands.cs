using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.BusinessTrip;

public record CreateBusinessTripCaseCommand(
    Guid StoreId,
    Guid CurrentUserId,
    Guid? EmployeeUserId,
    Guid? EmployeeId,
    string Title,
    string? Destination,
    DateTime? TripFromDate,
    DateTime? TripToDate,
    string? Note,
    bool IsPrivileged = false) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class CreateBusinessTripCaseHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<Employee> employeeRepository,
    UserManager<ApplicationUser> userManager) : ICommandHandler<CreateBusinessTripCaseCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(CreateBusinessTripCaseCommand request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
            return AppResponse<BusinessTripCaseDto>.Error("Vui lòng nhập tiêu đề chuyến công tác");

        // Nhân viên thường chỉ được tạo hồ sơ cho chính mình.
        var requestedUserId = request.IsPrivileged ? request.EmployeeUserId : request.CurrentUserId;
        var requestedEmployeeId = request.IsPrivileged ? request.EmployeeId : null;

        var (empUserId, empId, err) = await BusinessTripEmployeeResolver.ResolveAsync(
            userManager, employeeRepository, requestedUserId, requestedEmployeeId, request.CurrentUserId, ct);
        if (err != null) return AppResponse<BusinessTripCaseDto>.Error(err);

        if (!request.IsPrivileged && empUserId.HasValue && empUserId.Value != request.CurrentUserId)
            return AppResponse<BusinessTripCaseDto>.Error("Bạn chỉ được tạo hồ sơ công tác cho chính mình");

        var entity = new BusinessTripCase
        {
            Id = Guid.NewGuid(),
            CaseCode = await BusinessTripCodeGenerator.NextCaseCodeAsync(caseRepository, request.StoreId, ct),
            StoreId = request.StoreId,
            EmployeeUserId = empUserId,
            EmployeeId = empId,
            Title = request.Title.Trim(),
            Destination = request.Destination?.Trim(),
            TripFromDate = request.TripFromDate,
            TripToDate = request.TripToDate,
            Note = request.Note,
            Status = BusinessTripCaseStatus.Draft,
            IsActive = true
        };

        await caseRepository.AddAsync(entity, ct);
        return AppResponse<BusinessTripCaseDto>.Success(BusinessTripMapper.ToDto(entity));
    }
}

public record UpdateBusinessTripCaseCommand(
    Guid StoreId,
    Guid CaseId,
    Guid CurrentUserId,
    bool IsManager,
    string Title,
    string? Destination,
    DateTime? TripFromDate,
    DateTime? TripToDate,
    string? Note) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class UpdateBusinessTripCaseHandler(IRepository<BusinessTripCase> caseRepository)
    : ICommandHandler<UpdateBusinessTripCaseCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(UpdateBusinessTripCaseCommand request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
            return AppResponse<BusinessTripCaseDto>.Error("Vui lòng nhập tiêu đề chuyến công tác");

        var tripCase = await caseRepository.GetSingleAsync(
            c => c.Id == request.CaseId && c.StoreId == request.StoreId, cancellationToken: ct);
        if (tripCase == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy hồ sơ công tác");

        if (!request.IsManager && tripCase.EmployeeUserId != request.CurrentUserId)
            return AppResponse<BusinessTripCaseDto>.Error("Bạn không có quyền sửa hồ sơ này");

        if (tripCase.Status is BusinessTripCaseStatus.Closed or BusinessTripCaseStatus.Cancelled)
            return AppResponse<BusinessTripCaseDto>.Error("Không thể sửa hồ sơ đã đóng/hủy");

        // Nhân viên không được sửa khi đang chờ duyệt ứng/HT.
        if (!request.IsManager && tripCase.Status is BusinessTripCaseStatus.AdvancePending
            or BusinessTripCaseStatus.SettlementPending)
            return AppResponse<BusinessTripCaseDto>.Error("Không thể sửa hồ sơ đang chờ duyệt");

        tripCase.Title = request.Title.Trim();
        tripCase.Destination = request.Destination?.Trim();
        tripCase.TripFromDate = request.TripFromDate;
        tripCase.TripToDate = request.TripToDate;
        tripCase.Note = request.Note;
        tripCase.UpdatedAt = DateTime.UtcNow;
        await caseRepository.UpdateAsync(tripCase, ct);
        return AppResponse<BusinessTripCaseDto>.Success(BusinessTripMapper.ToDto(tripCase));
    }
}

public record DeleteBusinessTripCaseCommand(
    Guid StoreId,
    Guid CaseId,
    Guid CurrentUserId,
    bool IsManager) : ICommand<AppResponse<bool>>;

public class DeleteBusinessTripCaseHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripAdvanceClaim> advanceRepository,
    IRepository<BusinessTripSettlementClaim> settlementRepository,
    IRepository<CashTransaction> cashTransactionRepository)
    : ICommandHandler<DeleteBusinessTripCaseCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteBusinessTripCaseCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        if (tripCase == null)
            return AppResponse<bool>.Error("Không tìm thấy hồ sơ công tác");

        if (!request.IsManager && tripCase.EmployeeUserId != request.CurrentUserId)
            return AppResponse<bool>.Error("Bạn không có quyền xóa hồ sơ này");

        // Soft-delete (ẩn khỏi mọi danh sách) khi còn Nháp và chưa có ứng/HT đã duyệt.
        var canHardDelete = tripCase.Status == BusinessTripCaseStatus.Draft
            && (tripCase.AdvanceClaim == null
                || tripCase.AdvanceClaim.Status is AdvanceRequestStatus.Rejected or AdvanceRequestStatus.Cancelled)
            && tripCase.SettlementClaim == null;

        if (canHardDelete || tripCase.Status == BusinessTripCaseStatus.Cancelled)
        {
            tripCase.Deleted = DateTime.UtcNow;
            tripCase.DeletedBy = request.CurrentUserId.ToString();
            tripCase.IsActive = false;
            tripCase.Status = BusinessTripCaseStatus.Cancelled;
            BusinessTripCaseLoader.DetachNavigations(tripCase);
            await caseRepository.UpdateAsync(tripCase, ct);
            return AppResponse<bool>.Success(true);
        }

        if (tripCase.Status == BusinessTripCaseStatus.Closed)
            return AppResponse<bool>.Error("Hồ sơ đã đóng");

        if (tripCase.AdvanceClaim?.IsPaid == true || tripCase.SettlementClaim?.Status == AdvanceRequestStatus.Approved)
            return AppResponse<bool>.Error("Không thể xóa hồ sơ đã chi ứng / đã duyệt hoạch toán. Hãy liên hệ quản lý.");

        // Hủy claim ứng / HT chưa hoàn tất + phiếu Thu chi chờ thanh toán liên quan.
        await CancelRelatedFinanceAsync(tripCase, request.StoreId, ct);

        // Hủy = soft-delete để phiếu biến mất khỏi danh sách / báo cáo.
        tripCase.Status = BusinessTripCaseStatus.Cancelled;
        tripCase.Deleted = DateTime.UtcNow;
        tripCase.DeletedBy = request.CurrentUserId.ToString();
        tripCase.IsActive = false;
        tripCase.UpdatedAt = DateTime.UtcNow;
        BusinessTripCaseLoader.DetachNavigations(tripCase);
        await caseRepository.UpdateAsync(tripCase, ct);
        return AppResponse<bool>.Success(true);
    }

    private async Task CancelRelatedFinanceAsync(BusinessTripCase tripCase, Guid storeId, CancellationToken ct)
    {
        var advance = tripCase.AdvanceClaim;
        if (advance != null && !advance.IsPaid
            && advance.Status is AdvanceRequestStatus.Pending or AdvanceRequestStatus.Approved)
        {
            advance.Status = AdvanceRequestStatus.Cancelled;
            advance.UpdatedAt = DateTime.UtcNow;
            await advanceRepository.UpdateAsync(advance, ct);
            await CancelUnpaidCashAsync(storeId, advance.CashTransactionId, advance.Id.ToString(), ct);
        }

        var settlement = tripCase.SettlementClaim;
        if (settlement != null && settlement.Status != AdvanceRequestStatus.Approved)
        {
            settlement.Status = AdvanceRequestStatus.Cancelled;
            settlement.UpdatedAt = DateTime.UtcNow;
            await settlementRepository.UpdateAsync(settlement, ct);
            await CancelUnpaidCashAsync(storeId, settlement.ExtraCashTransactionId, settlement.Id.ToString(), ct);
        }
    }

    private async Task CancelUnpaidCashAsync(
        Guid storeId, Guid? cashId, string markerGuid, CancellationToken ct)
    {
        CashTransaction? cash = null;
        if (cashId.HasValue)
        {
            cash = await cashTransactionRepository.GetSingleAsync(
                c => c.Id == cashId && c.StoreId == storeId && c.IsActive && c.Deleted == null,
                cancellationToken: ct);
        }
        cash ??= await cashTransactionRepository.GetSingleAsync(
            c => c.StoreId == storeId && c.IsActive && c.Deleted == null
                 && c.InternalNote != null && c.InternalNote.Contains(markerGuid)
                 && !c.IsPaid,
            cancellationToken: ct);

        if (cash == null || cash.IsPaid) return;

        cash.Status = CashTransactionStatus.Cancelled;
        cash.IsActive = false;
        cash.UpdatedAt = DateTime.UtcNow;
        await cashTransactionRepository.UpdateAsync(cash, ct);
    }
}

public record CreateBusinessTripAdvanceCommand(
    Guid StoreId,
    Guid CaseId,
    Guid CurrentUserId,
    decimal Amount,
    string? Reason,
    string? Note,
    bool IsPrivileged = false) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class CreateBusinessTripAdvanceHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripAdvanceClaim> advanceRepository,
    IRepository<BusinessTripAdvanceApprovalRecord> approvalRecordRepository,
    IRepository<AppSettings> appSettingsRepository,
    IRepository<Employee> employeeRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService,
    INotificationTargetResolver targetResolver) : ICommandHandler<CreateBusinessTripAdvanceCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(CreateBusinessTripAdvanceCommand request, CancellationToken ct)
    {
        if (request.Amount <= 0)
            return AppResponse<BusinessTripCaseDto>.Error("Số tiền ứng phải lớn hơn 0");

        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        if (tripCase == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy hồ sơ công tác");

        var deny = BusinessTripAccess.DenyIfCannotAccess(tripCase, request.CurrentUserId, request.IsPrivileged);
        if (deny != null)
            return AppResponse<BusinessTripCaseDto>.Error(deny);

        if (tripCase.AdvanceClaim != null && tripCase.AdvanceClaim.Status == AdvanceRequestStatus.Pending)
            return AppResponse<BusinessTripCaseDto>.Error("Đã có phiếu ứng đang chờ duyệt");

        if (tripCase.Status is not (BusinessTripCaseStatus.Draft or BusinessTripCaseStatus.AdvancePending)
            && tripCase.AdvanceClaim?.Status is not AdvanceRequestStatus.Rejected)
            return AppResponse<BusinessTripCaseDto>.Error("Không thể tạo ứng ở trạng thái hiện tại");

        var totalLevels = await BusinessTripApprovalChainHelper.ReadApprovalLevelsAsync(
            appSettingsRepository, request.StoreId,
            "business_trip_advance_approval_levels", "advance_approval_levels", ct);

        var managerChain = await BusinessTripApprovalChainHelper.BuildManagerChainAsync(
            employeeRepository, userManager, tripCase.EmployeeUserId, ct);
        var adminFallback = await BusinessTripApprovalChainHelper.ResolveAdminFallbackAsync(
            userManager, request.StoreId, tripCase.EmployeeUserId, ct);
        var steps = BusinessTripApprovalChainHelper.BuildSteps(totalLevels, managerChain, adminFallback);

        BusinessTripAdvanceClaim advance;
        if (tripCase.AdvanceClaim != null)
        {
            advance = tripCase.AdvanceClaim;
            var oldRecords = await approvalRecordRepository.GetAllAsync(
                r => r.AdvanceClaimId == advance.Id, cancellationToken: ct);
            foreach (var r in oldRecords)
                await approvalRecordRepository.DeleteAsync(r, ct);

            advance.Amount = request.Amount;
            advance.Reason = request.Reason ?? tripCase.Title;
            advance.Note = request.Note;
            advance.Status = AdvanceRequestStatus.Pending;
            advance.RejectionReason = null;
            advance.RequestDate = DateTime.UtcNow;
            advance.TotalApprovalLevels = totalLevels;
            advance.CurrentApprovalStep = 0;
            advance.IsPaid = false;
            advance.PaidDate = null;
            advance.PaymentMethod = null;
            await advanceRepository.UpdateAsync(advance, ct);
        }
        else
        {
            advance = new BusinessTripAdvanceClaim
            {
                Id = Guid.NewGuid(),
                CaseId = tripCase.Id,
                StoreId = request.StoreId,
                Amount = request.Amount,
                Reason = request.Reason ?? tripCase.Title,
                Note = request.Note,
                Status = AdvanceRequestStatus.Pending,
                TotalApprovalLevels = totalLevels,
                IsActive = true
            };
            await advanceRepository.AddAsync(advance, ct);
        }

        foreach (var step in steps)
        {
            await approvalRecordRepository.AddAsync(new BusinessTripAdvanceApprovalRecord
            {
                Id = Guid.NewGuid(),
                AdvanceClaimId = advance.Id,
                StoreId = request.StoreId,
                StepOrder = step.StepOrder,
                StepName = step.StepName,
                AssignedUserId = step.AssignedUserId,
                AssignedUserName = step.AssignedUserName,
                Status = ApprovalStatus.Pending
            }, ct);
        }

        tripCase.Status = BusinessTripCaseStatus.AdvancePending;
        tripCase.AdvanceAmount = request.Amount;
        tripCase.UpdatedAt = DateTime.UtcNow;
        await caseRepository.UpdateAsync(tripCase, ct);

        try
        {
            var targets = await targetResolver.ResolveManagersAsync(
                tripCase.EmployeeUserId, request.StoreId, hierarchyLevels: 2, ct);
            var set = new HashSet<Guid>(targets);
            var first = steps.FirstOrDefault();
            if (first.AssignedUserId.HasValue) set.Add(first.AssignedUserId.Value);
            if (tripCase.EmployeeUserId.HasValue) set.Remove(tripCase.EmployeeUserId.Value);
            if (set.Count > 0)
            {
                await notificationService.CreateAndSendToUsersAsync(
                    set, NotificationType.ApprovalRequired,
                    "Yêu cầu ứng công tác mới",
                    $"Ứng công tác {request.Amount:N0}đ — {tripCase.CaseCode}",
                    relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                    fromUserId: tripCase.EmployeeUserId, categoryCode: "business_trip", storeId: request.StoreId);
            }
        }
        catch { }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }
}
