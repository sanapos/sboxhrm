using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Phiếu thu / chi của chứng từ nhân sự bị xóa hoặc bỏ «đã thanh toán» → trả chứng từ gốc về «chưa thanh toán».
/// Trước đây chỉ xóa mới hoàn tác (và chỉ đọc chuỗi trong ghi chú); bỏ thanh toán thì ứng lương / công tác /
/// thưởng phạt vẫn «đã chi». Lương tính lại riêng qua PayslipPayments.SyncForVoucherAsync.
/// Chưa SaveChanges.
/// </summary>
public static class CashSourceRevert
{
    public static async Task RevertPaidAsync(ZKTecoDbContext db, CashTransaction cash, Guid storeId, bool deleting)
    {
        var src = CashSources.Resolve(cash.SourceType, cash.SourceId, cash.InternalNote);
        if (src == null) return;
        var (type, id) = src.Value;
        var now = DateTime.UtcNow;

        switch (type)
        {
            case CashSources.Advance:
            {
                var advance = await db.AdvanceRequests.AsTracking().FirstOrDefaultAsync(a => a.Id == id);
                if (advance is { IsPaid: true })
                {
                    advance.IsPaid = false;
                    advance.PaidDate = null;
                    advance.PaymentMethod = null;
                    advance.UpdatedAt = now;
                }
                break;
            }
            case CashSources.TripAdvance:
            {
                var claim = await db.BusinessTripAdvanceClaims.AsTracking().Include(a => a.Case)
                    .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId);
                if (claim is { IsPaid: true })
                {
                    claim.IsPaid = false;
                    claim.PaidDate = null;
                    claim.PaymentMethod = null;
                    if (deleting) claim.CashTransactionId = null;
                    claim.UpdatedAt = now;
                    if (claim.Case is { Status: BusinessTripCaseStatus.AdvancePaid })
                    {
                        claim.Case.Status = BusinessTripCaseStatus.AdvanceApproved;
                        claim.Case.UpdatedAt = now;
                    }
                }
                break;
            }
            case CashSources.TripSettlement:
            case CashSources.TripRefund:
            {
                var settlement = await db.BusinessTripSettlementClaims.AsTracking().Include(s => s.Case)
                    .FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId);
                if (settlement is { IsExtraPaid: true })
                {
                    settlement.IsExtraPaid = false;
                    settlement.ExtraPaidDate = null;
                    settlement.ExtraPaymentMethod = null;
                    settlement.UpdatedAt = now;
                    if (settlement.Case is { Status: BusinessTripCaseStatus.Closed })
                    {
                        settlement.Case.Status = BusinessTripCaseStatus.Settling;
                        settlement.Case.UpdatedAt = now;
                    }
                }
                break;
            }
            case CashSources.Reward:
            {
                var tx = await db.PaymentTransactions.AsTracking().FirstOrDefaultAsync(t => t.Id == id);
                if (tx != null && !string.IsNullOrEmpty(tx.PaymentMethod) && !PaymentFinanceHelper.IsSalaryDisbursement(tx))
                {
                    tx.PaymentMethod = null;
                    tx.UpdatedAt = now;
                }
                break;
            }
            case CashSources.PenaltyTicket:
            {
                // Phiếu phạt «đã thu» khi phiếu thu liên kết đã thanh toán; xóa phiếu thu → bỏ liên kết để thu lại được.
                if (!deleting) break;
                var ticket = await db.PenaltyTickets.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId);
                if (ticket != null && ticket.CashTransactionId == cash.Id)
                {
                    ticket.CashTransactionId = null;
                    ticket.UpdatedAt = now;
                }
                break;
            }
        }
    }
}
