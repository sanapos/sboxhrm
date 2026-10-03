using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Reports;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Vận hành theo chi nhánh: ngữ cảnh chi nhánh, tồn kho từng chi nhánh, chuyển kho,
/// báo cáo so sánh doanh thu / lợi nhuận giữa các chi nhánh.
/// </summary>
[ApiController]
[Route("api/branch-ops")]
[Authorize]
public class BranchOperationsController(ZKTecoDbContext db, IBranchContext branchCtx) : AuthenticatedControllerBase
{
    // ═══════════════════════ Ngữ cảnh ═══════════════════════

    public record BranchItemDto(Guid Id, string Code, string Name, bool IsHeadquarter, bool IsActive, Guid? ParentBranchId);

    public record BranchContextDto(
        bool UsesBranches, Guid? CurrentBranchId, Guid? HeadquarterBranchId, bool CanSeeAllBranches,
        List<BranchItemDto> Branches);

    /// <summary>Chi nhánh người dùng được thao tác + chi nhánh hiện tại (app hiển thị bộ chuyển chi nhánh).</summary>
    [HttpGet("context")]
    public async Task<ActionResult<AppResponse<BranchContextDto>>> GetContext()
    {
        var storeId = CurrentStoreId;
        if (storeId == null || !branchCtx.StoreUsesBranches)
            return Ok(AppResponse<BranchContextDto>.Success(new BranchContextDto(false, null, null, true, [])));
        var all = await BranchStockService.GetStoreBranchesAsync(db, storeId.Value);
        var visible = all
            .Where(b => branchCtx.AllowedBranchIds == null || branchCtx.AllowedBranchIds.Contains(b.Id))
            .Select(b => new BranchItemDto(b.Id, b.Code, b.Name, b.IsHeadquarter, b.IsActive, b.ParentBranchId))
            .ToList();
        return Ok(AppResponse<BranchContextDto>.Success(new BranchContextDto(
            true, branchCtx.CurrentBranchId, branchCtx.HeadquarterBranchId, branchCtx.AllowedBranchIds == null, visible)));
    }

    // ═══════════════════════ Tồn kho theo chi nhánh ═══════════════════════

    public record BranchStockRowDto(
        Guid ProductId, Guid? VariantId, string ProductCode, string Name, string? VariantName, string Unit,
        decimal Qty, decimal TotalQty, decimal CostPrice, decimal StockValue, decimal MinStockQty, string? ImageUrl);

    /// <summary>Tồn kho của 1 chi nhánh (mặc định chi nhánh đang thao tác).</summary>
    [HttpGet("stock")]
    [MaskCostData("totalValue")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetBranchStock(
        [FromQuery] Guid? branchId, [FromQuery] string? search, [FromQuery] string? filter,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        if (!branchCtx.StoreUsesBranches) return Ok(AppResponse<object>.Fail("Cửa hàng chưa tạo chi nhánh"));
        var bId = branchId ?? branchCtx.CurrentBranchId ?? branchCtx.HeadquarterBranchId;
        if (bId == null || !branchCtx.CanAccess(bId)) return Ok(AppResponse<object>.Fail("Bạn không có quyền xem kho chi nhánh này"));

        var pq = db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.ProductType == PosProductType.Goods);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            pq = pq.Where(p => p.Name.ToLower().Contains(s) || p.ProductCode.ToLower().Contains(s) ||
                               (p.Barcode != null && p.Barcode.Contains(s)));
        }
        var products = await pq
            .Select(p => new { p.Id, p.ProductCode, p.Name, p.BaseUnitName, p.OnHandQty, p.CostPrice, p.MinStockQty, p.ImageUrl })
            .ToListAsync();
        var ids = products.Select(p => p.Id).ToList();
        var qty = await BranchStockService.GetBranchQtyAsync(db, storeId, bId.Value, branchCtx.HeadquarterBranchId, ids);

        var rows = products.Select(p =>
        {
            var q = qty.GetValueOrDefault((p.Id, (Guid?)null));
            return new BranchStockRowDto(p.Id, null, p.ProductCode, p.Name, null, p.BaseUnitName, q, p.OnHandQty,
                p.CostPrice, q * p.CostPrice, p.MinStockQty, p.ImageUrl);
        }).ToList();

        rows = (filter ?? "").ToLowerInvariant() switch
        {
            "instock" => rows.Where(r => r.Qty > 0).ToList(),
            "out" => rows.Where(r => r.Qty <= 0).ToList(),
            "low" => rows.Where(r => r.MinStockQty > 0 && r.Qty < r.MinStockQty).ToList(),
            _ => rows,
        };
        rows = rows.OrderByDescending(r => r.StockValue).ThenBy(r => r.Name).ToList();
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 500);
        return Ok(AppResponse<object>.Success(new
        {
            branchId = bId,
            totalCount = rows.Count,
            totalQty = rows.Sum(r => r.Qty),
            totalValue = rows.Sum(r => r.StockValue),
            outOfStock = rows.Count(r => r.Qty <= 0),
            lowStock = rows.Count(r => r.MinStockQty > 0 && r.Qty < r.MinStockQty && r.Qty > 0),
            items = rows.Skip((page - 1) * pageSize).Take(pageSize).ToList(),
        }));
    }

    /// <summary>Tồn 1 sản phẩm / biến thể ở tất cả chi nhánh được xem.</summary>
    [HttpGet("stock/matrix/{productId:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockMatrix(Guid productId, [FromQuery] Guid? variantId)
    {
        var storeId = RequiredStoreId;
        if (!branchCtx.StoreUsesBranches) return Ok(AppResponse<object>.Success(new { branches = Array.Empty<object>() }));
        var matrix = await BranchStockService.GetProductMatrixAsync(db, storeId, productId, variantId);
        var branches = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        return Ok(AppResponse<object>.Success(new
        {
            branches = branches
                .Where(b => branchCtx.CanAccess(b.Id))
                .Select(b => new { b.Id, b.Code, b.Name, b.IsHeadquarter, qty = matrix.GetValueOrDefault(b.Id) })
                .ToList(),
        }));
    }

    // ═══════════════════════ Chuyển kho ═══════════════════════

    public record TransferLineInput(Guid ProductId, Guid? VariantId, decimal Qty);

    public record CreateTransferRequest(Guid FromBranchId, Guid ToBranchId, string? Note, List<TransferLineInput> Lines, bool SendNow);

    public record ReceiveLineInput(Guid LineId, decimal ReceivedQty);

    public record ReceiveTransferRequest(List<ReceiveLineInput>? Lines);

    [HttpGet("transfers")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetTransfers([FromQuery] int? status, [FromQuery] Guid? branchId)
    {
        var storeId = RequiredStoreId;
        var q = db.PosStockTransfers.AsNoTracking().Include(t => t.Lines).Where(t => t.StoreId == storeId);
        if (status.HasValue) q = q.Where(t => (int)t.Status == status.Value);
        if (branchId.HasValue) q = q.Where(t => t.FromBranchId == branchId || t.ToBranchId == branchId);
        if (branchCtx.AllowedBranchIds is { } allowed)
        {
            var list = allowed.ToList();
            q = q.Where(t => list.Contains(t.FromBranchId) || list.Contains(t.ToBranchId));
        }
        var names = await BranchNamesAsync(storeId);
        var rows = await q.OrderByDescending(t => t.CreatedAt).Take(300).ToListAsync();
        return Ok(AppResponse<object>.Success(rows.Select(t => TransferDto(t, names)).ToList()));
    }

    [HttpGet("transfers/{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetTransfer(Guid id)
    {
        var storeId = RequiredStoreId;
        var t = await db.PosStockTransfers.AsNoTracking().Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (t == null || !(branchCtx.CanAccess(t.FromBranchId) || branchCtx.CanAccess(t.ToBranchId)))
            return Ok(AppResponse<object>.Fail("Không tìm thấy phiếu chuyển kho"));
        return Ok(AppResponse<object>.Success(TransferDto(t, await BranchNamesAsync(storeId))));
    }

    [HttpPost("transfers")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateTransfer([FromBody] CreateTransferRequest req)
    {
        var storeId = RequiredStoreId;
        var branches = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        var ids = branches.Select(b => b.Id).ToHashSet();
        if (!ids.Contains(req.FromBranchId) || !ids.Contains(req.ToBranchId))
            return Ok(AppResponse<object>.Fail("Chi nhánh không hợp lệ"));
        if (req.FromBranchId == req.ToBranchId)
            return Ok(AppResponse<object>.Fail("Kho đi và kho đến phải khác nhau"));
        if (!branchCtx.CanAccess(req.FromBranchId))
            return Ok(AppResponse<object>.Fail("Bạn chỉ được chuyển hàng từ chi nhánh mình quản lý"));
        var lines = (req.Lines ?? []).Where(l => l.Qty > 0).ToList();
        if (lines.Count == 0) return Ok(AppResponse<object>.Fail("Chưa có hàng cần chuyển"));

        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && productIds.Contains(p.Id) && p.Deleted == null)
            .Select(p => new { p.Id, p.Name, p.ProductCode, p.BaseUnitName, p.ProductType })
            .ToDictionaryAsync(p => p.Id);
        var variantIds = lines.Where(l => l.VariantId != null).Select(l => l.VariantId!.Value).ToList();
        var variants = await db.PosProductVariants.AsNoTracking()
            .Where(v => variantIds.Contains(v.Id))
            .Select(v => new { v.Id, v.Name, v.ProductId })
            .ToDictionaryAsync(v => v.Id);

        var transfer = new PosStockTransfer
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            TransferNo = await NextTransferNoAsync(storeId),
            FromBranchId = req.FromBranchId,
            ToBranchId = req.ToBranchId,
            Note = req.Note?.Trim(),
            CreatedByName = CurrentUserEmail,
            CreatedAt = DateTime.UtcNow,
        };
        foreach (var l in lines)
        {
            if (!products.TryGetValue(l.ProductId, out var p))
                return Ok(AppResponse<object>.Fail("Có sản phẩm không tồn tại"));
            if (p.ProductType != PosProductType.Goods)
                return Ok(AppResponse<object>.Fail($"«{p.Name}» không phải hàng hóa có tồn kho"));
            string name = p.Name;
            if (l.VariantId is Guid vid)
            {
                if (!variants.TryGetValue(vid, out var v) || v.ProductId != l.ProductId)
                    return Ok(AppResponse<object>.Fail("Biến thể không hợp lệ"));
                name = $"{p.Name} - {v.Name}";
            }
            transfer.Lines.Add(new PosStockTransferLine
            {
                Id = Guid.NewGuid(),
                TransferId = transfer.Id,
                ProductId = l.ProductId,
                VariantId = l.VariantId,
                ProductName = name,
                Sku = p.ProductCode,
                Unit = p.BaseUnitName,
                Qty = l.Qty,
            });
        }
        db.PosStockTransfers.Add(transfer);

        if (req.SendNow)
        {
            var err = await SendInternalAsync(transfer);
            if (err != null) return Ok(AppResponse<object>.Fail(err));
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(TransferDto(transfer, await BranchNamesAsync(storeId))));
    }

    [HttpPost("transfers/{id:guid}/send")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SendTransfer(Guid id)
    {
        var storeId = RequiredStoreId;
        var t = await db.PosStockTransfers.AsTracking().Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (t == null || !branchCtx.CanAccess(t.FromBranchId)) return Ok(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (t.Status != PosStockTransferStatus.Draft) return Ok(AppResponse<object>.Fail("Phiếu đã được gửi hoặc đã hủy"));
        var err = await SendInternalAsync(t);
        if (err != null) return Ok(AppResponse<object>.Fail(err));
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(TransferDto(t, await BranchNamesAsync(storeId))));
    }

    [HttpPost("transfers/{id:guid}/receive")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ReceiveTransfer(Guid id, [FromBody] ReceiveTransferRequest? req)
    {
        var storeId = RequiredStoreId;
        var t = await db.PosStockTransfers.AsTracking().Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (t == null || !branchCtx.CanAccess(t.ToBranchId)) return Ok(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (t.Status != PosStockTransferStatus.Sent) return Ok(AppResponse<object>.Fail("Phiếu chưa gửi hoặc đã xử lý"));

        var hq = branchCtx.HeadquarterBranchId;
        var inputs = (req?.Lines ?? []).ToDictionary(x => x.LineId, x => x.ReceivedQty);
        foreach (var line in t.Lines)
        {
            var got = inputs.TryGetValue(line.Id, out var r) ? Math.Clamp(r, 0, line.Qty) : line.Qty;
            line.ReceivedQty = got;
            // Kho đến nhận số thực nhận; phần thiếu trả lại kho đi.
            await AdjustAsync(storeId, t.ToBranchId, hq, line.ProductId, line.VariantId, got);
            if (line.Qty - got > 0)
                await AdjustAsync(storeId, t.FromBranchId, hq, line.ProductId, line.VariantId, line.Qty - got);
        }
        t.Status = PosStockTransferStatus.Received;
        t.ReceivedAt = DateTime.UtcNow;
        t.ReceivedByName = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(TransferDto(t, await BranchNamesAsync(storeId))));
    }

    [HttpPost("transfers/{id:guid}/cancel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> CancelTransfer(Guid id)
    {
        var storeId = RequiredStoreId;
        var t = await db.PosStockTransfers.AsTracking().Include(x => x.Lines)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (t == null || !branchCtx.CanAccess(t.FromBranchId)) return Ok(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (t.Status is PosStockTransferStatus.Received or PosStockTransferStatus.Cancelled)
            return Ok(AppResponse<object>.Fail("Phiếu đã nhận hoặc đã hủy"));
        if (t.Status == PosStockTransferStatus.Sent)
        {
            // Đang trên đường → hoàn lại kho đi.
            foreach (var line in t.Lines)
                await AdjustAsync(storeId, t.FromBranchId, branchCtx.HeadquarterBranchId, line.ProductId, line.VariantId, line.Qty);
        }
        t.Status = PosStockTransferStatus.Cancelled;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(true));
    }

    /// <summary>Trừ kho đi (kiểm đủ hàng) → trạng thái Đã gửi (hàng đang trên đường).</summary>
    private async Task<string?> SendInternalAsync(PosStockTransfer t)
    {
        var hq = branchCtx.HeadquarterBranchId;
        var productIds = t.Lines.Select(l => l.ProductId).Distinct().ToList();
        var avail = await BranchStockService.GetBranchQtyAsync(db, t.StoreId, t.FromBranchId, hq, productIds);
        foreach (var g in t.Lines.GroupBy(l => (l.ProductId, l.VariantId)))
        {
            var need = g.Sum(x => x.Qty);
            var have = avail.GetValueOrDefault(g.Key);
            if (need > have)
                return $"«{g.First().ProductName}» chỉ còn {have:0.##} ở kho đi (cần {need:0.##})";
        }
        foreach (var line in t.Lines)
            await AdjustAsync(t.StoreId, t.FromBranchId, hq, line.ProductId, line.VariantId, -line.Qty);
        t.Status = PosStockTransferStatus.Sent;
        t.SentAt = DateTime.UtcNow;
        t.SentByName = CurrentUserEmail;
        return null;
    }

    /// <summary>
    /// Cộng/trừ tồn chi nhánh (trụ sở tính ngầm nên bỏ qua). Dòng biến thể cũng chỉnh dòng cấp sản phẩm
    /// (tồn sản phẩm quản lý biến thể = tổng các biến thể).
    /// </summary>
    private async Task AdjustAsync(Guid storeId, Guid branchId, Guid? hq, Guid productId, Guid? variantId, decimal delta)
    {
        if (branchId == hq || delta == 0) return;
        await BranchStockService.AddAsync(db, storeId, branchId, productId, variantId, delta);
        if (variantId != null)
            await BranchStockService.AddAsync(db, storeId, branchId, productId, null, delta);
    }

    private async Task<string> NextTransferNoAsync(Guid storeId)
    {
        var prefix = $"CK{DateTime.UtcNow.AddHours(7):yyMMdd}";
        var count = await db.PosStockTransfers.CountAsync(t => t.StoreId == storeId && t.TransferNo.StartsWith(prefix));
        return $"{prefix}-{count + 1:000}";
    }

    private async Task<Dictionary<Guid, string>> BranchNamesAsync(Guid storeId)
        => (await BranchStockService.GetStoreBranchesAsync(db, storeId)).ToDictionary(b => b.Id, b => b.Name);

    private static object TransferDto(PosStockTransfer t, Dictionary<Guid, string> names) => new
    {
        t.Id,
        t.TransferNo,
        t.FromBranchId,
        fromBranchName = names.GetValueOrDefault(t.FromBranchId, "—"),
        t.ToBranchId,
        toBranchName = names.GetValueOrDefault(t.ToBranchId, "—"),
        status = (int)t.Status,
        statusLabel = t.Status switch
        {
            PosStockTransferStatus.Draft => "Nháp",
            PosStockTransferStatus.Sent => "Đang chuyển",
            PosStockTransferStatus.Received => "Đã nhận",
            _ => "Đã hủy",
        },
        t.Note,
        t.CreatedByName,
        t.SentByName,
        t.ReceivedByName,
        t.CreatedAt,
        t.SentAt,
        t.ReceivedAt,
        totalQty = t.Lines.Sum(l => l.Qty),
        lines = t.Lines.Select(l => new { l.Id, l.ProductId, l.VariantId, l.ProductName, l.Sku, l.Unit, l.Qty, l.ReceivedQty }).ToList(),
    };

    // ═══════════════════════ Báo cáo chi nhánh ═══════════════════════

    public record BranchKpiDto(
        Guid BranchId, string Code, string Name, bool IsHeadquarter,
        decimal Revenue, int Orders, decimal AvgOrder, decimal Refunds, decimal Cogs, decimal GrossProfit, decimal GrossMarginPct,
        decimal OtherIncome, decimal Expenses, decimal Payroll, decimal NetProfit,
        decimal StockValue, int Employees);

    /// <summary>So sánh các chi nhánh: doanh thu, lợi nhuận gộp, chi phí, lương, lợi nhuận ròng, tồn kho, nhân sự.</summary>
    [HttpGet("reports/compare")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Compare([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        if (!branchCtx.StoreUsesBranches) return Ok(AppResponse<object>.Fail("Cửa hàng chưa tạo chi nhánh"));
        var (fromUtc, toUtc, fromVn, toVn) = Range(from, to);
        var all = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        var branches = all.Where(b => branchCtx.CanAccess(b.Id)).ToList();
        var kpis = await ComputeKpisAsync(storeId, branches, fromUtc, toUtc, fromVn, toVn);

        // Doanh thu theo ngày từng chi nhánh
        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;
        var ids = branches.Select(b => b.Id).ToList();
        var daily = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc &&
                        ids.Contains(o.BranchId ?? hq))
            .Select(o => new { B = o.BranchId ?? hq, At = o.SaleDate ?? o.CreatedAt, Net = o.Total })
            .ToListAsync();
        var days = new List<DateTime>();
        for (var d = fromVn.Date; d <= toVn.Date; d = d.AddDays(1)) days.Add(d);
        var series = branches.Select(b => new
        {
            branchId = b.Id,
            name = b.Name,
            values = days.Select(d => daily.Where(x => x.B == b.Id && x.At.AddHours(7).Date == d).Sum(x => x.Net)).ToList(),
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVn.Date,
            branches = kpis,
            totals = Sum(kpis),
            daily = new { labels = days.Select(d => d.ToString("yyyy-MM-dd")).ToList(), series },
        }));
    }

    /// <summary>Tổng quan 1 chi nhánh: KPI + so kỳ trước + doanh thu / lợi nhuận theo ngày + top hàng, NV + kho.</summary>
    [HttpGet("reports/overview/{branchId:guid}")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Overview(Guid branchId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        if (!branchCtx.StoreUsesBranches || !branchCtx.CanAccess(branchId))
            return Ok(AppResponse<object>.Fail("Bạn không có quyền xem chi nhánh này"));
        var all = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        var b = all.FirstOrDefault(x => x.Id == branchId);
        if (b == null) return Ok(AppResponse<object>.Fail("Không tìm thấy chi nhánh"));

        var (fromUtc, toUtc, fromVn, toVn) = Range(from, to);
        var span = (toVn.Date - fromVn.Date).Days + 1;
        var cur = (await ComputeKpisAsync(storeId, [b], fromUtc, toUtc, fromVn, toVn)).First();
        var prev = (await ComputeKpisAsync(storeId, [b], fromUtc.AddDays(-span), fromUtc, fromVn.AddDays(-span), fromVn.AddDays(-1), includeStock: false)).First();

        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc &&
                        (o.BranchId ?? hq) == branchId)
            .Select(o => new { o.Id, At = o.SaleDate ?? o.CreatedAt, Net = o.Total, o.SoldBy })
            .ToListAsync();
        var orderIds = orders.Select(o => o.Id).ToList();
        var cogsByOrder = await PosReportMoney.CogsByOrderAsync(db, storeId, orderIds);
        var daily = new List<object>();
        for (var d = fromVn.Date; d <= toVn.Date; d = d.AddDays(1))
        {
            var dayOrders = orders.Where(o => o.At.AddHours(7).Date == d).ToList();
            var rev = dayOrders.Sum(o => o.Net);
            var cogs = dayOrders.Sum(o => cogsByOrder.GetValueOrDefault(o.Id));
            daily.Add(new { date = d.ToString("yyyy-MM-dd"), revenue = rev, profit = rev - cogs, orders = dayOrders.Count });
        }
        var topProducts = orderIds.Count == 0
            ? []
            : await db.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && orderIds.Contains(l.SaleOrderId))
                .GroupBy(l => new { l.ProductId, l.ProductName })
                .Select(g => new { g.Key.ProductId, g.Key.ProductName, qty = g.Sum(x => x.Qty), revenue = g.Sum(x => x.LineTotal) })
                .OrderByDescending(x => x.revenue).Take(10)
                .ToListAsync<object>();
        var topSellers = orders
            .GroupBy(o => string.IsNullOrWhiteSpace(o.SoldBy) ? "Không rõ" : o.SoldBy!)
            .Select(g => new { name = g.Key, revenue = g.Sum(x => x.Net), orders = g.Count() })
            .OrderByDescending(x => x.revenue).Take(10).ToList();

        var qty = await BranchStockService.GetBranchQtyAsync(db, storeId, branchId, branchCtx.HeadquarterBranchId);
        var prods = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.ProductType == PosProductType.Goods)
            .Select(p => new { p.Id, p.Name, p.MinStockQty })
            .ToListAsync();
        var lowStock = prods
            .Select(p => new { p.Id, p.Name, p.MinStockQty, qty = qty.GetValueOrDefault((p.Id, (Guid?)null)) })
            .Where(p => p.MinStockQty > 0 && p.qty < p.MinStockQty)
            .OrderBy(p => p.qty).Take(15).ToList();

        var employees = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.BranchId == branchId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new { e.Id, name = (e.LastName + " " + e.FirstName).Trim(), e.Position, e.Department, e.PhotoUrl })
            .OrderBy(e => e.name).ToListAsync();
        var transfers = await db.PosStockTransfers.AsNoTracking().Include(t => t.Lines)
            .Where(t => t.StoreId == storeId && (t.FromBranchId == branchId || t.ToBranchId == branchId))
            .OrderByDescending(t => t.CreatedAt).Take(8).ToListAsync();
        var names = all.ToDictionary(x => x.Id, x => x.Name);

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVn.Date,
            branch = new { b.Id, b.Code, b.Name, b.IsHeadquarter },
            current = cur,
            previous = prev,
            daily,
            topProducts,
            topSellers,
            lowStock,
            outOfStock = prods.Count(p => qty.GetValueOrDefault((p.Id, (Guid?)null)) <= 0),
            employees,
            transfers = transfers.Select(t => TransferDto(t, names)).ToList(),
        }));
    }

    private static (DateTime fromUtc, DateTime toUtc, DateTime fromVn, DateTime toVn) Range(DateTime? from, DateTime? to)
    {
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var fromVn = (from ?? todayVn.AddDays(-29)).Date;
        var toVn = (to ?? todayVn).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        if ((toVn - fromVn).Days > 366) fromVn = toVn.AddDays(-366);
        return (DateTime.SpecifyKind(fromVn.AddHours(-7), DateTimeKind.Utc),
                DateTime.SpecifyKind(toVn.AddDays(1).AddHours(-7), DateTimeKind.Utc), fromVn, toVn);
    }

    private static readonly string[] PosMarkers =
    [
        PosFinanceSyncHelper.SaleMarker, PosFinanceSyncHelper.ReservationDepositMarker,
        PosFinanceSyncHelper.ReservationDepositRefundMarker, PosFinanceSyncHelper.PurchaseReceiptMarker,
        PosFinanceSyncHelper.SupplierPaymentMarker, PosFinanceSyncHelper.CustomerReturnMarker,
        PosFinanceSyncHelper.CustomerPaymentMarker, PosFinanceSyncHelper.PurchaseReturnRefundMarker,
    ];

    /// <summary>
    /// KPI từng chi nhánh trong kỳ.
    ///  Doanh thu = Σ (tổng đơn − VAT) đơn hoàn tất; giá vốn = thẻ kho bán; lãi gộp = doanh thu − trả hàng − giá vốn.
    ///  Thu khác / chi phí = phiếu thu chi hoàn tất KHÔNG do POS tự sinh (bán, nhập, trả…) và không phải phiếu lương.
    ///  Lương = tổng lương gộp các phiếu lương (không hủy) của NV thuộc chi nhánh, tháng nằm trong kỳ.
    ///  Lãi ròng = lãi gộp + thu khác − chi phí − lương.
    /// </summary>
    private async Task<List<BranchKpiDto>> ComputeKpisAsync(
        Guid storeId, List<BranchStockService.BranchInfo> branches,
        DateTime fromUtc, DateTime toUtc, DateTime fromVn, DateTime toVn, bool includeStock = true)
    {
        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;
        var ids = branches.Select(b => b.Id).ToList();

        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc &&
                        ids.Contains(o.BranchId ?? hq))
            .Select(o => new { o.Id, B = o.BranchId ?? hq, Net = o.Total })
            .ToListAsync();
        var orderIds = orders.Select(o => o.Id).ToList();
        var cogs = await PosReportMoney.CogsByOrderAsync(db, storeId, orderIds);
        var orderBranch = orders.ToDictionary(o => o.Id, o => o.B);

        var cash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive && c.Status == CashTransactionStatus.Completed &&
                        c.TransactionDate >= fromUtc && c.TransactionDate < toUtc && ids.Contains(c.BranchId ?? hq))
            .Select(c => new { B = c.BranchId ?? hq, c.Type, c.Amount, Note = c.InternalNote ?? "" })
            .ToListAsync();

        // Lương theo chi nhánh của NV
        var months = new HashSet<(int, int)>();
        for (var d = new DateTime(fromVn.Year, fromVn.Month, 1); d <= toVn; d = d.AddMonths(1)) months.Add((d.Year, d.Month));
        var years = months.Select(m => m.Item1).Distinct().ToList();
        var payslips = await db.Payslips.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.Status != PayslipStatus.Cancelled && years.Contains(p.Year))
            .Select(p => new { p.Year, p.Month, p.GrossSalary, EmpBranch = p.Employee.BranchId })
            .ToListAsync();

        var empCounts = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .GroupBy(e => e.BranchId ?? hq)
            .Select(g => new { B = g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.B, x => x.N);

        // Giá trị tồn: tồn chi nhánh × giá vốn (cấp sản phẩm)
        var stockValue = new Dictionary<Guid, decimal>();
        if (includeStock)
        {
            var costs = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && p.ProductType == PosProductType.Goods)
                .Select(p => new { p.Id, p.CostPrice })
                .ToDictionaryAsync(p => p.Id, p => p.CostPrice);
            foreach (var b in branches)
            {
                var q = await BranchStockService.GetBranchQtyAsync(db, storeId, b.Id, branchCtx.HeadquarterBranchId);
                stockValue[b.Id] = q.Where(kv => kv.Key.Item2 == null && costs.ContainsKey(kv.Key.Item1))
                    .Sum(kv => Math.Max(0, kv.Value) * costs[kv.Key.Item1]);
            }
        }

        var result = new List<BranchKpiDto>();
        foreach (var b in branches)
        {
            var bo = orders.Where(o => o.B == b.Id).ToList();
            var revenue = bo.Sum(o => o.Net);
            var cg = bo.Sum(o => cogs.GetValueOrDefault(o.Id));
            var bc = cash.Where(c => c.B == b.Id).ToList();
            bool IsPos(string note) => PosMarkers.Any(m => note.StartsWith(m, StringComparison.OrdinalIgnoreCase));
            bool IsPayslip(string note) => note.StartsWith("phiếu lương #", StringComparison.OrdinalIgnoreCase);
            var refunds = bc.Where(c => c.Type == CashTransactionType.Expense &&
                                        c.Note.StartsWith(PosFinanceSyncHelper.CustomerReturnMarker, StringComparison.OrdinalIgnoreCase))
                .Sum(c => c.Amount);
            var otherIncome = bc.Where(c => c.Type == CashTransactionType.Income && !IsPos(c.Note) && !IsPayslip(c.Note)).Sum(c => c.Amount);
            var expenses = bc.Where(c => c.Type == CashTransactionType.Expense && !IsPos(c.Note) && !IsPayslip(c.Note)).Sum(c => c.Amount);
            var payroll = payslips.Where(p => (p.EmpBranch ?? hq) == b.Id && months.Contains((p.Year, p.Month))).Sum(p => p.GrossSalary);
            var gross = revenue - refunds - cg;
            result.Add(new BranchKpiDto(
                b.Id, b.Code, b.Name, b.IsHeadquarter,
                revenue, bo.Count, bo.Count == 0 ? 0 : Math.Round(revenue / bo.Count, 0), refunds, cg, gross,
                revenue > 0 ? Math.Round(gross / revenue * 100, 1) : 0,
                otherIncome, expenses, payroll, gross + otherIncome - expenses - payroll,
                stockValue.GetValueOrDefault(b.Id), empCounts.GetValueOrDefault(b.Id)));
        }
        return result;
    }

    private static object Sum(List<BranchKpiDto> k)
    {
        var revenue = k.Sum(x => x.Revenue);
        var orders = k.Sum(x => x.Orders);
        var gross = k.Sum(x => x.GrossProfit);
        return new
        {
            revenue,
            orders,
            avgOrder = orders == 0 ? 0 : Math.Round(revenue / orders, 0),
            refunds = k.Sum(x => x.Refunds),
            cogs = k.Sum(x => x.Cogs),
            grossProfit = gross,
            grossMarginPct = revenue > 0 ? Math.Round(gross / revenue * 100, 1) : 0,
            otherIncome = k.Sum(x => x.OtherIncome),
            expenses = k.Sum(x => x.Expenses),
            payroll = k.Sum(x => x.Payroll),
            netProfit = k.Sum(x => x.NetProfit),
            stockValue = k.Sum(x => x.StockValue),
            employees = k.Sum(x => x.Employees),
        };
    }
}
