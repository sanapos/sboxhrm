using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.BusinessTrip;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.BusinessTrip;

public record SaveBusinessTripSettlementCommand(
    Guid StoreId,
    Guid CaseId,
    Guid CurrentUserId,
    string? Note,
    List<UpsertBusinessTripExpenseLineDto> Lines,
    bool IsPrivileged = false) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class SaveBusinessTripSettlementHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripSettlementClaim> settlementRepository,
    IRepository<BusinessTripSettlementApprovalRecord> settlementApprovalRepository,
    IRepository<BusinessTripExpenseLine> lineRepository,
    IRepository<BusinessTripExpenseAttachment> attachmentRepository,
    IRepository<BusinessTripExpenseCategory> categoryRepository,
    IRepository<AppSettings> appSettingsRepository,
    IRepository<Employee> employeeRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService,
    INotificationTargetResolver targetResolver) : ICommandHandler<SaveBusinessTripSettlementCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(SaveBusinessTripSettlementCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        if (tripCase == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy hồ sơ công tác");

        var deny = BusinessTripAccess.DenyIfCannotAccess(tripCase, request.CurrentUserId, request.IsPrivileged);
        if (deny != null)
            return AppResponse<BusinessTripCaseDto>.Error(deny);

        if (tripCase.Status == BusinessTripCaseStatus.Draft && tripCase.AdvanceClaim == null)
        {
            tripCase.AdvanceAmount = 0;
            tripCase.Status = BusinessTripCaseStatus.AdvancePaid;
        }
        else if (tripCase.Status != BusinessTripCaseStatus.AdvancePaid
            && tripCase.Status != BusinessTripCaseStatus.SettlementDraft
            && tripCase.SettlementClaim?.Status is not AdvanceRequestStatus.Rejected)
            return AppResponse<BusinessTripCaseDto>.Error("Chưa thể hoạch toán ở trạng thái hiện tại");

        if (request.Lines.Count == 0)
            return AppResponse<BusinessTripCaseDto>.Error("Cần ít nhất một dòng chi phí");

        var categories = await categoryRepository.GetAllAsync(c => c.StoreId == request.StoreId && c.IsActive, cancellationToken: ct);
        foreach (var line in request.Lines)
        {
            if (line.Amount <= 0)
                return AppResponse<BusinessTripCaseDto>.Error("Số tiền dòng chi phải lớn hơn 0");
            // Có HĐ: khuyến nghị đính kèm, nhưng không chặn gửi nếu NV chưa kịp chụp ảnh.
            if (line.CategoryId.HasValue)
            {
                var cat = categories.FirstOrDefault(c => c.Id == line.CategoryId);
                if (cat?.RequiresInvoice == true && !line.HasInvoice)
                    return AppResponse<BusinessTripCaseDto>.Error($"Hạn mục {cat.Name} bắt buộc đánh dấu có hóa đơn");
            }
        }

        var advanceAmount = tripCase.AdvanceClaim?.Amount ?? tripCase.AdvanceAmount;
        var total = request.Lines.Sum(l => l.Amount);
        var withInv = request.Lines.Where(l => l.HasInvoice).Sum(l => l.Amount);

        BusinessTripSettlementClaim settlement;
        if (tripCase.SettlementClaim != null)
        {
            settlement = tripCase.SettlementClaim;
            var oldLines = await lineRepository.GetAllAsync(l => l.SettlementClaimId == settlement.Id, cancellationToken: ct);
            foreach (var ol in oldLines)
            {
                var atts = await attachmentRepository.GetAllAsync(a => a.LineId == ol.Id, cancellationToken: ct);
                foreach (var a in atts) await attachmentRepository.DeleteAsync(a, ct);
                await lineRepository.DeleteAsync(ol, ct);
            }

            var oldApprovals = await settlementApprovalRepository.GetAllAsync(
                r => r.SettlementClaimId == settlement.Id, cancellationToken: ct);
            foreach (var r in oldApprovals) await settlementApprovalRepository.DeleteAsync(r, ct);

            // AsNoTracking load still keeps deleted children in navigation collections.
            // Clearing prevents EF Update() from re-attaching them → DbUpdateConcurrencyException.
            settlement.Lines.Clear();
            settlement.ApprovalRecords.Clear();
        }
        else
        {
            settlement = new BusinessTripSettlementClaim
            {
                Id = Guid.NewGuid(),
                CaseId = tripCase.Id,
                StoreId = request.StoreId,
                IsActive = true
            };
            await settlementRepository.AddAsync(settlement, ct);
        }

        settlement.Note = request.Note;
        settlement.AdvanceAmount = advanceAmount;
        settlement.TotalAmount = total;
        settlement.TotalWithInvoice = withInv;
        settlement.TotalWithoutInvoice = total - withInv;
        settlement.BalanceAmount = total - advanceAmount;
        settlement.Status = AdvanceRequestStatus.Pending;
        settlement.SubmittedAt = DateTime.UtcNow;
        settlement.RejectionReason = null;
        settlement.IsExtraPaid = false;
        settlement.ApprovedById = null;
        settlement.ApprovedDate = null;
        settlement.SettlementType = BusinessTripSettlementType.Balanced;

        var totalLevels = await BusinessTripApprovalChainHelper.ReadApprovalLevelsAsync(
            appSettingsRepository, request.StoreId,
            "business_trip_settlement_approval_levels", "advance_approval_levels", ct);
        settlement.TotalApprovalLevels = totalLevels;
        settlement.CurrentApprovalStep = 0;

        var managerChain = await BusinessTripApprovalChainHelper.BuildManagerChainAsync(
            employeeRepository, userManager, tripCase.EmployeeUserId, ct);
        var adminFallback = await BusinessTripApprovalChainHelper.ResolveAdminFallbackAsync(
            userManager, request.StoreId, tripCase.EmployeeUserId, ct);
        var steps = BusinessTripApprovalChainHelper.BuildSteps(totalLevels, managerChain, adminFallback);

        foreach (var step in steps)
        {
            await settlementApprovalRepository.AddAsync(new BusinessTripSettlementApprovalRecord
            {
                Id = Guid.NewGuid(),
                SettlementClaimId = settlement.Id,
                StoreId = request.StoreId,
                StepOrder = step.StepOrder,
                StepName = step.StepName,
                AssignedUserId = step.AssignedUserId,
                AssignedUserName = step.AssignedUserName,
                Status = ApprovalStatus.Pending
            }, ct);
        }

        var sort = 0;
        foreach (var lineDto in request.Lines)
        {
            var line = new BusinessTripExpenseLine
            {
                Id = Guid.NewGuid(),
                SettlementClaimId = settlement.Id,
                CategoryId = lineDto.CategoryId,
                ExpenseDate = lineDto.ExpenseDate,
                Amount = lineDto.Amount,
                Description = lineDto.Description,
                Note = lineDto.Note,
                HasInvoice = lineDto.HasInvoice,
                InvoiceNumber = lineDto.InvoiceNumber,
                InvoiceDate = lineDto.InvoiceDate,
                SortOrder = lineDto.SortOrder > 0 ? lineDto.SortOrder : sort++,
                IsActive = true
            };
            await lineRepository.AddAsync(line, ct);

            if (lineDto.Attachments != null)
            {
                foreach (var att in lineDto.Attachments)
                {
                    await attachmentRepository.AddAsync(new BusinessTripExpenseAttachment
                    {
                        Id = Guid.NewGuid(),
                        LineId = line.Id,
                        FileName = att.FileName,
                        FileUrl = att.FileUrl,
                        ContentType = att.ContentType,
                        FileSize = att.FileSize,
                        AttachmentType = (BusinessTripAttachmentType)att.AttachmentType,
                        StoreId = request.StoreId,
                        IsActive = true
                    }, ct);
                }
            }
        }

        // Update scalars only — do not re-attach child graphs already saved above.
        BusinessTripCaseLoader.DetachSettlementNavigations(settlement);
        await settlementRepository.UpdateAsync(settlement, ct);
        tripCase.Status = BusinessTripCaseStatus.SettlementPending;
        tripCase.SettledAmount = total;
        tripCase.BalanceAmount = settlement.BalanceAmount;
        tripCase.UpdatedAt = DateTime.UtcNow;
        BusinessTripCaseLoader.DetachNavigations(tripCase);
        await caseRepository.UpdateAsync(tripCase, ct);

        try
        {
            var targets = await targetResolver.ResolveManagersAsync(tripCase.EmployeeUserId, request.StoreId, 2, ct);
            var set = new HashSet<Guid>(targets);
            var first = steps.FirstOrDefault();
            if (first.AssignedUserId.HasValue) set.Add(first.AssignedUserId.Value);
            if (tripCase.EmployeeUserId.HasValue) set.Remove(tripCase.EmployeeUserId.Value);
            if (set.Count > 0)
            {
                await notificationService.CreateAndSendToUsersAsync(
                    set, NotificationType.ApprovalRequired,
                    "Hoạch toán công tác chờ duyệt",
                    $"{tripCase.CaseCode} — {total:N0}đ",
                    relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                    fromUserId: tripCase.EmployeeUserId, categoryCode: "business_trip", storeId: request.StoreId);
            }
        }
        catch { }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }
}

public record ApproveBusinessTripSettlementCommand(
    Guid StoreId,
    Guid CaseId,
    Guid ApprovedById,
    bool IsApproved,
    string? RejectionReason) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class ApproveBusinessTripSettlementHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripSettlementClaim> settlementRepository,
    IRepository<BusinessTripSettlementApprovalRecord> approvalRecordRepository,
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService) : ICommandHandler<ApproveBusinessTripSettlementCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(ApproveBusinessTripSettlementCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        var settlement = tripCase?.SettlementClaim;
        if (settlement == null)
            return AppResponse<BusinessTripCaseDto>.Error("Không tìm thấy phiếu hoạch toán");

        if (settlement.Status != AdvanceRequestStatus.Pending)
            return AppResponse<BusinessTripCaseDto>.Error("Phiếu hoạch toán đã được xử lý");

        var approver = await userManager.FindByIdAsync(request.ApprovedById.ToString());
        var approverName = approver?.FullName ?? approver?.Email ?? "Unknown";
        var records = settlement.ApprovalRecords.OrderBy(r => r.StepOrder).ToList();

        if (request.IsApproved)
        {
            var current = records.FirstOrDefault(r => r.Status == ApprovalStatus.Pending);
            if (current != null)
            {
                current.Status = ApprovalStatus.Approved;
                current.ActualUserId = request.ApprovedById;
                current.ActualUserName = approverName;
                current.ActionDate = DateTime.UtcNow;
                settlement.CurrentApprovalStep = current.StepOrder;
                await approvalRecordRepository.UpdateAsync(current, ct);
            }

            var next = records.FirstOrDefault(r => r.StepOrder > settlement.CurrentApprovalStep && r.Status == ApprovalStatus.Pending);
            if (next != null)
            {
                BusinessTripCaseLoader.DetachSettlementNavigations(settlement);
                await settlementRepository.UpdateAsync(settlement, ct);
                return AppResponse<BusinessTripCaseDto>.Success(
                    await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase!.Id, request.StoreId, ct));
            }

            settlement.Status = AdvanceRequestStatus.Approved;
            settlement.ApprovedById = request.ApprovedById;
            settlement.ApprovedDate = DateTime.UtcNow;
            ApplySettlementType(settlement);
            tripCase!.Status = settlement.SettlementType == BusinessTripSettlementType.Balanced
                ? BusinessTripCaseStatus.Closed
                : BusinessTripCaseStatus.Settling;
            tripCase.BalanceAmount = settlement.BalanceAmount;
            tripCase.UpdatedAt = DateTime.UtcNow;
            BusinessTripCaseLoader.DetachSettlementNavigations(settlement);
            BusinessTripCaseLoader.DetachNavigations(tripCase);
            await settlementRepository.UpdateAsync(settlement, ct);
            await caseRepository.UpdateAsync(tripCase, ct);

            try
            {
                if (tripCase.EmployeeUserId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        tripCase.EmployeeUserId.Value, NotificationType.Success,
                        "Hoạch toán công tác đã duyệt",
                        SettlementMessage(settlement),
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
            settlement.Status = AdvanceRequestStatus.Rejected;
            settlement.RejectionReason = request.RejectionReason;
            tripCase!.Status = BusinessTripCaseStatus.SettlementDraft;
            tripCase.UpdatedAt = DateTime.UtcNow;
            BusinessTripCaseLoader.DetachSettlementNavigations(settlement);
            BusinessTripCaseLoader.DetachNavigations(tripCase);
            await settlementRepository.UpdateAsync(settlement, ct);
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
                        request.RejectionReason != null
                            && request.RejectionReason.Contains("Bổ sung", StringComparison.OrdinalIgnoreCase)
                            ? "Yêu cầu bổ sung giấy tờ công tác"
                            : "Hoạch toán công tác bị từ chối",
                        $"{tripCase.CaseCode}: {reason}",
                        relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                        fromUserId: request.ApprovedById, categoryCode: "business_trip", storeId: request.StoreId);
                }
            }
            catch { }
        }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase!.Id, request.StoreId, ct));
    }

    internal static void ApplySettlementType(BusinessTripSettlementClaim settlement)
    {
        if (settlement.BalanceAmount > 0)
            settlement.SettlementType = BusinessTripSettlementType.PayExtra;
        else if (settlement.BalanceAmount < 0)
            settlement.SettlementType = BusinessTripSettlementType.SurplusAsAdvance;
        else
            settlement.SettlementType = BusinessTripSettlementType.Balanced;
    }

    private static string SettlementMessage(BusinessTripSettlementClaim s) => s.SettlementType switch
    {
        BusinessTripSettlementType.PayExtra => $"Thiếu {s.BalanceAmount:N0}đ — chờ chi bù",
        BusinessTripSettlementType.SurplusAsAdvance => $"Dư {Math.Abs(s.BalanceAmount):N0}đ — ghi nợ ứng lương",
        BusinessTripSettlementType.SurplusRefunded => $"Dư {Math.Abs(s.BalanceAmount):N0}đ — chờ thu hoàn",
        _ => "Quyết toán khớp — đã đóng hồ sơ"
    };
}

public record PayBusinessTripSettlementExtraCommand(
    Guid StoreId,
    Guid CaseId,
    Guid PerformedById,
    string? PaymentMethod) : ICommand<AppResponse<BusinessTripCaseDto>>;

public class PayBusinessTripSettlementExtraHandler(
    IRepository<BusinessTripCase> caseRepository,
    IRepository<BusinessTripSettlementClaim> settlementRepository,
    IRepository<CashTransaction> cashTransactionRepository,
    IRepository<TransactionCategory> categoryRepository,
    ISystemNotificationService notificationService) : ICommandHandler<PayBusinessTripSettlementExtraCommand, AppResponse<BusinessTripCaseDto>>
{
    public async Task<AppResponse<BusinessTripCaseDto>> Handle(PayBusinessTripSettlementExtraCommand request, CancellationToken ct)
    {
        var tripCase = await BusinessTripCaseLoader.LoadAsync(caseRepository, request.CaseId, request.StoreId, ct);
        var settlement = tripCase?.SettlementClaim;
        if (settlement == null || settlement.SettlementType != BusinessTripSettlementType.PayExtra)
            return AppResponse<BusinessTripCaseDto>.Error("Không có khoản chi bù");

        if (settlement.IsExtraPaid)
            return AppResponse<BusinessTripCaseDto>.Success(
                await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase!.Id, request.StoreId, ct));

        var method = request.PaymentMethod?.ToLowerInvariant() switch
        {
            "banktransfer" or "bank" => PaymentMethodType.BankTransfer,
            "vietqr" or "qr" => PaymentMethodType.VietQR,
            _ => PaymentMethodType.Cash
        };
        var methodLabel = method == PaymentMethodType.BankTransfer ? "Chuyển khoản"
            : method == PaymentMethodType.VietQR ? "VietQR" : "Tiền mặt";
        var marker = $"Tự động tạo từ quyết toán công tác phí #{settlement.Id}";

        var cash = await cashTransactionRepository.GetSingleAsync(
            c => c.IsActive && c.Deleted == null && c.InternalNote != null
                 && c.InternalNote.Contains(settlement.Id.ToString()),
            cancellationToken: ct);

        if (cash != null && !cash.IsPaid)
        {
            cash.PaymentMethod = method;
            cash.Status = CashTransactionStatus.Completed;
            cash.IsPaid = true;
            cash.PaidDate = DateTime.UtcNow;
            cash.UpdatedAt = DateTime.UtcNow;
            await cashTransactionRepository.UpdateAsync(cash, ct);
            settlement.ExtraCashTransactionId = cash.Id;
        }
        else if (cash == null)
        {
            var category = await categoryRepository.GetSingleAsync(
                c => c.StoreId == request.StoreId && c.Name == "Công tác phí"
                     && c.Type == CashTransactionType.Expense && c.IsActive, cancellationToken: ct);
            if (category == null)
            {
                category = new TransactionCategory
                {
                    Id = Guid.NewGuid(),
                    Name = "Công tác phí",
                    Description = "Chi bù công tác phí",
                    Type = CashTransactionType.Expense,
                    IsSystem = true,
                    IsActive = true,
                    StoreId = request.StoreId
                };
                await categoryRepository.AddAsync(category, ct);
            }

            var empName = tripCase!.Employee != null
                ? $"{tripCase.Employee.LastName} {tripCase.Employee.FirstName}".Trim()
                : tripCase.EmployeeUser?.FullName ?? "N/A";

            cash = new CashTransaction
            {
                Id = Guid.NewGuid(),
                TransactionCode = $"CH-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpperInvariant()}",
                Type = CashTransactionType.Expense,
                CategoryId = category.Id,
                Amount = settlement.BalanceAmount,
                TransactionDate = DateTime.UtcNow,
                Description = $"Chi bù công tác phí ({methodLabel}) - {empName}",
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
            settlement.ExtraCashTransactionId = cash.Id;
        }

        settlement.IsExtraPaid = true;
        settlement.ExtraPaymentMethod = methodLabel;
        settlement.ExtraPaidDate = DateTime.UtcNow;
        tripCase!.Status = BusinessTripCaseStatus.Closed;
        tripCase.UpdatedAt = DateTime.UtcNow;
        BusinessTripCaseLoader.DetachSettlementNavigations(settlement);
        BusinessTripCaseLoader.DetachNavigations(tripCase);
        await settlementRepository.UpdateAsync(settlement, ct);
        await caseRepository.UpdateAsync(tripCase, ct);

        try
        {
            if (tripCase.EmployeeUserId.HasValue)
            {
                await notificationService.CreateAndSendAsync(
                    tripCase.EmployeeUserId.Value, NotificationType.Success,
                    "Đã chi bù công tác phí",
                    $"{settlement.BalanceAmount:N0}đ ({methodLabel})",
                    relatedEntityId: tripCase.Id, relatedEntityType: "BusinessTripCase",
                    fromUserId: request.PerformedById, categoryCode: "business_trip", storeId: request.StoreId);
            }
        }
        catch { }

        return AppResponse<BusinessTripCaseDto>.Success(
            await BusinessTripCaseLoader.ToDtoAsync(caseRepository, tripCase.Id, request.StoreId, ct));
    }
}

public record UpsertBusinessTripExpenseCategoryCommand(
    Guid StoreId,
    Guid? Id,
    UpsertBusinessTripExpenseCategoryDto Dto) : ICommand<AppResponse<BusinessTripExpenseCategoryDto>>;

public class UpsertBusinessTripExpenseCategoryHandler(IRepository<BusinessTripExpenseCategory> categoryRepository)
    : ICommandHandler<UpsertBusinessTripExpenseCategoryCommand, AppResponse<BusinessTripExpenseCategoryDto>>
{
    public async Task<AppResponse<BusinessTripExpenseCategoryDto>> Handle(
        UpsertBusinessTripExpenseCategoryCommand request, CancellationToken ct)
    {
        BusinessTripExpenseCategory entity;
        if (request.Id.HasValue)
        {
            entity = await categoryRepository.GetSingleAsync(
                c => c.Id == request.Id && c.StoreId == request.StoreId, cancellationToken: ct)
                ?? throw new InvalidOperationException("not found");
        }
        else
        {
            entity = new BusinessTripExpenseCategory
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                IsActive = true
            };
            await categoryRepository.AddAsync(entity, ct);
        }

        entity.Code = request.Dto.Code.Trim();
        entity.Name = request.Dto.Name.Trim();
        entity.Description = request.Dto.Description;
        entity.MaxAmountPerLine = request.Dto.MaxAmountPerLine;
        entity.MaxAmountPerMonth = request.Dto.MaxAmountPerMonth;
        entity.RequiresInvoice = request.Dto.RequiresInvoice;
        entity.SortOrder = request.Dto.SortOrder;
        entity.UpdatedAt = DateTime.UtcNow;
        await categoryRepository.UpdateAsync(entity, ct);
        return AppResponse<BusinessTripExpenseCategoryDto>.Success(BusinessTripMapper.ToCategoryDto(entity));
    }
}

public record DeleteBusinessTripExpenseCategoryCommand(Guid StoreId, Guid Id)
    : ICommand<AppResponse<bool>>;

public class DeleteBusinessTripExpenseCategoryHandler(IRepository<BusinessTripExpenseCategory> categoryRepository)
    : ICommandHandler<DeleteBusinessTripExpenseCategoryCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteBusinessTripExpenseCategoryCommand request, CancellationToken ct)
    {
        var entity = await categoryRepository.GetSingleAsync(
            c => c.Id == request.Id && c.StoreId == request.StoreId, cancellationToken: ct);
        if (entity == null)
            return AppResponse<bool>.Error("Không tìm thấy loại chi phí");

        entity.IsActive = false;
        entity.UpdatedAt = DateTime.UtcNow;
        await categoryRepository.UpdateAsync(entity, ct);
        return AppResponse<bool>.Success(true);
    }
}

public record SeedBusinessTripExpenseCategoriesCommand(Guid StoreId) : ICommand<AppResponse<int>>;

public class SeedBusinessTripExpenseCategoriesHandler(IRepository<BusinessTripExpenseCategory> categoryRepository)
    : ICommandHandler<SeedBusinessTripExpenseCategoriesCommand, AppResponse<int>>
{
    private static readonly (string Code, string Name, bool RequiresInvoice, int Sort)[] Defaults =
    [
        ("AN", "Tiền ăn", false, 1),
        ("XE", "Tiền xe / đi lại", false, 2),
        ("KS", "Nhà nghỉ / khách sạn", true, 3),
        ("MB", "Vé máy bay", true, 4),
        ("TK", "Tiếp khách", false, 5),
        ("VP", "Văn phòng phẩm", false, 6),
        ("KHAC", "Chi khác", false, 99)
    ];

    public async Task<AppResponse<int>> Handle(SeedBusinessTripExpenseCategoriesCommand request, CancellationToken ct)
    {
        var existingList = (await categoryRepository.GetAllAsync(c => c.StoreId == request.StoreId, cancellationToken: ct)).ToList();
        var byCode = existingList.ToDictionary(c => c.Code, StringComparer.OrdinalIgnoreCase);
        var added = 0;
        foreach (var d in Defaults)
        {
            if (byCode.TryGetValue(d.Code, out var existing))
            {
                // Không ghi đè tên/cấu hình người dùng đã sửa — chỉ bật lại nếu bị tắt.
                if (!existing.IsActive)
                {
                    existing.IsActive = true;
                    await categoryRepository.UpdateAsync(existing, ct);
                }
                continue;
            }
            await categoryRepository.AddAsync(new BusinessTripExpenseCategory
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                Code = d.Code,
                Name = d.Name,
                RequiresInvoice = d.RequiresInvoice,
                SortOrder = d.Sort,
                IsActive = true
            }, ct);
            added++;
        }
        return AppResponse<int>.Success(added);
    }
}
