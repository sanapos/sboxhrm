using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.BusinessTrip;

public record ApproveBusinessTripAdvanceCommand(
    Guid StoreId,
    Guid CaseId,
    Guid ApprovedById,
    bool IsApproved,
    string? RejectionReason) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class ApproveBusinessTripAdvanceHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripAdvanceClaim> advanceRepository,
    IRepository<BusinessTripAdvanceApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService) : ICommandHandler<ApproveBusinessTripAdvanceCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(ApproveBusinessTripAdvanceCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        var advance = tripCase?.AdvanceClaim;
        if (tripCase == null || advance == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy phiếu ứng công tác");

        if (advance.Status != AdvanceRequestStatus.Pending)
            return AppResponse<BusinessTripCaseDto>.Error("Phiếu ứng đã được xử lý");

        var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
        var approverName = approver?.FullName ?? approver?.Email ?? "Unknown";
        var records = advance.ApprovalRecords.OrderBy(r => r.StepOrder).ToList();

        if (request.IsApproved)
        {
            var current = records.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
            if (current == null && records.Count > 0)
                return AppResponse<BusinessTripCaseDto>.Error("Không có bước duyệt nào đang chờ");

            if (current != null)
            {
                current.Status = ApprovalStatus.Approved;
                current.ActualUserId = request.ApprovedById;
                current.ActualUserName = approverName;
                current.ActionDate = DateTime.UtcNow;
                advance.CurrentApprovalStep = current.StepOrder;
                await approvalRecordRepository.UpdateAsync(current, ct);
            }

            var next = records.FirstOrDefault(r => r.StepOrder > advance.CurrentApprovalStep && r.Status == ApprovalStatus.Pending);
            if (next != null)
            {
                await advanceRepository.UpdateAsync(advance, ct);
                try
                {
                    if (next.AssignedUserId.HasValue)
                    {
                        await notificationService.CreateAndSendAsync(
                            next.AssignedUserId.Value, NotificationType.ApprovalRequired,
                            "Ứng công tác chờ duyệt",
                            $"Bước {next.StepOrder}/{advance.TotalApprovalLevels} — {tripCase.CaseCode}",
                            relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                            fromUserId: request.ApprovedById, categoryCode: "business_trip", storeId: request.StoreId);
                    }
                }
                catch { }
                return AppResponse<BusinessTripCaseDto>.Success(
                    await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
            }

            advance.Status = AdvanceRequestStatus.Approved;
            advance.ApprovedById = request.ApprovedById;
            advance.ApprovedDate = DateTime.UtcNow;
            tripCase.Status = BusinessTripCaseStatus.AdvanceApproved;
            tripCase.UpdatedAt = DateTime.UtcNow;
            await advanceRepository.UpdateAsync(advance, ct);
            await caseRepository.UpdateAsync(tripCase, ct);

            try
            {
                if (tripCase.EmployeeUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        tripCase.EmployeeUserId.Value, NotificationType.Success,
                        "Ứng công tác đã duyệt",
                        $"Phiếu ứng {advance.Amount:N0}đ đã duyệt — chờ chi trả",
                        relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                        fromUserId: request.ApprovedById, categoryCode: "business_trip", storeId: request.StoreId);
                }
            }
            catch { }
        }
        else
        {
            foreach (var r in records.Where(r => r.Status == ApprovalStatus.Pending))
            {
                r.Status = ApprovalStatus.Cancelled;
                await approvalRecordRepository.UpdateAsync(r, ct);
            }
            advance.Status = AdvanceRequestStatus.Rejected;
            advance.RejectionReason = request.RejectionReason;
            advance.ApprovedById = request.ApprovedById;
            advance.ApprovedDate = DateTime.UtcNow;
            tripCase.Status = BusinessTripCaseStatus.Draft;
            tripCase.UpdatedAt = DateTime.UtcNow;
            await advanceRepository.UpdateAsync(advance, ct);
            await caseRepository.UpdateAsync(tripCase, ct);

            try
            {
                if (tripCase.EmployeeUserId.HasValue)
                {
                    var reason = string.IsNullOrWhiteSpace(request.RejectionReason)
                        ? "Không có lý do"
                        : request.RejectionReason.Trim();
                    await notificationService.CreateAndSendAsync(
                        tripCase.EmployeeUserId.Value, NotificationType.Warning,
                        "Ứng công tác bị từ chối",
                        $"{tripCase.CaseCode}: {reason}",
                        relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                        fromUserId: request.ApprovedById, categoryCode: "business_trip", storeId: request.StoreId);
                }
            }
            catch { }
        }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }
}

public record PayBusinessTripAdvanceCommand(
    Guid StoreId,
    Guid CaseId,
    Guid PerformedById,
    string? PaymentMethod) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class PayBusinessTripAdvanceHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripAdvanceClaim> advanceRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<PaymentTransaction> paymentTransactionRepository,
    IRepository<TransactionCategory> categoryRepository,
    ISystemNotificationService notificationService) : ICommandHandler<PayBusinessTripAdvanceCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(PayBusinessTripAdvanceCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        var advance = tripCase?.AdvanceClaim;
        if (tripCase == null || advance == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy phiếu ứng");

        if (advance.Status != AdvanceRequestStatus.Approved)
            return AppResponse<BusinessTripCaseDto>.Error("Chỉ chi ứng đã duyệt");

        if (advance.IsPaid)
            return AppResponse<BusinessTripCaseDto>.Success(
                await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));

        var method = ParsePaymentMethod(request.PaymentMethod);
        var methodLabel = GetPaymentMethodLabel(method);
        var marker = $"Tự động tạo từ ứng công tác #{advance.Id}";

        var pendingCash = await cashTransactionRepository.GetSingleAsync(
            c => c.IsActive && c.Deleted == null && c.InternalNote != null
                 && c.InternalNote.Contains(advance.Id.ToString()) && !c.IsPaid, cancellationToken: ct);

        if (pendingCash != null)
        {
            pendingCash.PaymentMethod = method;
            pendingCash.Status = CashTransactionStatus.Completed;
            pendingCash.IsPaid = true;
            pendingCash.PaidDate = DateTime.UtcNow;
            pendingCash.UpdatedAt = DateTime.UtcNow;
            await cashTransactionRepository.UpdateAsync(pendingCash, ct);
            advance.CashTransactionId = pendingCash.Id;
        }
        else
        {
            var category = await categoryRepository.GetSingleAsync(
                c => c.StoreId == request.StoreId && c.Name == "Ứng công tác"
                     && c.Type == CashTransactionType.Expense && c.IsActive, cancellationToken: ct)
                ?? await categoryRepository.GetSingleAsync(
                    c => c.StoreId == request.StoreId && c.Name == "Ứng lương"
                         && c.Type == CashTransactionType.Expense && c.IsActive, cancellationToken: ct);

            if (category == null)
            {
                category = new TransactionCategory
                {
                    Id = Guid.NewGuid(),
                    Name = "Ứng công tác",
                    Type = CashTransactionType.Expense,
                    IsSystem = true,
                    IsActive = true,
                    StoreId = request.StoreId
                };
                await categoryRepository.AddAsync(category, ct);
            }

            var empName = tripCase.Employee != null
                ? $"{tripCase.Employee.LastName} {tripCase.Employee.FirstName}".Trim()
                : tripCase.EmployeeUser?.FullName ?? "N/A";

            var cash = new CashTransaction
            {
                Id = Guid.NewGuid(),
                TransactionCode = $"CH-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpperInvariant()}",
                Type = CashTransactionType.Expense,
                CategoryId = category.Id,
                Amount = advance.Amount,
                TransactionDate = DateTime.UtcNow,
                Description = $"Chi ứng công tác ({methodLabel}) - {empName}",
                PaymentMethod = method,
                Status = CashTransactionStatus.Completed,
                IsPaid = true,
                PaidDate = DateTime.UtcNow,
                ContactName = empName,
                CreatedByUserId = request.PerformedById,
                InternalNote = marker,
                IsActive = true,
                StoreId = request.StoreId
            };
            await cashTransactionRepository.AddAsync(cash, ct);
            advance.CashTransactionId = cash.Id;
        }

        await paymentTransactionRepository.AddAsync(new PaymentTransaction
        {
            Id = Guid.NewGuid(),
            EmployeeUserId = tripCase.EmployeeUserId ?? Guid.Empty,
            EmployeeId = tripCase.EmployeeId,
            Type = "TravelAdvancePayment",
            TransactionDate = DateTime.UtcNow,
            Amount = advance.Amount,
            Description = $"Chi ứng công tác ({methodLabel}) — {tripCase.CaseCode}",
            PaymentMethod = methodLabel,
            Status = "Completed",
            PerformedById = request.PerformedById,
            Note = advance.Reason
        }, ct);

        advance.IsPaid = true;
        advance.PaymentMethod = methodLabel;
        advance.PaidDate = DateTime.UtcNow;
        tripCase.Status = BusinessTripCaseStatus.AdvancePaid;
        tripCase.AdvanceAmount = advance.Amount;
        tripCase.UpdatedAt = DateTime.UtcNow;
        await advanceRepository.UpdateAsync(advance, ct);
        await caseRepository.UpdateAsync(tripCase, ct);

        try
        {
            if (tripCase.EmployeeUserId.HasValue)
            {
                await notificationService.CreateAndSendAsync(
                    tripCase.EmployeeUserId.Value, NotificationType.Success,
                    "Đã chi ứng công tác",
                    $"{advance.Amount:N0}đ ({methodLabel})",
                    relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                    fromUserId: request.PerformedById, categoryCode: "business_trip", storeId: request.StoreId);
            }
        }
        catch { }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }

    private static PaymentMethodType ParsePaymentMethod(string? method) => method?.ToLowerInvariant() switch
    {
        "banktransfer" or "bank_transfer" or "bank" => PaymentMethodType.BankTransfer,
        "vietqr" or "qr" => PaymentMethodType.VietQR,
        "card" => PaymentMethodType.Card,
        "ewallet" or "e_wallet" or "wallet" => PaymentMethodType.EWallet,
        _ => PaymentMethodType.Cash
    };

    private static string GetPaymentMethodLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Tiền mặt"
    };
}

public record UndoApproveBusinessTripAdvanceCommand(
    Guid StoreId,
    Guid CaseId,
    Guid CurrentUserId) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class UndoApproveBusinessTripAdvanceHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripAdvanceClaim> advanceRepository,
    IRepository<BusinessTripAdvanceApprovalRecord> approvalRecordRepository,
    IRepository<CashTransaction> cashTransactionRepository) : ICommandHandler<UndoApproveBusinessTripAdvanceCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(UndoApproveBusinessTripAdvanceCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        var advance = tripCase?.AdvanceClaim;
        if (advance == null || advance.Status != AdvanceRequestStatus.Approved || advance.IsPaid)
            return AppResponse<BusinessTripCaseDto>.Error("Không thể hoàn duyệt phiếu này");

        foreach (var r in advance.ApprovalRecords)
        {
            r.Status = ApprovalStatus.Pending;
            r.ActualUserId = null;
            r.ActualUserName = null;
            r.ActionDate = null;
            r.Note = null;
            await approvalRecordRepository.UpdateAsync(r, ct);
        }

        advance.Status = AdvanceRequestStatus.Pending;
        advance.ApprovedById = null;
        advance.ApprovedDate = null;
        advance.CurrentApprovalStep = 0;
        tripCase!.Status = BusinessTripCaseStatus.AdvancePending;
        tripCase.UpdatedAt = DateTime.UtcNow;

        var cash = await cashTransactionRepository.GetSingleAsync(
            c => c.IsActive && c.InternalNote != null && c.InternalNote.Contains(advance.Id.ToString()) && !c.IsPaid,
            cancellationToken: ct);
        if (cash != null)
        {
            cash.Status = CashTransactionStatus.Cancelled;
            cash.IsActive = false;
            cash.UpdatedAt = DateTime.UtcNow;
            await cashTransactionRepository.UpdateAsync(cash, ct);
        }

        await advanceRepository.UpdateAsync(advance, ct);
        await caseRepository.UpdateAsync(tripCase, ct);
        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }
}
