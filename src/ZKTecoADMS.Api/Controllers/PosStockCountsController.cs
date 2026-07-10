using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/stock/counts")]
[Authorize]
public class PosStockCountsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record CreateStockCountDto(string? Name, string? Note, bool SeedAllProducts = false);

    public record UpdateStockCountDto(string? Note);

    public record AddCountLineInput(Guid ProductId, Guid? VariantId);

    public record UpdateCountLineDto(Guid LineId, decimal? CountedQty, bool? IsChecked);

    public record UpdateCountLinesDto(List<UpdateCountLineDto> Lines);

    public record StockCountLineDto(
        Guid Id, Guid ProductId, Guid? VariantId, string ProductCode, string ProductName,
        string? UnitName, decimal SystemQty, decimal? CountedQty, bool IsChecked,
        decimal DiffQty, decimal DiffValue, decimal CostPrice);

    public record StockCountDto(
        Guid Id, string CountNo, string Name, string? Note, string Status,
        DateTime? CompletedAt, DateTime CreatedAt, string? CreatedBy, string? BalancedBy,
        decimal TotalActualQty, decimal TotalActualValue,
        decimal TotalDiffQty, decimal TotalDiffValue,
        decimal QtyIncrease, decimal QtyDecrease,
        List<StockCountLineDto> Lines);

    public record StockCountSummaryDto(
        Guid Id, string CountNo, string Name, string? Note, string Status,
        DateTime? CompletedAt, DateTime CreatedAt, string? CreatedBy, string? BalancedBy,
        int LineCount, int CheckedCount,
        decimal TotalActualQty, decimal TotalActualValue,
        decimal TotalDiffQty, decimal TotalDiffValue,
        decimal QtyIncrease, decimal QtyDecrease);

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> CreateCount([FromBody] CreateStockCountDto dto)
    {
        var storeId = RequiredStoreId;
        var countNo = await NextCountNoAsync(storeId);
        var count = new PosStockCount
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CountNo = countNo,
            Name = string.IsNullOrWhiteSpace(dto.Name) ? countNo : dto.Name.Trim(),
            Note = dto.Note?.Trim(),
            Status = PosStockCountStatus.InProgress,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        var lines = dto.SeedAllProducts
            ? await BuildAllProductLinesAsync(storeId, count.Id)
            : new List<PosStockCountLine>();

        dbContext.PosStockCounts.Add(count);
        if (lines.Count > 0)
            dbContext.PosStockCountLines.AddRange(lines);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, lines)));
    }

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListCounts(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] string? statuses,
        [FromQuery] string? createdBy,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosStockCounts.AsNoTracking()
            .Include(c => c.Lines)
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(c => c.CountNo.ToLower().Contains(s) ||
                                     c.Name.ToLower().Contains(s) ||
                                     (c.Note != null && c.Note.ToLower().Contains(s)));
        }
        if (!string.IsNullOrWhiteSpace(statuses))
        {
            var statusList = statuses.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Enum.TryParse<PosStockCountStatus>(s, true, out var x) ? x : (PosStockCountStatus?)null)
                .Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();
            if (statusList.Count > 0)
                query = query.Where(c => statusList.Contains(c.Status));
        }
        else if (!string.IsNullOrWhiteSpace(status) &&
                 Enum.TryParse<PosStockCountStatus>(status, true, out var st))
            query = query.Where(c => c.Status == st);
        if (!string.IsNullOrWhiteSpace(createdBy))
            query = query.Where(c => c.CreatedBy != null && c.CreatedBy.Contains(createdBy.Trim()));
        if (from.HasValue) query = query.Where(c => c.CreatedAt >= from.Value.Date);
        if (to.HasValue) query = query.Where(c => c.CreatedAt < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var rows = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = rows.Select(MapSummary).ToList();
        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> GetCount(Guid id)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts.AsNoTracking()
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));

        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, count.Lines.ToList())));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> UpdateCount(
        Guid id, [FromBody] UpdateStockCountDto dto)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.InProgress)
            return BadRequest(AppResponse<StockCountDto>.Fail("Chỉ sửa được phiếu tạm"));

        count.Note = dto.Note?.Trim();
        count.UpdatedAt = DateTime.UtcNow;
        count.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, count.Lines.ToList())));
    }

    [HttpPost("{id:guid}/lines/add")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> AddLines(
        Guid id, [FromBody] List<AddCountLineInput> inputs)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.InProgress)
            return BadRequest(AppResponse<StockCountDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));
        if (inputs == null || inputs.Count == 0)
            return BadRequest(AppResponse<StockCountDto>.Fail("Không có dòng hàng"));

        var existingKeys = count.Lines
            .Select(l => $"{l.ProductId}:{l.VariantId}")
            .ToHashSet();
        var added = new List<PosStockCountLine>();

        foreach (var input in inputs)
        {
            var key = $"{input.ProductId}:{input.VariantId}";
            if (existingKeys.Contains(key)) continue;

            var line = await BuildLineAsync(storeId, count.Id, input.ProductId, input.VariantId);
            if (line == null) continue;
            added.Add(line);
            existingKeys.Add(key);
        }

        if (added.Count == 0)
            return BadRequest(AppResponse<StockCountDto>.Fail("Hàng đã có trong phiếu hoặc không hợp lệ"));

        dbContext.PosStockCountLines.AddRange(added);
        await dbContext.SaveChangesAsync();
        await dbContext.Entry(count).Collection(c => c.Lines).LoadAsync();
        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, count.Lines.ToList())));
    }

    [HttpDelete("{id:guid}/lines/{lineId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> RemoveLine(Guid id, Guid lineId)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.InProgress)
            return BadRequest(AppResponse<StockCountDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));

        var line = count.Lines.FirstOrDefault(l => l.Id == lineId);
        if (line == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy dòng hàng"));

        dbContext.PosStockCountLines.Remove(line);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, count.Lines.Where(l => l.Id != lineId).ToList())));
    }

    [HttpPut("{id:guid}/lines")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> UpdateLines(
        Guid id, [FromBody] UpdateCountLinesDto dto)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.InProgress)
            return BadRequest(AppResponse<StockCountDto>.Fail("Phiếu đã hoàn thành hoặc hủy"));

        var lineMap = count.Lines.ToDictionary(l => l.Id);
        foreach (var upd in dto.Lines ?? new List<UpdateCountLineDto>())
        {
            if (!lineMap.TryGetValue(upd.LineId, out var line)) continue;
            if (upd.CountedQty.HasValue) line.CountedQty = upd.CountedQty;
            if (upd.IsChecked.HasValue) line.IsChecked = upd.IsChecked.Value;
            else if (upd.CountedQty.HasValue) line.IsChecked = true;
            line.UpdatedAt = DateTime.UtcNow;
            line.UpdatedBy = CurrentUserEmail;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, count.Lines.ToList())));
    }

    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> CompleteCount(Guid id)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.InProgress)
            return BadRequest(AppResponse<StockCountDto>.Fail("Phiếu không ở trạng thái tạm"));

        var productIds = count.Lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await dbContext.PosProducts
            .AsTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id);

        var variantIds = count.Lines.Where(l => l.VariantId.HasValue)
            .Select(l => l.VariantId!.Value).Distinct().ToList();
        var variants = variantIds.Count == 0
            ? new Dictionary<Guid, PosProductVariant>()
            : await dbContext.PosProductVariants
                .AsTracking()
                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId && v.Deleted == null)
                .ToDictionaryAsync(v => v.Id);

        var touchedProducts = new HashSet<Guid>();
        foreach (var line in count.Lines)
        {
            if (!line.CountedQty.HasValue) continue;
            var diff = line.CountedQty.Value - line.SystemQty;
            if (diff == 0)
            {
                line.IsChecked = true;
                continue;
            }

            if (!products.TryGetValue(line.ProductId, out var p)) continue;
            PosProductVariant? variant = null;
            if (line.VariantId.HasValue)
                variants.TryGetValue(line.VariantId.Value, out variant);

            decimal qtyAfter;
            decimal txChange;
            if (variant != null)
            {
                if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))
                {
                    var baseDiff = PosVariantStockHelper.StockDeltaInBase(variant, Math.Abs(diff));
                    txChange = diff > 0 ? baseDiff : -baseDiff;
                    p.OnHandQty += txChange;
                    qtyAfter = p.OnHandQty;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = CurrentUserEmail;
                }
                else
                {
                    variant.OnHandQty += diff;
                    qtyAfter = variant.OnHandQty;
                    txChange = diff;
                    variant.UpdatedAt = DateTime.UtcNow;
                    variant.UpdatedBy = CurrentUserEmail;
                    touchedProducts.Add(p.Id);
                }
            }
            else
            {
                p.OnHandQty += diff;
                qtyAfter = p.OnHandQty;
                txChange = diff;
                p.UpdatedAt = DateTime.UtcNow;
                p.UpdatedBy = CurrentUserEmail;
            }

            dbContext.PosStockTransactions.Add(new PosStockTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ProductId = p.Id,
                VariantId = variant?.Id,
                TransactionType = PosStockTransactionType.Adjust,
                QtyChange = txChange,
                QtyAfter = qtyAfter,
                ReferenceNo = count.CountNo,
                StockCountId = count.Id,
                Note = $"Kiểm kê: hệ thống {line.SystemQty:N2} → thực tế {line.CountedQty:N2}",
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            line.IsChecked = true;
        }

        foreach (var pid in touchedProducts)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, products[pid]);

        await dbContext.SaveChangesAsync();

        var completedAt = DateTime.UtcNow;
        var (statusOk, statusErr) = await PosDocStatusPersistHelper.SetStockCountStatusAsync(
            dbContext, id, storeId,
            PosStockCountStatus.InProgress, PosStockCountStatus.Completed,
            CurrentUserEmail, completedAt, CurrentUserEmail);
        if (!statusOk)
            return BadRequest(AppResponse<StockCountDto>.Fail(statusErr!));

        dbContext.ChangeTracker.Clear();
        var fresh = await dbContext.PosStockCounts.AsNoTracking()
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (fresh == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));

        return Ok(AppResponse<StockCountDto>.Success(MapCount(fresh, fresh.Lines.ToList())));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> CopyCount(Guid id)
    {
        var storeId = RequiredStoreId;
        var src = await dbContext.PosStockCounts.AsNoTracking()
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (src == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));

        var countNo = await NextCountNoAsync(storeId);
        var count = new PosStockCount
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CountNo = countNo,
            Name = countNo,
            Note = src.Note,
            Status = PosStockCountStatus.InProgress,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        var lines = new List<PosStockCountLine>();
        foreach (var l in src.Lines)
        {
            var built = await BuildLineAsync(storeId, count.Id, l.ProductId, l.VariantId);
            if (built != null) lines.Add(built);
        }

        dbContext.PosStockCounts.Add(count);
        if (lines.Count > 0)
            dbContext.PosStockCountLines.AddRange(lines);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<StockCountDto>.Success(MapCount(count, lines)));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StockCountDto>>> CancelCount(Guid id)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status != PosStockCountStatus.Completed)
            return BadRequest(AppResponse<StockCountDto>.Fail("Chỉ hủy được phiếu đã cân bằng kho — phiếu tạm dùng Xóa"));

        await using var tx = await dbContext.Database.BeginTransactionAsync();
        try
        {
            await PosPurchaseStockHelper.ReverseStockCountAdjustmentsAsync(
                dbContext, storeId, count, CurrentUserEmail);
            await dbContext.SaveChangesAsync();

            var (statusOk, statusErr) = await PosDocStatusPersistHelper.SetStockCountStatusAsync(
                dbContext, id, storeId,
                PosStockCountStatus.Completed, PosStockCountStatus.Cancelled, CurrentUserEmail);
            if (!statusOk)
            {
                await tx.RollbackAsync();
                return BadRequest(AppResponse<StockCountDto>.Fail(statusErr!));
            }

            await tx.CommitAsync();
        }
        catch (InvalidOperationException ex)
        {
            await tx.RollbackAsync();
            return BadRequest(AppResponse<StockCountDto>.Fail(ex.Message));
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }

        dbContext.ChangeTracker.Clear();
        var fresh = await dbContext.PosStockCounts.AsNoTracking()
            .Include(c => c.Lines)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (fresh == null)
            return NotFound(AppResponse<StockCountDto>.Fail("Không tìm thấy phiếu kiểm kê"));

        return Ok(AppResponse<StockCountDto>.Success(MapCount(fresh, fresh.Lines.ToList())));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeleteCount(Guid id)
    {
        var storeId = RequiredStoreId;
        var count = await dbContext.PosStockCounts
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (count == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu kiểm kê"));
        if (count.Status == PosStockCountStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã cân bằng — hãy Hủy trước khi xóa"));

        var (deleteOk, deleteErr) = await PosDocStatusPersistHelper.SoftDeleteStockCountAsync(
            dbContext, id, storeId, CurrentUserEmail);
        if (!deleteOk)
            return BadRequest(AppResponse<object>.Fail(deleteErr!));

        dbContext.ChangeTracker.Clear();
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    private async Task<List<PosStockCountLine>> BuildAllProductLinesAsync(Guid storeId, Guid countId)
    {
        var products = await dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                        p.ProductType != PosProductType.Service &&
                        p.ProductType != PosProductType.Combo)
            .OrderBy(p => p.Name)
            .ToListAsync();

        var productIds = products.Select(p => p.Id).ToList();
        var variants = await dbContext.PosProductVariants.AsNoTracking()
            .Where(v => productIds.Contains(v.ProductId) && v.StoreId == storeId &&
                        v.Deleted == null && v.IsActive)
            .ToListAsync();
        var variantsByProduct = variants.GroupBy(v => v.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var lines = new List<PosStockCountLine>();
        foreach (var p in products)
        {
            var pVariants = variantsByProduct.GetValueOrDefault(p.Id) ?? new List<PosProductVariant>();
            var sharedBase = pVariants.Count == 0 ||
                             pVariants.All(v => PosVariantStockHelper.IsUnitOnlyVariant(v.AttributeJson));

            if (sharedBase)
            {
                var variant = pVariants.Count == 1 ? pVariants[0] : null;
                lines.Add(BuildLineEntity(storeId, countId, p, variant));
            }
            else
            {
                foreach (var v in pVariants)
                    lines.Add(BuildLineEntity(storeId, countId, p, v));
            }
        }
        return lines;
    }

    private async Task<PosStockCountLine?> BuildLineAsync(
        Guid storeId, Guid countId, Guid productId, Guid? variantId)
    {
        var p = await dbContext.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == productId && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return null;

        PosProductVariant? variant = null;
        if (variantId.HasValue)
        {
            variant = await dbContext.PosProductVariants.AsNoTracking()
                .FirstOrDefaultAsync(v => v.Id == variantId && v.ProductId == productId &&
                                          v.StoreId == storeId && v.Deleted == null);
            if (variant == null) return null;
        }

        return BuildLineEntity(storeId, countId, p, variant);
    }

    private PosStockCountLine BuildLineEntity(
        Guid storeId, Guid countId, PosProduct p, PosProductVariant? variant)
    {
        var systemQty = variant?.OnHandQty ?? p.OnHandQty;
        var cost = variant?.CostPrice ?? p.CostPrice;
        var unitName = PosPurchaseStockHelper.ParseUnitName(variant?.AttributeJson) ?? p.BaseUnitName;
        return new PosStockCountLine
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CountId = countId,
            ProductId = p.Id,
            VariantId = variant?.Id,
            ProductName = variant != null && !PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson)
                ? $"{p.Name} — {variant.Name}"
                : p.Name,
            ProductCode = variant?.SkuCode ?? p.ProductCode,
            UnitName = unitName,
            CostPrice = cost,
            SystemQty = systemQty,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
    }

    private static StockCountLineDto MapLine(PosStockCountLine l)
    {
        var diff = l.CountedQty.HasValue ? l.CountedQty.Value - l.SystemQty : 0;
        return new StockCountLineDto(
            l.Id, l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName, l.UnitName,
            l.SystemQty, l.CountedQty, l.IsChecked, diff, diff * l.CostPrice, l.CostPrice);
    }

    private static (decimal totalActualQty, decimal totalActualValue, decimal totalDiffQty,
        decimal totalDiffValue, decimal qtyIncrease, decimal qtyDecrease)
        CalcTotals(IEnumerable<PosStockCountLine> lines)
    {
        decimal totalActualQty = 0, totalActualValue = 0, totalDiffQty = 0, totalDiffValue = 0;
        decimal qtyIncrease = 0, qtyDecrease = 0;
        foreach (var l in lines)
        {
            if (!l.CountedQty.HasValue) continue;
            totalActualQty += l.CountedQty.Value;
            totalActualValue += l.CountedQty.Value * l.CostPrice;
            var diff = l.CountedQty.Value - l.SystemQty;
            totalDiffQty += diff;
            totalDiffValue += diff * l.CostPrice;
            if (diff > 0) qtyIncrease += diff;
            else if (diff < 0) qtyDecrease += Math.Abs(diff);
        }
        return (totalActualQty, totalActualValue, totalDiffQty, totalDiffValue, qtyIncrease, qtyDecrease);
    }

    private static StockCountDto MapCount(PosStockCount count, List<PosStockCountLine> lines)
    {
        var t = CalcTotals(lines);
        return new StockCountDto(
            count.Id, count.CountNo, count.Name, count.Note, count.Status.ToString(),
            count.CompletedAt, count.CreatedAt, count.CreatedBy, count.BalancedBy,
            t.totalActualQty, t.totalActualValue, t.totalDiffQty, t.totalDiffValue,
            t.qtyIncrease, t.qtyDecrease,
            lines.Select(MapLine).ToList());
    }

    private static StockCountSummaryDto MapSummary(PosStockCount count)
    {
        var lines = count.Lines.ToList();
        var t = CalcTotals(lines);
        return new StockCountSummaryDto(
            count.Id, count.CountNo, count.Name, count.Note, count.Status.ToString(),
            count.CompletedAt, count.CreatedAt, count.CreatedBy, count.BalancedBy,
            lines.Count, lines.Count(l => l.IsChecked || l.CountedQty.HasValue),
            t.totalActualQty, t.totalActualValue, t.totalDiffQty, t.totalDiffValue,
            t.qtyIncrease, t.qtyDecrease);
    }

    private async Task<string> NextCountNoAsync(Guid storeId)
    {
        const string prefix = "KK";
        var existing = await dbContext.PosStockCounts.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.CountNo.StartsWith(prefix))
            .Select(c => c.CountNo)
            .ToListAsync();
        var max = 0;
        foreach (var no in existing)
        {
            var numPart = no.Length > 2 ? no[2..] : "";
            if (int.TryParse(numPart, out var n) && n > max) max = n;
        }
        return prefix + (max + 1).ToString("D6");
    }
}
