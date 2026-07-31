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

[Route("api/pos/stock")]

[Authorize]

public class PosStockController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase

{

    public record StockTransactionDto(

        Guid Id,

        Guid ProductId,

        Guid? VariantId,

        string? VariantName,

        string? UnitName,

        string ProductName,

        string ProductCode,

        string TransactionType,

        decimal QtyChange,

        decimal QtyAfter,

        string? ReferenceNo,

        string? Note,

        Guid? StockReceiptId,

        Guid? SaleOrderId,

        Guid? StockIssueId,

        Guid? StockCountId,

        Guid? PurchaseReturnId,

        decimal? UnitCost,

        decimal? LineAmount,

        string? PartnerName,

        DateTime CreatedAt,

        string? CreatedBy);



    public record StockAdjustDto(

        decimal QtyChange,

        string? Note,

        PosStockTransactionType TransactionType,

        Guid? VariantId);



    [HttpGet]

    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]

    public async Task<ActionResult<AppResponse<object>>> GetTransactions(

        [FromQuery] Guid? productId,

        [FromQuery] Guid? variantId,

        [FromQuery] DateTime? from,

        [FromQuery] DateTime? to,

        [FromQuery] int page = 1,

        [FromQuery] int pageSize = 50)

    {

        var storeId = RequiredStoreId;

        page = Math.Max(page, 1);

        pageSize = Math.Clamp(pageSize, 1, 200);



        var query = dbContext.PosStockTransactions
            .AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive);

        if (productId.HasValue)
            query = query.Where(t => t.ProductId == productId);

        if (variantId.HasValue)
            query = query.Where(t => t.VariantId == variantId);

        if (from.HasValue)
            query = query.Where(t => t.CreatedAt >= from.Value.Date);

        if (to.HasValue)
            query = query.Where(t => t.CreatedAt < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();
        var rows = await query
            .OrderByDescending(t => t.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new
            {
                t.Id,
                t.ProductId,
                t.VariantId,
                VariantName = t.Variant != null ? t.Variant.Name : null,
                VariantAttr = t.Variant != null ? t.Variant.AttributeJson : null,
                ProductName = t.Product != null ? t.Product.Name : "",
                ProductCode = t.Product != null ? t.Product.ProductCode : "",
                TransactionType = t.TransactionType.ToString(),
                t.QtyChange,
                t.QtyAfter,
                t.ReferenceNo,
                t.Note,
                t.StockReceiptId,
                t.SaleOrderId,
                t.StockIssueId,
                t.StockCountId,
                t.PurchaseReturnId,
                t.UnitCost,
                t.LineAmount,
                PartyName = t.StockReceipt != null && t.StockReceipt.Supplier != null
                    ? t.StockReceipt.Supplier.Name
                    : (t.SaleOrder != null ? t.SaleOrder.CustomerName : null),
                t.CreatedAt,
                t.CreatedBy,
            })
            .ToListAsync();
        var items = rows.Select(t => new StockTransactionDto(
            t.Id, t.ProductId, t.VariantId,
            t.VariantName,
            ParseUnitName(t.VariantAttr),
            t.ProductName,
            t.ProductCode,
            t.TransactionType,
            t.QtyChange, t.QtyAfter,
            t.ReferenceNo, t.Note,
            t.StockReceiptId, t.SaleOrderId, t.StockIssueId, t.StockCountId,
            t.PurchaseReturnId, t.UnitCost, t.LineAmount,
            t.PartyName,
            t.CreatedAt, t.CreatedBy)).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));

    }

    [HttpGet("export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportTransactionsExcel(
        [FromQuery] Guid? productId,
        [FromQuery] Guid? variantId,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosStockTransactions.AsNoTracking()
            .Include(t => t.Product)
            .Include(t => t.Variant)
            .Include(t => t.StockReceipt).ThenInclude(r => r!.Supplier)
            .Include(t => t.SaleOrder)
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive);
        if (productId.HasValue) query = query.Where(t => t.ProductId == productId);
        if (variantId.HasValue) query = query.Where(t => t.VariantId == variantId);
        if (from.HasValue) query = query.Where(t => t.CreatedAt >= from.Value.Date);
        if (to.HasValue) query = query.Where(t => t.CreatedAt < to.Value.Date.AddDays(1));
        var rows = await query.OrderByDescending(t => t.CreatedAt).Take(5000).ToListAsync();

        using var workbook = new ClosedXML.Excel.XLWorkbook();
        var ws = workbook.Worksheets.Add("The kho");
        var headers = new[]
        {
            "STT", "Chứng từ", "Thời gian", "Loại GD", "Mã hàng", "Tên hàng",
            "ĐVT", "Số lượng", "Tồn cuối", "Đối tác", "Ghi chú", "Người tạo"
        };
        var meta = ReportExcelMeta.FromUser(
            User, "THẺ KHO POS", null, null,
            new[] { $"Tổng dòng: {rows.Count}" }, rows.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);
        var row = dataStartRow;
        var idx = 1;
        foreach (var t in rows)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = t.ReferenceNo ?? "";
            ws.Cell(row, 3).Value = t.CreatedAt.ToString("dd/MM/yyyy HH:mm");
            ws.Cell(row, 4).Value = TxTypeLabel(t.TransactionType);
            ws.Cell(row, 5).Value = t.Product?.ProductCode ?? "";
            ws.Cell(row, 6).Value = t.Product?.Name ?? "";
            ws.Cell(row, 7).Value = ParseUnitName(t.Variant?.AttributeJson) ?? "";
            ws.Cell(row, 8).Value = t.QtyChange;
            ws.Cell(row, 9).Value = t.QtyAfter;
            ws.Cell(row, 10).Value = t.StockReceipt?.Supplier?.Name ?? t.SaleOrder?.CustomerName ?? "";
            ws.Cell(row, 11).Value = t.Note ?? "";
            ws.Cell(row, 12).Value = t.CreatedBy ?? "";
            row++;
        }
        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"TheKhoPOS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    private static string TxTypeLabel(PosStockTransactionType type) => type switch
    {
        PosStockTransactionType.StockIn => "Nhập kho",
        PosStockTransactionType.StockOut => "Xuất kho",
        PosStockTransactionType.Adjust => "Điều chỉnh tồn",
        PosStockTransactionType.Sale => "Bán hàng",
        PosStockTransactionType.Purchase => "Mua hàng",
        PosStockTransactionType.Return => "Trả hàng",
        _ => type.ToString()
    };



    [HttpPost("products/{productId:guid}/adjust")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockTransactionDto>>> AdjustStock(

        Guid productId, [FromBody] StockAdjustDto dto)

    {

        var storeId = RequiredStoreId;

        if (dto.QtyChange == 0)

            return BadRequest(AppResponse<StockTransactionDto>.Fail("Số lượng biến động phải khác 0"));



        var product = await dbContext.PosProducts

            .AsTracking()

            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);

        if (product == null)

            return NotFound(AppResponse<StockTransactionDto>.Fail("Không tìm thấy hàng hóa"));



        PosProductVariant? variant = null;

        decimal qtyAfter;

        decimal txQtyChange = dto.QtyChange;

        if (dto.VariantId.HasValue)

        {

            variant = await dbContext.PosProductVariants

                .AsTracking()

                .FirstOrDefaultAsync(v => v.Id == dto.VariantId.Value &&

                    v.ProductId == productId && v.StoreId == storeId &&

                    v.Deleted == null && v.IsActive);

            if (variant == null)

                return NotFound(AppResponse<StockTransactionDto>.Fail("Không tìm thấy hàng cùng loại"));



            txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, dto.QtyChange);

            var newBase = product.OnHandQty + txQtyChange;

            if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))

            {

                if (newBase < 0)

                    return BadRequest(AppResponse<StockTransactionDto>.Fail("Tồn kho không đủ"));

                product.OnHandQty = newBase;

                product.UpdatedAt = DateTime.UtcNow;

                product.UpdatedBy = CurrentUserEmail;

                qtyAfter = newBase;

            }

            else

            {

                var newQty = variant.OnHandQty + dto.QtyChange;

                if (newQty < 0)

                    return BadRequest(AppResponse<StockTransactionDto>.Fail("Tồn kho không đủ"));

                variant.OnHandQty = newQty;

                variant.UpdatedAt = DateTime.UtcNow;

                variant.UpdatedBy = CurrentUserEmail;

                qtyAfter = newQty;

                await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, product);

            }

        }

        else

        {

            var newQty = product.OnHandQty + dto.QtyChange;

            if (newQty < 0)

                return BadRequest(AppResponse<StockTransactionDto>.Fail("Tồn kho không đủ"));

            product.OnHandQty = newQty;

            product.UpdatedAt = DateTime.UtcNow;

            product.UpdatedBy = CurrentUserEmail;

            qtyAfter = newQty;

        }



        var tx = new PosStockTransaction

        {

            Id = Guid.NewGuid(),

            StoreId = storeId,

            ProductId = productId,

            VariantId = variant?.Id,

            TransactionType = dto.TransactionType,

            QtyChange = txQtyChange,

            QtyAfter = qtyAfter,

            ReferenceNo = PosStockDocumentNo.NewAdjust(),

            Note = dto.Note?.Trim(),

            IsActive = true,

            CreatedBy = CurrentUserEmail,

        };

        dbContext.PosStockTransactions.Add(tx);

        await dbContext.SaveChangesAsync();



        return Ok(AppResponse<StockTransactionDto>.Success(new StockTransactionDto(

            tx.Id, productId, variant?.Id, variant?.Name,

            ParseUnitName(variant?.AttributeJson),

            product.Name, product.ProductCode,

            tx.TransactionType.ToString(), tx.QtyChange, tx.QtyAfter,

            tx.ReferenceNo, tx.Note,

            tx.StockReceiptId, tx.SaleOrderId, tx.StockIssueId, tx.StockCountId,
            tx.PurchaseReturnId, tx.UnitCost, tx.LineAmount, null,

            tx.CreatedAt, tx.CreatedBy)));

    }



    public record StockReceiptLineInput(

        Guid ProductId,

        Guid? VariantId,

        decimal Qty,

        decimal? CostPrice);



    public record CreateStockReceiptDto(

        Guid? SupplierId,

        string? Note,

        List<StockReceiptLineInput> Lines);



    public record StockReceiptDto(

        Guid Id,

        string ReceiptNo,

        Guid? SupplierId,

        string? SupplierName,

        string? Note,

        decimal TotalQty,

        decimal TotalCost,

        DateTime CreatedAt,

        string? CreatedBy,

        List<StockReceiptLineDto> Lines);



    public record StockReceiptLineDto(

        Guid ProductId,

        Guid? VariantId,

        string ProductCode,

        string ProductName,

        decimal Qty,

        decimal CostPrice,

        decimal LineTotal);



    [HttpPost("receipts")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]

    public async Task<ActionResult<AppResponse<StockReceiptDto>>> CreateStockReceipt(

        [FromBody] CreateStockReceiptDto dto)

    {

        var storeId = RequiredStoreId;

        if (dto.Lines == null || dto.Lines.Count == 0)

            return BadRequest(AppResponse<StockReceiptDto>.Fail("Phiếu nhập trống"));



        var productIds = dto.Lines.Select(l => l.ProductId).Distinct().ToList();

        var products = await dbContext.PosProducts

            .AsTracking()

            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)

            .ToDictionaryAsync(p => p.Id);



        var variantIds = dto.Lines

            .Where(l => l.VariantId.HasValue)

            .Select(l => l.VariantId!.Value)

            .Distinct()

            .ToList();

        var variants = variantIds.Count == 0

            ? new Dictionary<Guid, PosProductVariant>()

            : await dbContext.PosProductVariants

                .AsTracking()

                .Where(v => variantIds.Contains(v.Id) && v.StoreId == storeId &&

                            v.Deleted == null && v.IsActive)

                .ToDictionaryAsync(v => v.Id);



        foreach (var line in dto.Lines)

        {

            if (!products.ContainsKey(line.ProductId))

                return BadRequest(AppResponse<StockReceiptDto>.Fail("Hàng hóa không hợp lệ"));

            if (line.Qty <= 0)

                return BadRequest(AppResponse<StockReceiptDto>.Fail("Số lượng nhập phải > 0"));

            if (line.VariantId.HasValue)

            {

                if (!variants.TryGetValue(line.VariantId.Value, out var v) ||

                    v.ProductId != line.ProductId)

                    return BadRequest(AppResponse<StockReceiptDto>.Fail("Hàng cùng loại không hợp lệ"));

            }

        }



        if (dto.SupplierId.HasValue && !await dbContext.PosSuppliers.AnyAsync(s =>

                s.Id == dto.SupplierId && s.StoreId == storeId && s.Deleted == null))

            return BadRequest(AppResponse<StockReceiptDto>.Fail("Nhà cung cấp không hợp lệ"));



        var receiptNo = await GenerateReceiptNoAsync(storeId);

        var receipt = new PosStockReceipt

        {

            Id = Guid.NewGuid(),

            StoreId = storeId,

            ReceiptNo = receiptNo,

            SupplierId = dto.SupplierId,

            Note = dto.Note?.Trim(),

            IsActive = true,

            CreatedBy = CurrentUserEmail,

        };



        var receiptLines = new List<PosStockReceiptLine>();

        decimal totalQty = 0, totalCost = 0;

        var touchedProducts = new HashSet<Guid>();



        foreach (var line in dto.Lines)

        {

            var p = products[line.ProductId];

            PosProductVariant? variant = null;

            if (line.VariantId.HasValue)

                variants.TryGetValue(line.VariantId.Value, out variant);



            var cost = line.CostPrice ?? variant?.CostPrice ?? p.CostPrice;

            var lineTotal = cost * line.Qty;

            totalQty += line.Qty;

            totalCost += lineTotal;



            var displayCode = variant?.SkuCode ?? p.ProductCode;

            var displayName = variant?.Name ?? p.Name;



            receiptLines.Add(new PosStockReceiptLine

            {

                Id = Guid.NewGuid(),

                StoreId = storeId,

                ReceiptId = receipt.Id,

                ProductId = p.Id,

                VariantId = variant?.Id,

                ProductName = displayName,

                ProductCode = displayCode,

                Qty = line.Qty,

                CostPrice = cost,

                LineTotal = lineTotal,

                IsActive = true,

                CreatedBy = CurrentUserEmail,

            });



            decimal qtyAfter;

            decimal txQtyChange;

            if (variant != null)

            {

                txQtyChange = PosVariantStockHelper.StockDeltaInBase(variant, line.Qty);

                qtyAfter = PosVariantStockHelper.ApplyStockDelta(p, variant, line.Qty, add: true);

                if (line.CostPrice.HasValue)

                {

                    if (PosVariantStockHelper.IsUnitOnlyVariant(variant.AttributeJson))

                        p.CostPrice = line.CostPrice.Value;

                    else

                        variant.CostPrice = line.CostPrice.Value;

                }

                variant.UpdatedAt = DateTime.UtcNow;

                variant.UpdatedBy = CurrentUserEmail;

                p.UpdatedAt = DateTime.UtcNow;

                p.UpdatedBy = CurrentUserEmail;

                touchedProducts.Add(p.Id);

            }

            else

            {

                p.OnHandQty += line.Qty;

                if (line.CostPrice.HasValue)

                    p.CostPrice = line.CostPrice.Value;

                p.UpdatedAt = DateTime.UtcNow;

                p.UpdatedBy = CurrentUserEmail;

                qtyAfter = p.OnHandQty;

                txQtyChange = line.Qty;

            }



            dbContext.PosStockTransactions.Add(new PosStockTransaction

            {

                Id = Guid.NewGuid(),

                StoreId = storeId,

                ProductId = p.Id,

                VariantId = variant?.Id,

                TransactionType = PosStockTransactionType.StockIn,

                QtyChange = txQtyChange,

                QtyAfter = qtyAfter,

                ReferenceNo = receiptNo,

                StockReceiptId = receipt.Id,

                Note = dto.Note?.Trim() ?? "Nhập kho",

                IsActive = true,

                CreatedBy = CurrentUserEmail,

            });

        }



        foreach (var pid in touchedProducts)

            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, products[pid]);



        receipt.TotalQty = totalQty;

        receipt.TotalCost = totalCost;

        dbContext.PosStockReceipts.Add(receipt);

        dbContext.PosStockReceiptLines.AddRange(receiptLines);

        await dbContext.SaveChangesAsync();



        string? supplierName = null;

        if (receipt.SupplierId.HasValue)

        {

            supplierName = await dbContext.PosSuppliers.AsNoTracking()

                .Where(s => s.Id == receipt.SupplierId)

                .Select(s => s.Name)

                .FirstOrDefaultAsync();

        }



        return Ok(AppResponse<StockReceiptDto>.Success(new StockReceiptDto(

            receipt.Id, receipt.ReceiptNo, receipt.SupplierId, supplierName,

            receipt.Note, receipt.TotalQty, receipt.TotalCost,

            receipt.CreatedAt, receipt.CreatedBy,

            receiptLines.Select(l => new StockReceiptLineDto(

                l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName,

                l.Qty, l.CostPrice, l.LineTotal)).ToList())));

    }



    public record StockReceiptSummaryDto(

        Guid Id,

        string ReceiptNo,

        Guid? SupplierId,

        string? SupplierName,

        string? Note,

        decimal TotalQty,

        decimal TotalCost,

        DateTime CreatedAt,

        string? CreatedBy);



    [HttpGet("receipts")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]

    public async Task<ActionResult<AppResponse<object>>> ListStockReceipts(

        [FromQuery] string? search,

        [FromQuery] DateTime? from,

        [FromQuery] DateTime? to,

        [FromQuery] int page = 1,

        [FromQuery] int pageSize = 50)

    {

        var storeId = RequiredStoreId;

        page = Math.Max(page, 1);

        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosStockReceipts.AsNoTracking()

            .Include(r => r.Supplier)

            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive);

        if (!string.IsNullOrWhiteSpace(search))

        {

            var q = search.Trim().ToLower();

            query = query.Where(r => r.ReceiptNo.ToLower().Contains(q) ||

                                     (r.Note != null && r.Note.ToLower().Contains(q)));

        }

        if (from.HasValue)

            query = query.Where(r => r.CreatedAt >= from.Value.Date);

        if (to.HasValue)

            query = query.Where(r => r.CreatedAt < to.Value.Date.AddDays(1));

        var total = await query.CountAsync();

        var items = await query

            .OrderByDescending(r => r.CreatedAt)

            .Skip((page - 1) * pageSize)

            .Take(pageSize)

            .Select(r => new StockReceiptSummaryDto(

                r.Id, r.ReceiptNo, r.SupplierId, r.Supplier != null ? r.Supplier.Name : null,

                r.Note, r.TotalQty, r.TotalCost, r.CreatedAt, r.CreatedBy))

            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));

    }



    [HttpGet("receipts/{id:guid}")]

    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]

    public async Task<ActionResult<AppResponse<StockReceiptDto>>> GetStockReceipt(Guid id)

    {

        var storeId = RequiredStoreId;

        var receipt = await dbContext.PosStockReceipts.AsNoTracking()

            .Include(r => r.Lines)

            .Include(r => r.Supplier)

            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);

        if (receipt == null)

            return NotFound(AppResponse<StockReceiptDto>.Fail("Không tìm thấy phiếu nhập"));



        return Ok(AppResponse<StockReceiptDto>.Success(new StockReceiptDto(

            receipt.Id, receipt.ReceiptNo, receipt.SupplierId, receipt.Supplier?.Name,

            receipt.Note, receipt.TotalQty, receipt.TotalCost,

            receipt.CreatedAt, receipt.CreatedBy,

            receipt.Lines.Select(l => new StockReceiptLineDto(

                l.ProductId, l.VariantId, l.ProductCode ?? "", l.ProductName,

                l.Qty, l.CostPrice, l.LineTotal)).ToList())));

    }



    private static string? ParseUnitName(string? attributeJson)

    {

        if (string.IsNullOrWhiteSpace(attributeJson)) return null;

        try

        {

            using var doc = System.Text.Json.JsonDocument.Parse(attributeJson);

            if (doc.RootElement.TryGetProperty("_unit", out var unit))

                return unit.GetString();

        }

        catch { /* ignore */ }

        return null;

    }



    private async Task<string> GenerateReceiptNoAsync(Guid storeId)

    {

        var prefix = "NK" + DateTime.UtcNow.ToString("yyMMdd");

        for (var i = 0; i < 10; i++)

        {

            var no = prefix + Random.Shared.Next(1000, 9999);

            if (!await dbContext.PosStockReceipts.AnyAsync(r => r.StoreId == storeId && r.ReceiptNo == no))

                return no;

        }

        return prefix + Guid.NewGuid().ToString("N")[..4].ToUpperInvariant();

    }

}


