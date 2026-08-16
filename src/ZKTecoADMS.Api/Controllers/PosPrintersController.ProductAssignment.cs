using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Gán máy in theo sản phẩm / nhóm — tách lane phiếu bếp vs tem.</summary>
public partial class PosPrintersController
{
    public record ProductPrinterMapItem(
        Guid ProductId,
        Guid? ProductPrinterId,
        Guid? CategoryId,
        Guid? CategoryPrinterId,
        Guid? ProductLabelPrinterId = null,
        Guid? CategoryLabelPrinterId = null);

    public record ProductPrinterCategoryDto(
        Guid Id,
        string Name,
        Guid? ParentId,
        Guid? PrinterId,
        string? PrinterName,
        int ProductCount,
        Guid? LabelPrinterId = null,
        string? LabelPrinterName = null);

    public record ProductPrinterProductDto(
        Guid Id,
        string ProductCode,
        string Name,
        Guid? CategoryId,
        string? CategoryName,
        Guid? PrinterId,
        string? PrinterName,
        Guid? CategoryPrinterId,
        string? CategoryPrinterName,
        Guid? LabelPrinterId = null,
        string? LabelPrinterName = null,
        Guid? CategoryLabelPrinterId = null,
        string? CategoryLabelPrinterName = null);

    public record ProductPrinterSetDto
    {
        public Guid? PrinterId { get; set; }
        /// <summary>Khi bỏ gán (PrinterId null): true = bỏ gán tem, false = bỏ gán phiếu bếp.</summary>
        public bool? ForLabel { get; set; }
    }

    public record ProductPrinterApplyDto(bool IncludeChildCategories = true, bool OverwriteExisting = false);

    public record PrinterProductSummaryDto(
        Guid PrinterId,
        string PrinterName,
        int ProductCount,
        bool IsDeviceLocal = false,
        string? OwnerDeviceId = null,
        bool IsLabel = false,
        List<string>? DocumentTypes = null,
        /// <summary>Có Agent online nhận lệnh cho máy này — gán món vào máy
        /// không ai phục vụ thì phiếu chỉ nằm hàng đợi rồi hết hạn.</summary>
        bool HasOnlineAgent = false);

    public record PrinterAssignedProductDto(
        Guid Id,
        string ProductCode,
        string Name,
        Guid? CategoryId,
        string? CategoryName,
        Guid? DefaultPrinterId = null,
        string? DefaultPrinterName = null);

    public class PrinterAssignProductsDto
    {
        public List<Guid>? ProductIds { get; set; }
        public List<Guid>? CategoryIds { get; set; }
        public bool AllProducts { get; set; }
        public bool IncludeChildCategories { get; set; } = true;
        public bool ForceReassign { get; set; }
        /// <summary>
        /// true = gán lane tem (DefaultLabelPrinterId). false = lane phiếu bếp.
        /// null = suy ra từ PrinterBrand / khổ tem / document types.
        /// </summary>
        public bool? ForLabel { get; set; }
    }

    public record ProductPrinterConflictDto(
        Guid ProductId,
        string ProductName,
        string ProductCode,
        Guid CurrentPrinterId,
        string CurrentPrinterName);

    static bool IsLabelBrand(string? brand) =>
        string.Equals(brand, "label", StringComparison.OrdinalIgnoreCase);

    static bool LooksLikeLabelPaper(string? paperSize) =>
        !string.IsNullOrWhiteSpace(paperSize) &&
        (paperSize.StartsWith("roll_", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("50x30", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("40x30", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("x30", StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Loại chứng từ đã cấu hình là nguồn tin cậy nhất — hãng/khổ giấy chỉ là suy đoán.
    /// Trước đây brand="label" thắng trước, nên máy khổ tem cấu hình in Báo kho vẫn bị
    /// xếp lane tem: màn gán hiện "Báo kho / xuất kho" nhưng server đọc/ghi lane tem →
    /// gán xong không thấy SP trong danh sách, gán lại thì báo trùng máy khác.
    /// </summary>
    bool IsLabelPrinterEntity(PosStorePrinter p)
    {
        var routes = p.DocumentRoutes?
            .Where(r => r.Deleted == null)
            .Select(r => r.DocumentType.ToString())
            .ToHashSet(StringComparer.OrdinalIgnoreCase) ?? [];
        var labelish = routes.Any(t =>
            t.Equals("KitchenLabel", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("BarcodeLabel", StringComparison.OrdinalIgnoreCase));
        var kitchenish = routes.Any(t =>
            t.Equals("KitchenSlip", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("KitchenVoid", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("SaleInvoice", StringComparison.OrdinalIgnoreCase) ||
            t.Equals("StockIssue", StringComparison.OrdinalIgnoreCase));
        if (labelish || kitchenish) return labelish && !kitchenish;

        if (IsLabelBrand(p.PrinterBrand)) return true;
        if (LooksLikeLabelPaper(p.PaperSize)) return true;
        return false;
    }

    async Task<bool> ResolveAssignForLabelAsync(
        Guid printerId, Guid storeId, bool? dtoForLabel)
    {
        if (dtoForLabel.HasValue) return dtoForLabel.Value;
        var printer = await db.PosStorePrinters.AsNoTracking()
            .Include(p => p.DocumentRoutes)
            .FirstOrDefaultAsync(p =>
                p.Id == printerId && p.StoreId == storeId && p.Deleted == null);
        return printer != null && IsLabelPrinterEntity(printer);
    }

    async Task<bool> IsLabelPrinterAsync(Guid printerId, Guid storeId) =>
        await ResolveAssignForLabelAsync(printerId, storeId, null);

    [HttpGet("product-assignment/printers/summary")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PrinterProductSummaryDto>>>> GetPrinterProductSummary()
    {
        var storeId = RequiredStoreId;
        var printers = await db.PosStorePrinters.AsNoTracking()
            .Include(p => p.DocumentRoutes)
            .Where(p => p.StoreId == storeId && p.Deleted == null && !p.IsDeviceLocal)
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync();

        var kitchenCounts = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.DefaultPrinterId != null)
            .GroupBy(p => p.DefaultPrinterId!.Value)
            .Select(g => new { PrinterId = g.Key, Count = g.Count() })
            .ToListAsync();
        var labelCounts = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.DefaultLabelPrinterId != null)
            .GroupBy(p => p.DefaultLabelPrinterId!.Value)
            .Select(g => new { PrinterId = g.Key, Count = g.Count() })
            .ToListAsync();
        var kitchenMap = kitchenCounts.ToDictionary(x => x.PrinterId, x => x.Count);
        var labelMap = labelCounts.ToDictionary(x => x.PrinterId, x => x.Count);
        var servedByAgent = await OnlineAgentPrinterIdsAsync(storeId);

        var items = printers.Select(p =>
        {
            var isLabel = IsLabelPrinterEntity(p);
            var docTypes = p.DocumentRoutes?
                .Where(r => r.Deleted == null)
                .Select(r => r.DocumentType.ToString())
                .Distinct()
                .OrderBy(x => x)
                .ToList() ?? [];
            var count = isLabel
                ? labelMap.GetValueOrDefault(p.Id)
                : kitchenMap.GetValueOrDefault(p.Id);
            return new PrinterProductSummaryDto(
                p.Id,
                p.IsDeviceLocal ? $"[Nội bộ] {p.Name}" : p.Name,
                count,
                p.IsDeviceLocal,
                p.OwnerDeviceId,
                isLabel,
                docTypes,
                servedByAgent.Contains(p.Id));
        }).ToList();
        return Ok(AppResponse<List<PrinterProductSummaryDto>>.Success(items));
    }

    /// <summary>PrinterId đang được ít nhất một Agent online nhận lệnh.</summary>
    async Task<HashSet<Guid>> OnlineAgentPrinterIdsAsync(Guid storeId)
    {
        var staleBefore = DateTime.UtcNow.AddSeconds(-90);
        var jsons = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.IsOnline
                && a.LastHeartbeatAt != null && a.LastHeartbeatAt >= staleBefore)
            .Select(a => a.AssignedPrinterIdsJson)
            .ToListAsync();

        var ids = new HashSet<Guid>();
        foreach (var json in jsons)
        {
            try
            {
                foreach (var id in System.Text.Json.JsonSerializer
                             .Deserialize<List<Guid>>(json) ?? [])
                {
                    ids.Add(id);
                }
            }
            catch { /* JSON hỏng → coi như agent không phục vụ máy nào */ }
        }
        return ids;
    }

    [HttpGet("product-assignment/printers/{printerId:guid}/products")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPrinterProducts(
        Guid printerId,
        [FromQuery] string? search = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] bool assignedOnly = true,
        [FromQuery] bool? forLabel = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        var printer = await db.PosStorePrinters.AsNoTracking()
            .Include(p => p.DocumentRoutes)
            .FirstOrDefaultAsync(p => p.Id == printerId && p.StoreId == storeId && p.Deleted == null);
        if (printer == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));
        // Client gửi lane nó đang mở — phải đọc đúng lane đã ghi lúc gán,
        // không thì SP vừa gán biến mất khỏi danh sách.
        var lane = forLabel ?? IsLabelPrinterEntity(printer);

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Include(p => p.DefaultPrinter)
            .Include(p => p.DefaultLabelPrinter)
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (assignedOnly)
        {
            query = lane
                ? query.Where(p => p.DefaultLabelPrinterId == printerId)
                : query.Where(p => p.DefaultPrinterId == printerId);
        }
        if (categoryId.HasValue)
            query = query.Where(p => p.CategoryId == categoryId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new PrinterAssignedProductDto(
                p.Id,
                p.ProductCode,
                p.Name,
                p.CategoryId,
                p.Category != null ? p.Category.Name : null,
                lane ? p.DefaultLabelPrinterId : p.DefaultPrinterId,
                lane
                    ? (p.DefaultLabelPrinter != null ? p.DefaultLabelPrinter.Name : null)
                    : (p.DefaultPrinter != null ? p.DefaultPrinter.Name : null)))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items, forLabel = lane }));
    }

    [HttpPost("product-assignment/printers/{printerId:guid}/assign")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> AssignProductsToPrinter(
        Guid printerId, [FromBody] PrinterAssignProductsDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var printer = await db.PosStorePrinters.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == printerId && p.StoreId == storeId && p.Deleted == null);
        if (printer == null) return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));
        if (printer.IsDeviceLocal)
            return BadRequest(AppResponse<object>.Fail(
                "Không gán SP vào máy nội bộ — chọn máy Agent/cloud (cùng tên trên máy nhận lệnh in)"));
        var forLabel = await ResolveAssignForLabelAsync(printerId, storeId, dto.ForLabel);
        var laneName = forLabel ? "tem" : "phiếu bếp";

        var targetIds = await ResolveAssignProductIdsAsync(storeId, dto);
        if (targetIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn sản phẩm"));

        var idList = targetIds.ToList();

        int alreadyAssigned;
        List<ProductPrinterConflictDto> conflicts;
        if (forLabel)
        {
            alreadyAssigned = await db.PosProducts.AsNoTracking()
                .CountAsync(p => p.StoreId == storeId && p.Deleted == null &&
                                 idList.Contains(p.Id) && p.DefaultLabelPrinterId == printerId);
            conflicts = await db.PosProducts.AsNoTracking()
                .Include(p => p.DefaultLabelPrinter)
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            idList.Contains(p.Id) &&
                            p.DefaultLabelPrinterId != null &&
                            p.DefaultLabelPrinterId != printerId)
                .Select(p => new ProductPrinterConflictDto(
                    p.Id,
                    p.Name,
                    p.ProductCode,
                    p.DefaultLabelPrinterId!.Value,
                    p.DefaultLabelPrinter != null ? p.DefaultLabelPrinter.Name : "Máy tem khác"))
                .ToListAsync();
        }
        else
        {
            alreadyAssigned = await db.PosProducts.AsNoTracking()
                .CountAsync(p => p.StoreId == storeId && p.Deleted == null &&
                                 idList.Contains(p.Id) && p.DefaultPrinterId == printerId);
            conflicts = await db.PosProducts.AsNoTracking()
                .Include(p => p.DefaultPrinter)
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            idList.Contains(p.Id) &&
                            p.DefaultPrinterId != null &&
                            p.DefaultPrinterId != printerId)
                .Select(p => new ProductPrinterConflictDto(
                    p.Id,
                    p.Name,
                    p.ProductCode,
                    p.DefaultPrinterId!.Value,
                    p.DefaultPrinter != null ? p.DefaultPrinter.Name : "Máy khác"))
                .ToListAsync();
        }

        if (conflicts.Count > 0 && !dto.ForceReassign)
        {
            var freeCount = idList.Count - alreadyAssigned - conflicts.Count;
            return Ok(AppResponse<object>.Success(new
            {
                needsConfirm = true,
                forLabel,
                updated = 0,
                alreadyAssigned,
                conflictCount = conflicts.Count,
                freeCount = Math.Max(0, freeCount),
                conflicts,
                message =
                    $"{conflicts.Count} sản phẩm đã gán máy {laneName} khác — mỗi món chỉ 1 máy {laneName}. " +
                    "Bỏ chọn món đó, hoặc xác nhận chuyển máy.",
            }));
        }

        int updated;
        if (forLabel)
        {
            updated = await db.PosProducts
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            idList.Contains(p.Id) && p.DefaultLabelPrinterId != printerId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.DefaultLabelPrinterId, printerId)
                    .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                    .SetProperty(p => p.UpdatedBy, CurrentUserEmail));
        }
        else
        {
            updated = await db.PosProducts
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            idList.Contains(p.Id) && p.DefaultPrinterId != printerId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.DefaultPrinterId, printerId)
                    .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                    .SetProperty(p => p.UpdatedBy, CurrentUserEmail));
        }

        if (updated == 0 && alreadyAssigned == 0)
            return BadRequest(AppResponse<object>.Fail("Không tìm thấy sản phẩm hợp lệ"));

        return Ok(AppResponse<object>.Success(new
        {
            needsConfirm = false,
            forLabel,
            updated,
            alreadyAssigned,
            conflictCount = 0,
            total = updated + alreadyAssigned,
            requested = targetIds.Count,
            reassigned = dto.ForceReassign ? updated : 0,
        }));
    }

    [HttpPost("product-assignment/printers/{printerId:guid}/unassign")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UnassignProductsFromPrinter(
        Guid printerId, [FromBody] PrinterAssignProductsDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var forLabel = await IsLabelPrinterAsync(printerId, storeId);
        var targetIds = await ResolveAssignProductIdsAsync(storeId, dto);
        if (targetIds.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn sản phẩm"));

        var idList = targetIds.ToList();
        int updated;
        if (forLabel)
        {
            updated = await db.PosProducts
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            p.DefaultLabelPrinterId == printerId && idList.Contains(p.Id))
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.DefaultLabelPrinterId, (Guid?)null)
                    .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                    .SetProperty(p => p.UpdatedBy, CurrentUserEmail));
        }
        else
        {
            updated = await db.PosProducts
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            p.DefaultPrinterId == printerId && idList.Contains(p.Id))
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.DefaultPrinterId, (Guid?)null)
                    .SetProperty(p => p.UpdatedAt, DateTime.UtcNow)
                    .SetProperty(p => p.UpdatedBy, CurrentUserEmail));
        }

        return Ok(AppResponse<object>.Success(new { updated, forLabel }));
    }

    async Task<HashSet<Guid>> ResolveAssignProductIdsAsync(Guid storeId, PrinterAssignProductsDto dto)
    {
        var ids = new HashSet<Guid>();
        if (dto.ProductIds is { Count: > 0 })
        {
            var validProductIds = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && dto.ProductIds.Contains(p.Id))
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in validProductIds) ids.Add(id);
        }

        if (dto.CategoryIds is { Count: > 0 })
        {
            var categoryIds = new HashSet<Guid>();
            foreach (var cid in dto.CategoryIds)
            {
                categoryIds.Add(cid);
                if (dto.IncludeChildCategories)
                {
                    foreach (var child in await GetProductAssignmentDescendantCategoryIdsAsync(storeId, cid))
                        categoryIds.Add(child);
                }
            }

            var fromCats = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            p.CategoryId != null && categoryIds.Contains(p.CategoryId.Value))
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in fromCats) ids.Add(id);
        }

        if (dto.AllProducts)
        {
            var all = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => p.Id)
                .ToListAsync();
            foreach (var id in all) ids.Add(id);
        }

        return ids;
    }

    [HttpGet("product-assignment/map")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductPrinterMapItem>>>> GetProductAssignmentMap()
    {
        var storeId = RequiredStoreId;
        var items = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new ProductPrinterMapItem(
                p.Id,
                p.DefaultPrinterId,
                p.CategoryId,
                p.Category != null ? p.Category.DefaultPrinterId : null,
                p.DefaultLabelPrinterId,
                p.Category != null ? p.Category.DefaultLabelPrinterId : null))
            .ToListAsync();
        return Ok(AppResponse<List<ProductPrinterMapItem>>.Success(items));
    }

    [HttpGet("product-assignment/categories")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductPrinterCategoryDto>>>> GetProductAssignmentCategories()
    {
        var storeId = RequiredStoreId;
        var items = await db.PosProductCategories.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Name)
            .Select(c => new ProductPrinterCategoryDto(
                c.Id,
                c.Name,
                c.ParentId,
                c.DefaultPrinterId,
                c.DefaultPrinter != null ? c.DefaultPrinter.Name : null,
                c.Products.Count(p => p.Deleted == null),
                c.DefaultLabelPrinterId,
                c.DefaultLabelPrinter != null ? c.DefaultLabelPrinter.Name : null))
            .ToListAsync();
        return Ok(AppResponse<List<ProductPrinterCategoryDto>>.Success(items));
    }

    [HttpGet("product-assignment/products")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetProductAssignmentProducts(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] bool unassignedOnly = false,
        [FromQuery] bool forLabel = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = db.PosProducts.AsNoTracking()
            .Include(p => p.Category!).ThenInclude(c => c!.DefaultPrinter)
            .Include(p => p.Category!).ThenInclude(c => c!.DefaultLabelPrinter)
            .Include(p => p.DefaultPrinter)
            .Include(p => p.DefaultLabelPrinter)
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (categoryId.HasValue)
            query = query.Where(p => p.CategoryId == categoryId);
        if (unassignedOnly)
        {
            query = forLabel
                ? query.Where(p => p.DefaultLabelPrinterId == null &&
                    (p.Category == null || p.Category.DefaultLabelPrinterId == null))
                : query.Where(p => p.DefaultPrinterId == null &&
                    (p.Category == null || p.Category.DefaultPrinterId == null));
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new ProductPrinterProductDto(
                p.Id,
                p.ProductCode,
                p.Name,
                p.CategoryId,
                p.Category != null ? p.Category.Name : null,
                p.DefaultPrinterId,
                p.DefaultPrinter != null ? p.DefaultPrinter.Name : null,
                p.Category != null ? p.Category.DefaultPrinterId : null,
                p.Category != null && p.Category.DefaultPrinter != null
                    ? p.Category.DefaultPrinter.Name
                    : null,
                p.DefaultLabelPrinterId,
                p.DefaultLabelPrinter != null ? p.DefaultLabelPrinter.Name : null,
                p.Category != null ? p.Category.DefaultLabelPrinterId : null,
                p.Category != null && p.Category.DefaultLabelPrinter != null
                    ? p.Category.DefaultLabelPrinter.Name
                    : null))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items, forLabel }));
    }

    [HttpPut("product-assignment/categories/{id:guid}")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetProductAssignmentCategoryPrinter(
        Guid id, [FromBody] ProductPrinterSetDto dto)
    {
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var storeId = RequiredStoreId;
        var cat = await db.PosProductCategories.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (cat == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm hàng"));

        var forLabel = dto.ForLabel == true;
        if (dto.PrinterId.HasValue)
        {
            var brand = await db.PosStorePrinters.AsNoTracking()
                .Where(p => p.Id == dto.PrinterId && p.StoreId == storeId && p.Deleted == null && p.IsActive)
                .Select(p => p.PrinterBrand)
                .FirstOrDefaultAsync();
            if (brand == null && dto.PrinterId.HasValue)
                return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));
            forLabel = IsLabelBrand(brand);
        }

        if (forLabel)
        {
            var previous = cat.DefaultLabelPrinterId;
            cat.DefaultLabelPrinterId = dto.PrinterId;
            cat.UpdatedAt = DateTime.UtcNow;
            cat.UpdatedBy = CurrentUserEmail;
            var applied = await PropagateCategoryPrinterToProductsAsync(
                storeId, id, previous, dto.PrinterId, includeChildCategories: true, forLabel: true);
            await db.SaveChangesAsync();
            return Ok(AppResponse<object>.Success(new
            {
                forLabel = true,
                printerId = cat.DefaultLabelPrinterId,
                appliedProducts = applied,
            }));
        }
        else
        {
            var previousPrinterId = cat.DefaultPrinterId;
            cat.DefaultPrinterId = dto.PrinterId;
            cat.UpdatedAt = DateTime.UtcNow;
            cat.UpdatedBy = CurrentUserEmail;
            var applied = await PropagateCategoryPrinterToProductsAsync(
                storeId, id, previousPrinterId, dto.PrinterId, includeChildCategories: true, forLabel: false);
            await db.SaveChangesAsync();
            return Ok(AppResponse<object>.Success(new
            {
                forLabel = false,
                printerId = cat.DefaultPrinterId,
                appliedProducts = applied,
            }));
        }
    }

    [HttpPost("product-assignment/categories/{id:guid}/apply")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ApplyProductAssignmentCategoryPrinter(
        Guid id, [FromBody] ProductPrinterApplyDto dto)
    {
        var storeId = RequiredStoreId;
        var cat = await db.PosProductCategories.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == storeId && c.Deleted == null);
        if (cat == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhóm hàng"));
        if (!cat.DefaultPrinterId.HasValue && !cat.DefaultLabelPrinterId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Nhóm hàng chưa gán máy in"));

        var appliedKitchen = 0;
        var appliedLabel = 0;
        if (cat.DefaultPrinterId.HasValue)
        {
            appliedKitchen = await PropagateCategoryPrinterToProductsAsync(
                storeId, id, null, cat.DefaultPrinterId,
                includeChildCategories: dto.IncludeChildCategories,
                overwriteExisting: dto.OverwriteExisting,
                forLabel: false);
        }
        if (cat.DefaultLabelPrinterId.HasValue)
        {
            appliedLabel = await PropagateCategoryPrinterToProductsAsync(
                storeId, id, null, cat.DefaultLabelPrinterId,
                includeChildCategories: dto.IncludeChildCategories,
                overwriteExisting: dto.OverwriteExisting,
                forLabel: true);
        }

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            updated = appliedKitchen + appliedLabel,
            kitchen = appliedKitchen,
            label = appliedLabel,
        }));
    }

    [HttpPut("product-assignment/products/{id:guid}")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetProductAssignmentProductPrinter(
        Guid id, [FromBody] ProductPrinterSetDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var product = await db.PosProducts.AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (product == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        var forLabel = dto.ForLabel == true;
        if (dto.PrinterId.HasValue)
        {
            var brand = await db.PosStorePrinters.AsNoTracking()
                .Where(p => p.Id == dto.PrinterId && p.StoreId == storeId && p.Deleted == null && p.IsActive)
                .Select(p => p.PrinterBrand)
                .FirstOrDefaultAsync();
            if (brand == null)
                return BadRequest(AppResponse<object>.Fail("Máy in không hợp lệ"));
            forLabel = IsLabelBrand(brand);
        }

        if (forLabel)
            product.DefaultLabelPrinterId = dto.PrinterId;
        else
            product.DefaultPrinterId = dto.PrinterId;
        product.UpdatedAt = DateTime.UtcNow;
        product.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { forLabel }));
    }

    async Task<int> PropagateCategoryPrinterToProductsAsync(
        Guid storeId,
        Guid categoryId,
        Guid? previousCategoryPrinterId,
        Guid? newCategoryPrinterId,
        bool includeChildCategories = true,
        bool overwriteExisting = false,
        bool forLabel = false)
    {
        var categoryIds = new List<Guid> { categoryId };
        if (includeChildCategories)
            categoryIds.AddRange(await GetProductAssignmentDescendantCategoryIdsAsync(storeId, categoryId));

        var products = await db.PosProducts.AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        p.CategoryId != null && categoryIds.Contains(p.CategoryId.Value))
            .ToListAsync();

        var updated = 0;
        foreach (var p in products)
        {
            if (forLabel)
            {
                if (overwriteExisting)
                {
                    if (p.DefaultLabelPrinterId == newCategoryPrinterId) continue;
                    p.DefaultLabelPrinterId = newCategoryPrinterId;
                }
                else if (p.DefaultLabelPrinterId == null ||
                         (previousCategoryPrinterId.HasValue &&
                          p.DefaultLabelPrinterId == previousCategoryPrinterId))
                {
                    p.DefaultLabelPrinterId = newCategoryPrinterId;
                }
                else continue;
            }
            else
            {
                if (overwriteExisting)
                {
                    if (p.DefaultPrinterId == newCategoryPrinterId) continue;
                    p.DefaultPrinterId = newCategoryPrinterId;
                }
                else if (p.DefaultPrinterId == null ||
                         (previousCategoryPrinterId.HasValue &&
                          p.DefaultPrinterId == previousCategoryPrinterId))
                {
                    p.DefaultPrinterId = newCategoryPrinterId;
                }
                else continue;
            }

            p.UpdatedAt = DateTime.UtcNow;
            p.UpdatedBy = CurrentUserEmail;
            updated++;
        }

        return updated;
    }

    async Task<List<Guid>> GetProductAssignmentDescendantCategoryIdsAsync(Guid storeId, Guid parentId)
    {
        var all = await db.PosProductCategories.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .Select(c => new { c.Id, c.ParentId })
            .ToListAsync();

        var result = new List<Guid>();
        void Walk(Guid pid)
        {
            foreach (var c in all.Where(x => x.ParentId == pid))
            {
                result.Add(c.Id);
                Walk(c.Id);
            }
        }
        Walk(parentId);
        return result;
    }
}
