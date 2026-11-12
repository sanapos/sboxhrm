using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Bấm chip «Tổng quan» tài chính nhân sự → từng khoản đã cộng vào số trên chip.</summary>
public partial class HrFinanceController
{
    /// <summary>
    /// kind: advancePaid | advanceToDeduct | bonus | penalty (thủ công + phiếu phạt) | tripAdvancePaid | tripSettled | cashIn | cashOut.
    /// Điều kiện lọc giống hệt <see cref="Summary"/>; Amount của từng dòng cộng lại = số trên chip.
    /// </summary>
    [HttpGet("summary/drill")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AdvanceRequests", "BonusPenalty", "PenaltyTickets", "CashTransaction", "Transaction")]
    public async Task<ActionResult<AppResponse<List<HrFinItemDto>>>> DrillSummary(
        [FromQuery] string kind, [FromQuery] int? year, [FromQuery] int? month)
    {
        if (!SeesStoreMoney)
            return Ok(AppResponse<List<HrFinItemDto>>.Fail("Chỉ quản lý / kế toán xem được tổng quan tài chính nhân sự"));
        var (rangeFrom, rangeTo) = MonthRange(year, month);
        var storeId = RequiredStoreId;
        var lk = await LookupAsync();
        var items = new List<HrFinItemDto>();

        switch (kind)
        {
            case "advancePaid":
            case "advanceToDeduct":
            {
                var advances = await db.AdvanceRequests.AsNoTracking()
                    .Where(a => a.StoreId == storeId && a.Status == AdvanceRequestStatus.Approved && a.IsPaid)
                    .ToListAsync();
                // Tên NV: tra cả cửa hàng (tổng không lọc chi nhánh đang xem).
                var names = await AllEmployeeNamesAsync(storeId);
                foreach (var a in advances)
                {
                    decimal amount;
                    if (kind == "advancePaid")
                    {
                        if (!(a.PaidDate >= rangeFrom && a.PaidDate < rangeTo)) continue;
                        amount = a.ApprovedAmount ?? a.Amount;
                    }
                    else
                    {
                        amount = a.InstallmentCount <= 0
                            ? (a.PaidDate >= rangeFrom && a.PaidDate < rangeTo ? a.ApprovedAmount ?? a.Amount : 0)
                            : HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, rangeFrom.Year, rangeFrom.Month);
                        if (amount == 0) continue;
                    }
                    var it = AdvanceItem(a, Find(lk.ById, lk.ByUser, a.EmployeeId, a.EmployeeUserId));
                    FillName(it, names, a.EmployeeId, a.EmployeeUserId);
                    it.Amount = amount;
                    items.Add(it);
                }
                break;
            }
            case "bonus":
            case "penalty":
            {
                var type = kind == "bonus" ? "Bonus" : "Penalty";
                var rewards = await RewardQuery(lk)
                    .Where(t => t.TransactionDate >= rangeFrom && t.TransactionDate < rangeTo
                        && (t.Status == "Completed" || t.Status == "Approved") && t.Type == type)
                    .ToListAsync();
                items.AddRange(rewards.Select(t => TxItem(t, Find(lk.ById, lk.ByUser, t.EmployeeId, t.EmployeeUserId))));
                if (kind == "penalty")
                {
                    var tickets = await db.PenaltyTickets.AsNoTracking()
                        .Where(t => t.StoreId == storeId && t.ViolationDate >= rangeFrom && t.ViolationDate < rangeTo
                            && (t.Status == PenaltyTicketStatus.Approved || t.Status == PenaltyTicketStatus.AutoApproved))
                        .ToListAsync();
                    var names = await AllEmployeeNamesAsync(storeId);
                    foreach (var t in tickets)
                    {
                        var it = TicketItem(t, lk.ById.GetValueOrDefault(t.EmployeeId));
                        FillName(it, names, t.EmployeeId, null);
                        items.Add(it);
                    }
                }
                break;
            }
            case "tripAdvancePaid":
            {
                var rows = await (from c in db.BusinessTripAdvanceClaims.AsNoTracking()
                                  join k in db.BusinessTripCases.AsNoTracking() on c.CaseId equals k.Id
                                  where c.StoreId == storeId && c.IsPaid && c.PaidDate >= rangeFrom && c.PaidDate < rangeTo
                                  select new { c, k.CaseCode, k.Title, k.EmployeeId, k.EmployeeUserId })
                    .ToListAsync();
                var names = await AllEmployeeNamesAsync(storeId);
                foreach (var x in rows)
                {
                    var it = Fill(new HrFinItemDto
                    {
                        Kind = "trip_advance", Id = x.c.Id, Code = x.CaseCode, CaseId = x.c.CaseId,
                        Title = "Ứng công tác — " + x.Title, Subtitle = x.c.Reason,
                        Amount = x.c.Amount, Direction = "in", Status = "Paid", Date = x.c.PaidDate ?? x.c.RequestDate,
                    }, Find(lk.ById, lk.ByUser, x.EmployeeId, x.EmployeeUserId));
                    FillName(it, names, x.EmployeeId, x.EmployeeUserId);
                    items.Add(it);
                }
                break;
            }
            case "tripSettled":
            {
                var rows = await (from c in db.BusinessTripSettlementClaims.AsNoTracking()
                                  join k in db.BusinessTripCases.AsNoTracking() on c.CaseId equals k.Id
                                  where c.StoreId == storeId && c.Status == AdvanceRequestStatus.Approved
                                        && c.ApprovedDate >= rangeFrom && c.ApprovedDate < rangeTo
                                  select new { c, k.CaseCode, k.Title, k.EmployeeId, k.EmployeeUserId })
                    .ToListAsync();
                var names = await AllEmployeeNamesAsync(storeId);
                foreach (var x in rows)
                {
                    var it = Fill(new HrFinItemDto
                    {
                        Kind = "trip_settlement", Id = x.c.Id, Code = x.CaseCode, CaseId = x.c.CaseId,
                        Title = "Quyết toán công tác — " + x.Title,
                        Subtitle = Services.VnMoneyText.Normalize($"Tổng chi {x.c.TotalAmount:N0}đ, đã ứng {x.c.AdvanceAmount:N0}đ"),
                        Amount = x.c.TotalAmount, Direction = "in", Status = x.c.Status.ToString(),
                        Date = x.c.ApprovedDate ?? x.c.SubmittedAt ?? x.c.CreatedAt,
                    }, Find(lk.ById, lk.ByUser, x.EmployeeId, x.EmployeeUserId));
                    FillName(it, names, x.EmployeeId, x.EmployeeUserId);
                    items.Add(it);
                }
                break;
            }
            case "cashIn":
            case "cashOut":
            {
                var type = kind == "cashIn" ? CashTransactionType.Income : CashTransactionType.Expense;
                var rows = await db.CashTransactions.AsNoTracking()
                    .Where(c => c.StoreId == storeId && c.IsActive && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= rangeFrom && c.TransactionDate < rangeTo && c.Type == type)
                    .Select(c => new
                    {
                        c.Id, c.TransactionCode, c.Description, c.Amount, c.TransactionDate, c.ContactName,
                        CategoryName = c.Category != null ? c.Category.Name : null,
                    })
                    .ToListAsync();
                items.AddRange(rows.Select(c => new HrFinItemDto
                {
                    Kind = "cash",
                    Id = c.Id,
                    Code = c.TransactionCode,
                    EmployeeName = c.ContactName ?? "",
                    Title = string.IsNullOrWhiteSpace(c.Description) ? (c.CategoryName ?? "Phiếu quỹ") : c.Description,
                    Subtitle = c.CategoryName,
                    Amount = c.Amount,
                    Direction = type == CashTransactionType.Expense ? "out" : "in",
                    Status = "Completed",
                    Date = c.TransactionDate,
                }));
                break;
            }
            default:
                return Ok(AppResponse<List<HrFinItemDto>>.Fail("Loại số liệu không hợp lệ"));
        }

        return Ok(AppResponse<List<HrFinItemDto>>.Success(items.OrderByDescending(i => i.Amount).ToList()));
    }

    /// <summary>Tên mọi nhân viên của cửa hàng (không lọc chi nhánh) — cho các tổng tính trên cả cửa hàng.</summary>
    private async Task<Dictionary<Guid, (string Name, string Code)>> AllEmployeeNamesAsync(Guid storeId)
    {
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId)
            .Select(e => new { e.Id, e.ApplicationUserId, Name = (e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode })
            .ToListAsync();
        var map = new Dictionary<Guid, (string, string)>();
        foreach (var r in rows)
        {
            map[r.Id] = (r.Name, r.EmployeeCode);
            if (r.ApplicationUserId.HasValue) map.TryAdd(r.ApplicationUserId.Value, (r.Name, r.EmployeeCode));
        }
        return map;
    }

    private static void FillName(HrFinItemDto it, Dictionary<Guid, (string Name, string Code)> names, Guid? employeeId, Guid? userId)
    {
        if (!string.IsNullOrEmpty(it.EmployeeName)) return;
        if ((employeeId.HasValue && names.TryGetValue(employeeId.Value, out var n))
            || (userId.HasValue && names.TryGetValue(userId.Value, out n)))
        {
            it.EmployeeId ??= employeeId;
            it.EmployeeName = n.Name;
            it.EmployeeCode = n.Code;
        }
    }
}
