using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Ghi sổ công nợ (khách hàng / nhà cung cấp). Gọi NGAY SAU khi đổi CurrentDebt, trước SaveChanges của nơi gọi
/// — dòng sổ lưu cùng giao dịch với số dư. Delta = số dư mới − số dư cũ (đã chặn âm như số dư thật).
/// </summary>
internal static class PosDebtLedger
{
    public const string Customer = "customer";
    public const string Supplier = "supplier";

    public static void Add(
        ZKTecoDbContext db, Guid storeId, string partyType, Guid partyId,
        decimal before, decimal after, string docType, Guid? docId, string? docNo, string? note = null,
        DateTime? at = null, string? by = null, bool keepZero = false)
    {
        var delta = after - before;
        // keepZero: chứng từ cần biết «đã giảm bao nhiêu» khi hủy (vd trả hàng NCC lúc đã hết nợ → 0).
        if (delta == 0 && !keepZero) return;
        db.PosDebtLedgerEntries.Add(new PosDebtLedgerEntry
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            PartyType = partyType,
            PartyId = partyId,
            At = at ?? DateTime.UtcNow,
            DocType = docType,
            DocId = docId,
            DocNo = docNo is { Length: > 60 } ? docNo[..60] : docNo,
            Delta = delta,
            BalanceAfter = after,
            Note = note is { Length: > 300 } ? note[..300] : note,
            CreatedBy = by,
        });
    }
}
