using ZKTecoADMS.Infrastructure;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Hợp đồng từ báo giá: mốc tiến độ, đợt thanh toán, thu tiền (cọc / các đợt) → phiếu thu quỹ,
/// công nợ hợp đồng. Không chặn chuyển sản xuất khi chưa đủ cọc.
/// </summary>
public partial class PosQuotesController
{
    public record ContractStageInput(
        string? Id,
        string Title,
        decimal? Percent,
        decimal Amount,
        DateTime? DueDate,
        string? Note);

    public record ContractSaveDto(
        string? ContractNo,
        DateTime? ContractSignedAt,
        DateTime? ProductionDueAt,
        DateTime? InstallDueAt,
        DateTime? HandoverDueAt,
        string? ContractNote,
        List<ContractStageInput>? Stages);

    public record ContractPaymentInput(
        decimal Amount,
        DateTime? PaidAt,
        string? PaymentMethod,
        string? BankAccountId,
        string? StageId,
        string? Note);

    public record ContractStageView(
        Guid Id, int SortOrder, string Title, decimal? Percent, decimal Amount,
        DateTime? DueDate, string? Note, decimal Paid, decimal Remaining, string Status);

    public record ContractPaymentView(
        Guid Id, Guid? StageId, string? StageTitle, decimal Amount, DateTime PaidAt,
        string? PaymentMethod, string? Note, string? CollectedBy,
        Guid? CashTransactionId, string? CashCode);

    public record ContractView(
        Guid QuoteId, string QuoteNo, string Status, string CommercialStage,
        string? CustomerName, string? CustomerPhone, string? CustomerAddress,
        decimal Total, decimal DepositAmount,
        string? ContractNo, DateTime? ContractSignedAt, DateTime? ProductionDueAt,
        DateTime? InstallDueAt, DateTime? HandoverDueAt, string? ContractNote,
        decimal Collected, decimal Remaining, decimal OverdueAmount,
        DateTime? NextDueDate, string? NextDueTitle,
        List<ContractStageView> Stages, List<ContractPaymentView> Payments);

    public record ContractSummary(
        Guid QuoteId, string QuoteNo, string? ContractNo, string CommercialStage,
        string? CustomerName, string? CustomerPhone,
        decimal Total, decimal Collected, decimal Remaining, decimal OverdueAmount,
        DateTime? NextDueDate, string? NextDueTitle,
        DateTime? ContractSignedAt, DateTime? ProductionDueAt, DateTime? InstallDueAt, DateTime? HandoverDueAt,
        int StageCount);

    [HttpGet("{id:guid}/contract")]
    [RequireModulePermission("PosContracts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ContractView>>> GetContract(Guid id)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<ContractView>.Fail("Không tìm thấy báo giá"));
        return Ok(AppResponse<ContractView>.Success(await BuildContractViewAsync(quote)));
    }

    [HttpPut("{id:guid}/contract")]
    [RequireModulePermission("PosContracts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ContractView>>> SaveContract(Guid id, [FromBody] ContractSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<ContractView>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<ContractView>.Fail("Không có quyền sửa hợp đồng của nhân viên khác"));
        if (quote.Status is PosQuoteStatus.Cancelled or PosQuoteStatus.Rejected)
            return BadRequest(AppResponse<ContractView>.Fail("Báo giá đã hủy / bị từ chối — không lập hợp đồng"));

        var inputs = (dto.Stages ?? [])
            .Where(s => !string.IsNullOrWhiteSpace(s.Title) || s.Amount > 0 || s.Percent > 0)
            .ToList();
        if (inputs.Count > 20)
            return BadRequest(AppResponse<ContractView>.Fail("Tối đa 20 đợt thanh toán"));

        var now = DateTime.UtcNow;
        quote.ContractNo = Trim(dto.ContractNo, 50);
        quote.ContractSignedAt = dto.ContractSignedAt;
        quote.ProductionDueAt = dto.ProductionDueAt;
        quote.InstallDueAt = dto.InstallDueAt;
        quote.HandoverDueAt = dto.HandoverDueAt;
        quote.ContractNote = Trim(dto.ContractNote, 1000);
        if (quote.ContractSignedAt.HasValue && quote.CommercialStage < PosQuoteCommercialStage.Contracted)
            quote.CommercialStage = PosQuoteCommercialStage.Contracted;
        quote.UpdatedAt = now;
        quote.UpdatedBy = CurrentUserEmail;

        var existing = await dbContext.Set<PosQuotePaymentStage>().AsTracking()
            .Where(s => s.QuoteId == id && s.StoreId == storeId && s.Deleted == null)
            .ToListAsync();
        var kept = new HashSet<Guid>();
        var sort = 0;
        foreach (var input in inputs)
        {
            var pct = input.Percent is > 0 and <= 100 ? input.Percent : null;
            var amount = pct.HasValue
                ? Round0(quote.Total * pct.Value / 100m)
                : Round0(Math.Max(0, input.Amount));
            var title = Trim(input.Title, 200) ?? $"Đợt {sort + 1}";
            var stage = ParseGuid(input.Id) is Guid sid
                ? existing.FirstOrDefault(s => s.Id == sid && !kept.Contains(s.Id))
                : null;
            if (stage == null)
            {
                stage = new PosQuotePaymentStage
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    QuoteId = id,
                    CreatedBy = CurrentUserEmail,
                    IsActive = true,
                };
                dbContext.Set<PosQuotePaymentStage>().Add(stage);
            }
            else
            {
                stage.UpdatedAt = now;
                stage.UpdatedBy = CurrentUserEmail;
            }
            kept.Add(stage.Id);
            stage.SortOrder = sort++;
            stage.Title = title;
            stage.Percent = pct;
            stage.Amount = amount;
            stage.DueDate = input.DueDate;
            stage.Note = Trim(input.Note, 500);
        }
        foreach (var gone in existing.Where(s => !kept.Contains(s.Id)))
        {
            gone.Deleted = now;
            gone.DeletedBy = CurrentUserEmail;
        }

        AddActivity(quote, "Contract",
            $"Cập nhật hợp đồng{(quote.ContractNo is { } no ? " " + no : "")}: {inputs.Count} đợt thanh toán");
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ContractView>.Success(await BuildContractViewAsync(quote)));
    }

    [HttpPost("{id:guid}/payments")]
    [RequireModulePermission("PosContracts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ContractView>>> AddContractPayment(
        Guid id, [FromBody] ContractPaymentInput dto)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<ContractView>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<ContractView>.Fail("Không có quyền thu tiền hợp đồng của nhân viên khác"));
        if (quote.Status is PosQuoteStatus.Cancelled or PosQuoteStatus.Rejected)
            return BadRequest(AppResponse<ContractView>.Fail("Báo giá đã hủy / bị từ chối — không thu tiền"));

        var amount = Round0(dto.Amount);
        if (amount <= 0)
            return BadRequest(AppResponse<ContractView>.Fail("Số tiền thu phải lớn hơn 0"));
        var collected = await dbContext.Set<PosQuotePayment>().AsNoTracking()
            .Where(p => p.QuoteId == id && p.StoreId == storeId && p.Deleted == null)
            .SumAsync(p => (decimal?)p.Amount) ?? 0;
        var remaining = Math.Max(0, quote.Total - collected);
        if (amount > remaining)
            return BadRequest(AppResponse<ContractView>.Fail(
                $"Số thu {amount:#,##0} vượt số còn phải thu {remaining:#,##0}. Sửa báo giá nếu hợp đồng phát sinh thêm."));

        PosQuotePaymentStage? stage = null;
        if (ParseGuid(dto.StageId) is Guid sid)
            stage = await dbContext.Set<PosQuotePaymentStage>().AsNoTracking()
                .FirstOrDefaultAsync(s => s.Id == sid && s.QuoteId == id && s.Deleted == null);

        var payment = new PosQuotePayment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            QuoteId = id,
            StageId = stage?.Id,
            Amount = amount,
            PaidAt = dto.PaidAt ?? DateTime.UtcNow,
            PaymentMethod = Trim(dto.PaymentMethod, 50) ?? "Tiền mặt",
            BankAccountId = ParseGuid(dto.BankAccountId),
            Note = Trim(dto.Note, 500),
            CollectedBy = await EmployeeNameAsync(EmployeeId) ?? CurrentUserEmail,
            CreatedBy = CurrentUserEmail,
            IsActive = true,
        };
        var cash = await PosFinanceSyncHelper.AddQuoteContractReceiptAsync(
            dbContext, quote, payment, stage?.Title, CurrentUserId);
        payment.CashTransactionId = cash?.Id;
        dbContext.Set<PosQuotePayment>().Add(payment);
        if (quote.CommercialStage < PosQuoteCommercialStage.Contracted)
            quote.CommercialStage = PosQuoteCommercialStage.Contracted;
        quote.UpdatedAt = DateTime.UtcNow;
        quote.UpdatedBy = CurrentUserEmail;
        AddActivity(quote, "Payment",
            $"Thu {amount:#,##0}đ{(stage != null ? " — " + stage.Title : "")} ({payment.PaymentMethod})");
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ContractView>.Success(await BuildContractViewAsync(quote)));
    }

    /// <summary>Hủy lần thu: phiếu thu quỹ chuyển «Đã hủy», số đã thu của hợp đồng giảm tương ứng.</summary>
    [HttpDelete("{id:guid}/payments/{paymentId:guid}")]
    [RequireModulePermission("PosContracts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<ContractView>>> CancelContractPayment(Guid id, Guid paymentId)
    {
        var storeId = RequiredStoreId;
        var quote = await dbContext.PosQuotes.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound(AppResponse<ContractView>.Fail("Không tìm thấy báo giá"));
        if (!CanMutateOwn(quote))
            return StatusCode(403, AppResponse<ContractView>.Fail("Không có quyền hủy phiếu thu hợp đồng của nhân viên khác"));
        var payment = await dbContext.Set<PosQuotePayment>().AsTracking()
            .FirstOrDefaultAsync(p => p.Id == paymentId && p.QuoteId == id && p.StoreId == storeId && p.Deleted == null);
        if (payment == null)
            return NotFound(AppResponse<ContractView>.Fail("Không tìm thấy lần thu"));

        var now = DateTime.UtcNow;
        payment.Deleted = now;
        payment.DeletedBy = CurrentUserEmail;
        if (payment.CashTransactionId is Guid cashId)
        {
            var cash = await dbContext.CashTransactions.AsTracking()
                .FirstOrDefaultAsync(c => c.Id == cashId && c.StoreId == storeId);
            if (cash != null && cash.Status != CashTransactionStatus.Cancelled)
            {
                cash.Status = CashTransactionStatus.Cancelled;
                cash.InternalNote = (cash.InternalNote + " | hủy từ hợp đồng").Trim();
                cash.UpdatedAt = now;
                cash.UpdatedBy = CurrentUserEmail;
            }
        }
        AddActivity(quote, "Payment", $"Hủy lần thu {payment.Amount:#,##0}đ ngày {payment.PaidAt.AddHours(7):dd/MM/yyyy}");
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ContractView>.Success(await BuildContractViewAsync(quote)));
    }

    /// <summary>Công nợ hợp đồng: giá trị / đã thu / còn phải thu / quá hạn theo đợt.</summary>
    [HttpGet("receivables")]
    [RequireModulePermission("PosContracts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Receivables(
        [FromQuery] string? search,
        [FromQuery] string? filter)
    {
        var storeId = RequiredStoreId;
        var stagesQ = dbContext.Set<PosQuotePaymentStage>().Where(s => s.StoreId == storeId && s.Deleted == null);
        var payQ = dbContext.Set<PosQuotePayment>().Where(p => p.StoreId == storeId && p.Deleted == null);
        var q = ApplyOwnScope(dbContext.PosQuotes.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.Status != PosQuoteStatus.Cancelled && x.Status != PosQuoteStatus.Rejected
                && (x.CommercialStage >= PosQuoteCommercialStage.Contracted
                    || stagesQ.Any(s => s.QuoteId == x.Id)
                    || payQ.Any(p => p.QuoteId == x.Id))));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            q = q.Where(x =>
                VnSearch.Fold(x.QuoteNo).Contains(s) ||
                (x.ContractNo != null && VnSearch.Fold(x.ContractNo).Contains(s)) ||
                (x.CustomerName != null && VnSearch.Fold(x.CustomerName).Contains(s)) ||
                (x.CustomerPhone != null && x.CustomerPhone.Contains(s)));
        }
        var quotes = await q.OrderByDescending(x => x.ContractSignedAt ?? x.CreatedAt).Take(500).ToListAsync();
        var ids = quotes.Select(x => x.Id).ToList();
        var stages = await stagesQ.AsNoTracking().Where(s => ids.Contains(s.QuoteId)).ToListAsync();
        var paid = await payQ.AsNoTracking().Where(p => ids.Contains(p.QuoteId))
            .GroupBy(p => p.QuoteId)
            .Select(g => new { QuoteId = g.Key, Sum = g.Sum(p => p.Amount) })
            .ToDictionaryAsync(x => x.QuoteId, x => x.Sum);

        var items = quotes.Select(x =>
        {
            var st = stages.Where(s => s.QuoteId == x.Id).OrderBy(s => s.SortOrder).ToList();
            var collected = paid.GetValueOrDefault(x.Id);
            var views = AllocateStages(st, collected, x.Total);
            var next = views.FirstOrDefault(v => v.Remaining > 0);
            return new ContractSummary(
                x.Id, x.QuoteNo, x.ContractNo, x.CommercialStage.ToString(),
                x.CustomerName, x.CustomerPhone,
                x.Total, collected, Math.Max(0, x.Total - collected),
                views.Where(v => v.Status == "overdue").Sum(v => v.Remaining),
                next?.DueDate, next?.Title,
                x.ContractSignedAt, x.ProductionDueAt, x.InstallDueAt, x.HandoverDueAt,
                st.Count);
        }).ToList();

        items = (filter ?? "").Trim().ToLowerInvariant() switch
        {
            "owing" => items.Where(i => i.Remaining > 0).ToList(),
            "overdue" => items.Where(i => i.OverdueAmount > 0).ToList(),
            "paid" => items.Where(i => i.Remaining <= 0).ToList(),
            _ => items,
        };

        return Ok(AppResponse<object>.Success(new
        {
            items,
            totals = new
            {
                count = items.Count,
                contractValue = items.Sum(i => i.Total),
                collected = items.Sum(i => i.Collected),
                remaining = items.Sum(i => i.Remaining),
                overdue = items.Sum(i => i.OverdueAmount),
            },
        }));
    }

    async Task<ContractView> BuildContractViewAsync(PosQuote quote)
    {
        var stages = await dbContext.Set<PosQuotePaymentStage>().AsNoTracking()
            .Where(s => s.QuoteId == quote.Id && s.StoreId == quote.StoreId && s.Deleted == null)
            .OrderBy(s => s.SortOrder)
            .ToListAsync();
        var payments = await dbContext.Set<PosQuotePayment>().AsNoTracking()
            .Where(p => p.QuoteId == quote.Id && p.StoreId == quote.StoreId && p.Deleted == null)
            .OrderByDescending(p => p.PaidAt)
            .ToListAsync();
        var cashIds = payments.Where(p => p.CashTransactionId.HasValue).Select(p => p.CashTransactionId!.Value).ToList();
        var codes = cashIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await dbContext.CashTransactions.AsNoTracking()
                .Where(c => cashIds.Contains(c.Id))
                .ToDictionaryAsync(c => c.Id, c => c.TransactionCode);

        var collected = payments.Sum(p => p.Amount);
        var views = AllocateStages(stages, collected, quote.Total);
        var next = views.FirstOrDefault(v => v.Remaining > 0);
        var titles = stages.ToDictionary(s => s.Id, s => s.Title);
        return new ContractView(
            quote.Id, quote.QuoteNo, quote.Status.ToString(), quote.CommercialStage.ToString(),
            quote.CustomerName, quote.CustomerPhone, quote.CustomerAddress,
            quote.Total, quote.DepositAmount,
            quote.ContractNo, quote.ContractSignedAt, quote.ProductionDueAt,
            quote.InstallDueAt, quote.HandoverDueAt, quote.ContractNote,
            collected, Math.Max(0, quote.Total - collected),
            views.Where(v => v.Status == "overdue").Sum(v => v.Remaining),
            next?.DueDate, next?.Title,
            views,
            payments.Select(p => new ContractPaymentView(
                p.Id, p.StageId,
                p.StageId is Guid sid ? titles.GetValueOrDefault(sid) : null,
                p.Amount, p.PaidAt, p.PaymentMethod, p.Note, p.CollectedBy,
                p.CashTransactionId,
                p.CashTransactionId is Guid cid ? codes.GetValueOrDefault(cid) : null)).ToList());
    }

    /// <summary>Chia số đã thu vào các đợt theo thứ tự (đợt trước đủ rồi mới sang đợt sau).</summary>
    /// Đợt nhập theo % tính lại trên giá trị hợp đồng hiện tại (báo giá sửa sau khi lập đợt).
    static List<ContractStageView> AllocateStages(
        IReadOnlyList<PosQuotePaymentStage> stages, decimal collected, decimal contractTotal)
    {
        var today = DateTime.UtcNow.AddHours(7).Date;
        var left = collected;
        var result = new List<ContractStageView>(stages.Count);
        foreach (var s in stages.OrderBy(s => s.SortOrder))
        {
            var amount = s.Percent is > 0 ? Round0(contractTotal * s.Percent.Value / 100m) : s.Amount;
            var paid = Math.Min(amount, Math.Max(0, left));
            left -= paid;
            var remaining = Math.Max(0, amount - paid);
            // Hạn đợt là ngày (không giờ) theo lịch Việt Nam.
            var status = remaining <= 0 ? "paid"
                : s.DueDate.HasValue && s.DueDate.Value.Date < today ? "overdue"
                : paid > 0 ? "partial"
                : "pending";
            result.Add(new ContractStageView(
                s.Id, s.SortOrder, s.Title, s.Percent, amount, s.DueDate, s.Note,
                paid, remaining, status));
        }
        return result;
    }

    static string? Trim(string? value, int max)
    {
        var v = value?.Trim();
        if (string.IsNullOrEmpty(v)) return null;
        return v.Length > max ? v[..max] : v;
    }

    /// <summary>Hàng gia công tính theo m²: giá mỗi bộ = max(diện tích × đơn giá m², tối thiểu / bộ).</summary>
    internal static class AreaPricing
    {
        public record Result(decimal PricePerM2, decimal? AreaM2, decimal? MinPerSet, decimal SetPrice);

        public static Result? Resolve(QuoteLineInput input)
        {
            if (input.PricePerM2 is not > 0) return null;
            var perM2 = Math.Round(input.PricePerM2.Value, 2);
            decimal? area = input.AreaM2 is > 0 ? input.AreaM2 : null;
            if (area == null && input.Width is > 0 && input.Height is > 0)
                area = input.Width.Value * input.Height.Value / 1_000_000m;
            if (area.HasValue) area = Math.Round(area.Value, 4, MidpointRounding.AwayFromZero);
            var min = input.MinPricePerSet is > 0 ? Math.Round(input.MinPricePerSet.Value, 2) : (decimal?)null;
            var byArea = Round0((area ?? 0) * perM2);
            var setPrice = Math.Max(byArea, min ?? 0);
            return new Result(perM2, area, min, setPrice);
        }
    }
}
