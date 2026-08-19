using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/products")]
[Authorize]
public partial class PosProductsController(
    ZKTecoDbContext dbContext,
    IFileStorageService fileStorageService,
    IWebHostEnvironment webHostEnvironment,
    ILogger<PosProductsController> logger) : AuthenticatedControllerBase
{
    public record PosProductDto(
        Guid Id,
        string ProductCode,
        string? Barcode,
        string Name,
        Guid? CategoryId,
        string? CategoryName,
        string? CategoryPath,
        Guid? BrandId,
        string? BrandName,
        Guid? StorageLocationId,
        string? StorageLocationName,
        Guid? SupplierId,
        string? SupplierName,
        string ProductType,
        string? Description,
        string? ImageUrl,
        decimal CostPrice,
        decimal BasePrice,
        decimal VatRate,
        bool VatExempt,
        decimal OnHandQty,
        decimal ReservedQty,
        decimal MinStockQty,
        decimal MaxStockQty,
        decimal? Weight,
        string WeightUnit,
        string BaseUnitName,
        bool IsDirectSale,
        bool IsFavorite,
        bool IsActive,
        int VariantCount,
        decimal? AvgDailySales,
        DateTime? EstimatedStockoutDate,
        List<PosProductUnitDto>? Units,
        List<PosProductAttributeDto>? Attributes,
        List<string>? SaleQuickNotes,
        DateTime CreatedAt,
        DateTime? UpdatedAt,
        Guid? DefaultPrinterId = null,
        string? DefaultPrinterName = null,
        int? WarrantyMonths = null,
        bool RequiresSerial = false,
        bool TrackExpiry = false,
        int ExpiryWarningDays = 30,
        string ServiceBillingMode = "Flat",
        int? MinBillMinutes = null,
        int? BillRoundMinutes = null,
        int? GraceMinutes = null,
        int? RoundAfterMinutes = null,
        int? DefaultDurationMinutes = null,
        int SessionPackCount = 0,
        decimal OpeningFee = 0,
        int? OpeningMinutes = null,
        int SessionPackValidDays = 0,
        bool IsTopping = false,
        bool AllowToppings = false,
        bool AutoOpenToppingPopup = true,
        bool AllowDecimalQty = false,
        List<PosProductToppingOptionDto>? ToppingOptions = null,
        List<Guid>? ToppingGroupIds = null,
        List<PosProductToppingGroupDto>? ToppingGroups = null,
        decimal? SellableQty = null,
        List<PosProductComboLineDto>? ComboLines = null,
        List<PosProductComboLineDto>? RecipeLines = null,
        bool ShowComboComponentsOnSell = false);

    public record PosProductComboLineDto(
        Guid Id,
        Guid ComponentProductId,
        string ComponentProductCode,
        string ComponentProductName,
        decimal Qty,
        decimal ComponentOnHandQty,
        decimal ComponentBasePrice,
        string ComponentUnitName);

    public record PosProductToppingGroupDto(
        Guid Id,
        string Name,
        int SortOrder,
        List<PosProductToppingOptionDto> Items);

    public record PosProductToppingOptionDto(
        Guid Id,
        Guid ToppingProductId,
        string ToppingName,
        decimal ExtraPrice,
        int SortOrder);

    public record PosProductToppingInput(
        Guid ToppingProductId,
        decimal? ExtraPrice = null,
        int SortOrder = 0);

    public record PosProductUnitDto(
        Guid Id, string UnitName, decimal ConversionRate,
        decimal BasePrice, bool IsDirectSale, bool IsBaseUnit);

    public record PosProductAttributeDto(Guid AttributeId, string AttributeName, string Value);

    public record PosProductUpsertDto(
        string? ProductCode,
        string? Barcode,
        string Name,
        Guid? CategoryId,
        Guid? BrandId,
        Guid? StorageLocationId,
        Guid? SupplierId,
        PosProductType ProductType,
        string? Description,
        string? ImageBase64,
        string? ImageUrl,
        decimal CostPrice,
        decimal BasePrice,
        decimal VatRate,
        bool VatExempt,
        decimal OnHandQty,
        decimal ReservedQty,
        decimal MinStockQty,
        decimal MaxStockQty,
        decimal? Weight,
        string? WeightUnit,
        string? BaseUnitName,
        bool IsDirectSale,
        bool IsFavorite,
        List<string>? SaleQuickNotes,
        List<PosProductAttributeInput>? Attributes,
        Guid? DefaultPrinterId = null,
        int? WarrantyMonths = null,
        bool RequiresSerial = false,
        bool TrackExpiry = false,
        int ExpiryWarningDays = 30,
        PosServiceBillingMode ServiceBillingMode = PosServiceBillingMode.Flat,
        int? MinBillMinutes = null,
        int? BillRoundMinutes = null,
        int? GraceMinutes = null,
        int? RoundAfterMinutes = null,
        int? DefaultDurationMinutes = null,
        int SessionPackCount = 0,
        decimal OpeningFee = 0,
        int? OpeningMinutes = null,
        int SessionPackValidDays = 0,
        bool IsTopping = false,
        bool AllowToppings = false,
        bool AutoOpenToppingPopup = true,
        bool AllowDecimalQty = false,
        List<PosProductToppingInput>? Toppings = null,
        List<Guid>? ToppingGroupIds = null,
        bool ShowComboComponentsOnSell = false);

    public record PosProductAttributeInput(Guid? AttributeId, string? AttributeName, string Value);

    public record PosProductListSummary(decimal TotalOnHandQty, int TotalCount);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetProducts(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] Guid? brandId,
        [FromQuery] Guid? storageLocationId,
        [FromQuery] Guid? supplierId,
        [FromQuery] PosProductType? productType,
        [FromQuery] bool? isDirectSale,
        [FromQuery] PosStockFilter stockFilter = PosStockFilter.All,
        [FromQuery] PosStockoutFilter stockoutFilter = PosStockoutFilter.All,
        [FromQuery] PosProductSortBy sortBy = PosProductSortBy.CreatedAt,
        [FromQuery] bool sortDesc = true,
        [FromQuery] bool includeInactive = false,
        [FromQuery] bool categoryIncludeChildren = true,
        [FromQuery] DateTime? createdFrom = null,
        [FromQuery] DateTime? createdTo = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosProducts
            .AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (!includeInactive)
            query = query.Where(p => p.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }

        if (categoryId.HasValue)
        {
            if (categoryIncludeChildren)
            {
                var catIds = await GetCategoryDescendantIdsAsync(storeId, categoryId.Value);
                query = query.Where(p => p.CategoryId != null && catIds.Contains(p.CategoryId.Value));
            }
            else
            {
                query = query.Where(p => p.CategoryId == categoryId);
            }
        }
        if (brandId.HasValue)
            query = query.Where(p => p.BrandId == brandId);
        if (storageLocationId.HasValue)
            query = query.Where(p => p.StorageLocationId == storageLocationId);
        if (supplierId.HasValue)
            query = query.Where(p => p.SupplierId == supplierId);
        if (productType.HasValue)
            query = query.Where(p => p.ProductType == productType);
        if (isDirectSale.HasValue)
            query = query.Where(p => p.IsDirectSale == isDirectSale);

        if (createdFrom.HasValue)
            query = query.Where(p => p.CreatedAt >= createdFrom.Value);
        if (createdTo.HasValue)
        {
            var end = createdTo.Value.Date.AddDays(1);
            query = query.Where(p => p.CreatedAt < end);
        }

        query = stockFilter switch
        {
            PosStockFilter.BelowMin => query.Where(p =>
                (p.ProductType == PosProductType.Goods ||
                 p.ProductType == PosProductType.Material ||
                 p.ProductType == PosProductType.Topping) &&
                p.MinStockQty > 0 && p.OnHandQty > 0 && p.OnHandQty <= p.MinStockQty),
            PosStockFilter.OutOfStock => query.Where(p =>
                (p.ProductType == PosProductType.Goods ||
                 p.ProductType == PosProductType.Material ||
                 p.ProductType == PosProductType.Topping) && p.OnHandQty <= 0),
            PosStockFilter.AboveMax => query.Where(p =>
                (p.ProductType == PosProductType.Goods ||
                 p.ProductType == PosProductType.Material ||
                 p.ProductType == PosProductType.Topping) &&
                p.MaxStockQty > 0 && p.OnHandQty > p.MaxStockQty),
            _ => query,
        };

        var total = await query.CountAsync();
        var totalOnHand = total == 0 ? 0m : await query.SumAsync(p => p.OnHandQty);

        IOrderedQueryable<PosProduct> ordered = sortBy switch
        {
            PosProductSortBy.Code => sortDesc
                ? query.OrderByDescending(p => p.ProductCode)
                : query.OrderBy(p => p.ProductCode),
            PosProductSortBy.Price => sortDesc
                ? query.OrderByDescending(p => p.BasePrice)
                : query.OrderBy(p => p.BasePrice),
            PosProductSortBy.Stock => sortDesc
                ? query.OrderByDescending(p => p.OnHandQty)
                : query.OrderBy(p => p.OnHandQty),
            PosProductSortBy.Name => sortDesc
                ? query.OrderByDescending(p => p.Name)
                : query.OrderBy(p => p.Name),
            _ => sortDesc
                ? query.OrderByDescending(p => p.CreatedAt)
                : query.OrderBy(p => p.CreatedAt),
        };

        var rows = await ordered
            .ThenByDescending(p => p.IsFavorite)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Barcode,
                p.Name,
                p.CategoryId,
                CategoryName = p.Category != null ? p.Category.Name : null,
                p.BrandId,
                BrandName = p.Brand != null ? p.Brand.Name : null,
                p.StorageLocationId,
                StorageLocationName = p.StorageLocation != null ? p.StorageLocation.Name : null,
                p.SupplierId,
                SupplierName = p.Supplier != null ? p.Supplier.Name : null,
                p.ProductType,
                p.Description,
                p.ImageUrl,
                p.CostPrice,
                p.BasePrice,
                p.VatRate,
                p.VatExempt,
                p.OnHandQty,
                p.ReservedQty,
                p.MinStockQty,
                p.MaxStockQty,
                p.Weight,
                p.WeightUnit,
                p.BaseUnitName,
                p.IsDirectSale,
                p.IsFavorite,
                p.IsActive,
                p.SaleQuickNotesJson,
                p.IsTopping,
                p.AllowToppings,
                p.AutoOpenToppingPopup,
                p.ShowComboComponentsOnSell,
                p.AllowDecimalQty,
                p.ServiceBillingMode,
                p.MinBillMinutes,
                p.BillRoundMinutes,
                p.GraceMinutes,
                p.RoundAfterMinutes,
                p.DefaultDurationMinutes,
                p.SessionPackCount,
                p.OpeningFee,
                p.OpeningMinutes,
                p.SessionPackValidDays,
                p.CreatedAt,
                p.UpdatedAt,
            })
            .ToListAsync();

        var ids = rows.Select(r => r.Id).ToList();
        var variantCounts = new Dictionary<Guid, int>();
        var metrics = new Dictionary<Guid, (decimal AvgDaily, DateTime? Stockout)>();
        var comboSellable = new Dictionary<Guid, decimal>();
        if (ids.Count > 0)
        {
            variantCounts = await dbContext.PosProductVariants
                .AsNoTracking()
                .Where(v => ids.Contains(v.ProductId) && v.Deleted == null && v.IsActive)
                .GroupBy(v => v.ProductId)
                .Select(g => new { ProductId = g.Key, VariantCount = g.Count() })
                .ToDictionaryAsync(x => x.ProductId, x => x.VariantCount);

            if (stockoutFilter != PosStockoutFilter.All)
                metrics = await GetStockoutMetricsBatchAsync(storeId, ids);

            var comboIds = rows
                .Where(r => r.ProductType == PosProductType.Combo)
                .Select(r => r.Id)
                .ToList();
            comboSellable = await ComputeComboSellableAsync(storeId, comboIds);
        }

        var items = rows.Select(r =>
        {
            metrics.TryGetValue(r.Id, out var m);
            var avg = m.AvgDaily;
            var stockout = ComputeStockoutDate(r.OnHandQty, avg);
            variantCounts.TryGetValue(r.Id, out var variantCount);
            return new PosProductDto(
                r.Id, r.ProductCode, r.Barcode, r.Name,
                r.CategoryId, r.CategoryName, r.CategoryName,
                r.BrandId, r.BrandName,
                r.StorageLocationId, r.StorageLocationName,
                r.SupplierId, r.SupplierName,
                r.ProductType.ToString(), r.Description, r.ImageUrl,
                r.CostPrice, r.BasePrice, r.VatRate, r.VatExempt, r.OnHandQty, r.ReservedQty,
                r.MinStockQty, r.MaxStockQty, r.Weight, r.WeightUnit, r.BaseUnitName,
                r.IsDirectSale, r.IsFavorite, r.IsActive, variantCount,
                avg > 0 ? avg : null, stockout,
                null, null,
                PosSaleQuickNotesHelper.Parse(r.SaleQuickNotesJson),
                r.CreatedAt, r.UpdatedAt,
                ServiceBillingMode: r.ServiceBillingMode.ToString(),
                MinBillMinutes: r.MinBillMinutes,
                BillRoundMinutes: r.BillRoundMinutes,
                GraceMinutes: r.GraceMinutes,
                RoundAfterMinutes: r.RoundAfterMinutes,
                DefaultDurationMinutes: r.DefaultDurationMinutes,
                SessionPackCount: r.SessionPackCount,
                OpeningFee: r.OpeningFee,
                OpeningMinutes: r.OpeningMinutes,
                SessionPackValidDays: r.SessionPackValidDays,
                IsTopping: r.IsTopping,
                AllowToppings: r.AllowToppings,
                AutoOpenToppingPopup: r.AutoOpenToppingPopup,
                AllowDecimalQty: r.AllowDecimalQty,
                SellableQty: r.ProductType == PosProductType.Combo
                    ? comboSellable.GetValueOrDefault(r.Id)
                    : null,
                ShowComboComponentsOnSell: r.ShowComboComponentsOnSell);
        }).ToList();

        if (stockoutFilter != PosStockoutFilter.All)
        {
            var maxDays = stockoutFilter == PosStockoutFilter.Within7Days ? 7 : 30;
            var cutoff = DateTime.UtcNow.AddDays(maxDays);
            items = items.Where(i =>
                i.EstimatedStockoutDate.HasValue && i.EstimatedStockoutDate.Value <= cutoff).ToList();
            total = items.Count;
        }

        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
            summary = new PosProductListSummary(totalOnHand, total),
            items,
        }));
    }

    [HttpGet("by-barcode/{code}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> GetByBarcode(string code)
    {
        var storeId = RequiredStoreId;
        if (string.IsNullOrWhiteSpace(code))
            return BadRequest(AppResponse<PosProductDto>.Fail("Mã vạch không hợp lệ"));

        var trimmed = code.Trim();
        var product = await dbContext.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                (p.Barcode == trimmed || p.ProductCode == trimmed));
        if (product == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng theo mã vạch"));

        var dto = await MapProductAsync(product.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(dto!));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> GetProduct(Guid id)
    {
        var storeId = RequiredStoreId;
        var dto = await MapProductAsync(id, storeId);
        if (dto == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng hóa"));
        return Ok(AppResponse<PosProductDto>.Success(dto));
    }

    /// <summary>Phục vụ ảnh sản phẩm POS (auth + store scope). Không khóa PosProducts —
    /// thu ngân chỉ có PosSell vẫn cần xem ảnh trên màn bán.</summary>
    [HttpGet("{id:guid}/image")]
    [ResponseCache(Duration = 3600)]
    public async Task<IActionResult> GetProductImage(Guid id)
    {
        var storeId = RequiredStoreId;
        var imageUrl = await dbContext.PosProducts
            .AsNoTracking()
            .Where(p => p.Id == id && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.ImageUrl)
            .FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(imageUrl))
            return NotFound();

        var fullPath = ResolveProductImagePath(imageUrl);
        if (fullPath == null)
            return NotFound();

        var ext = Path.GetExtension(fullPath).ToLowerInvariant();
        var contentType = ext switch
        {
            ".jpg" or ".jpeg" or ".jfif" => "image/jpeg",
            ".png" => "image/png",
            ".webp" => "image/webp",
            ".gif" => "image/gif",
            _ => "image/jpeg",
        };
        return PhysicalFile(fullPath, contentType, enableRangeProcessing: true);
    }

    /// <summary>Upload ảnh sản phẩm (multipart) và gắn vào ImageUrl.</summary>
    [HttpPost("{id:guid}/image")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    [RequestSizeLimit(10_000_000)]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<AppResponse<object>>> UploadProductImage(
        Guid id, [FromForm] IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn ảnh"));

        var storeId = RequiredStoreId;
        var exists = await dbContext.PosProducts
            .AsNoTracking()
            .AnyAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (!exists)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));

        var ext = ResolveImageExtension(file);
        if (ext == null)
            return BadRequest(AppResponse<object>.Fail("Chỉ hỗ trợ ảnh JPG, PNG, WEBP, GIF"));

        try
        {
            var folder = await GetStoreFolderAsync("uploads/pos-products");
            await using var raw = file.OpenReadStream();
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                raw,
                string.IsNullOrWhiteSpace(Path.GetExtension(file.FileName))
                    ? $"product{ext}"
                    : file.FileName,
                ImageOptimizeHelper.ProductMaxEdge,
                ImageOptimizeHelper.ProductJpegQuality);
            await using (optimized)
            {
                var path = await fileStorageService.UploadAsync(optimized, uploadName, folder);
                var imagePath = path.TrimStart('/');
                var updatedBy = CurrentUserEmail ?? "API";
                var now = DateTime.UtcNow;

                // ExecuteUpdate tránh lỗi change-tracker không persist ImageUrl.
                var rows = await dbContext.PosProducts
                    .Where(p => p.Id == id && p.StoreId == storeId && p.Deleted == null)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(p => p.ImageUrl, imagePath)
                        .SetProperty(p => p.UpdatedAt, now)
                        .SetProperty(p => p.UpdatedBy, updatedBy));

                if (rows == 0)
                {
                    logger.LogWarning(
                        "POS product image DB update returned 0 rows for {ProductId}", id);
                    return NotFound(AppResponse<object>.Fail("Không cập nhật được ảnh sản phẩm"));
                }

                logger.LogInformation(
                    "POS product image saved (optimized): {ProductId} -> {ImageUrl} ({Bytes} bytes)",
                    id, imagePath, optimized.Length);

                return Ok(AppResponse<object>.Success(new { imageUrl = imagePath }));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to upload POS product image for {ProductId}", id);
            return StatusCode(500, AppResponse<object>.Fail("Không thể lưu ảnh sản phẩm"));
        }
    }

    private static string? ResolveImageExtension(IFormFile file)
    {
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (string.IsNullOrEmpty(ext) && !string.IsNullOrWhiteSpace(file.ContentType))
        {
            ext = file.ContentType.ToLowerInvariant() switch
            {
                "image/jpeg" or "image/jpg" => ".jpg",
                "image/png" => ".png",
                "image/webp" => ".webp",
                "image/gif" => ".gif",
                _ => ""
            };
        }

        return ext switch
        {
            ".jpg" or ".jpeg" or ".jfif" or ".png" or ".webp" or ".gif" => ext,
            _ => null
        };
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> CreateProduct([FromBody] PosProductUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<PosProductDto>.Fail("Tên hàng không được để trống"));

        var validation = await ValidateRefsAsync(storeId, dto);
        if (validation != null) return validation;

        var code = dto.ProductCode?.Trim();
        if (string.IsNullOrEmpty(code))
            code = await GenerateProductCodeAsync(storeId, dto.ProductType);
        // Unique index includes soft-deleted rows — block reuse of deleted codes too.
        else if (await dbContext.PosProducts.IgnoreQueryFilters().AnyAsync(p =>
                     p.StoreId == storeId && p.ProductCode == code))
            return BadRequest(AppResponse<PosProductDto>.Fail("Mã hàng đã tồn tại"));

        var entity = new PosProduct
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductCode = code,
            Barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim(),
            Name = name,
            CategoryId = dto.CategoryId,
            BrandId = dto.BrandId,
            StorageLocationId = dto.StorageLocationId,
            SupplierId = dto.SupplierId,
            ProductType = dto.ProductType,
            Description = dto.Description?.Trim(),
            CostPrice = dto.CostPrice,
            BasePrice = dto.BasePrice,
            VatRate = dto.VatExempt ? 0 : Math.Max(0, dto.VatRate),
            VatExempt = dto.VatExempt,
            OnHandQty = dto.OnHandQty,
            ReservedQty = dto.ReservedQty,
            MinStockQty = dto.MinStockQty,
            MaxStockQty = dto.MaxStockQty,
            Weight = dto.Weight,
            WeightUnit = string.IsNullOrWhiteSpace(dto.WeightUnit) ? "g" : dto.WeightUnit.Trim(),
            BaseUnitName = string.IsNullOrWhiteSpace(dto.BaseUnitName) ? "Cái" : dto.BaseUnitName.Trim(),
            IsDirectSale = dto.IsDirectSale,
            IsFavorite = dto.IsFavorite,
            SortOrder = await NextProductSortOrderAsync(storeId, dto.CategoryId),
            SaleQuickNotesJson = PosSaleQuickNotesHelper.Serialize(dto.SaleQuickNotes),
            DefaultPrinterId = await ResolvePrinterIdAsync(storeId, dto.DefaultPrinterId),
            WarrantyMonths = dto.WarrantyMonths > 0 ? dto.WarrantyMonths : null,
            RequiresSerial = dto.RequiresSerial && !dto.AllowDecimalQty,
            AllowDecimalQty = dto.AllowDecimalQty && !dto.RequiresSerial,
            TrackExpiry = dto.TrackExpiry,
            ExpiryWarningDays = dto.ExpiryWarningDays > 0 ? dto.ExpiryWarningDays : 30,
            ServiceBillingMode = dto.ProductType == PosProductType.Service
                ? dto.ServiceBillingMode
                : PosServiceBillingMode.Flat,
            MinBillMinutes = dto.MinBillMinutes,
            BillRoundMinutes = dto.BillRoundMinutes,
            GraceMinutes = dto.GraceMinutes,
            RoundAfterMinutes = dto.RoundAfterMinutes,
            DefaultDurationMinutes = dto.DefaultDurationMinutes,
            SessionPackCount = Math.Max(0, dto.SessionPackCount),
            OpeningFee = Math.Max(0, dto.OpeningFee),
            OpeningMinutes = dto.OpeningMinutes,
            SessionPackValidDays = Math.Max(0, dto.SessionPackValidDays),
            IsTopping = dto.IsTopping,
            AllowToppings = dto.AllowToppings && !dto.IsTopping,
            AutoOpenToppingPopup = dto.AutoOpenToppingPopup,
            ShowComboComponentsOnSell = dto.ProductType == PosProductType.Combo && dto.ShowComboComponentsOnSell,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        entity.ImageUrl = await ResolveImageUrlAsync(storeId, dto);

        NormalizeByProductType(entity);

        dbContext.PosProducts.Add(entity);
        await dbContext.SaveChangesAsync();

        await EnsureBaseUnitAsync(entity);
        await SyncAttributesAsync(storeId, entity.Id, dto.Attributes);
        await SyncToppingsAsync(storeId, entity.Id, dto.AllowToppings && !dto.IsTopping, dto.Toppings);
        await SyncToppingGroupsAsync(storeId, entity.Id, dto.ToppingGroupIds);
        var result = await MapProductAsync(entity.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(result!));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> UpdateProduct(
        Guid id, [FromBody] PosProductUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProducts
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng hóa"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<PosProductDto>.Fail("Tên hàng không được để trống"));

        var validation = await ValidateRefsAsync(storeId, dto);
        if (validation != null) return validation;

        if (!string.IsNullOrWhiteSpace(dto.ProductCode))
        {
            var code = dto.ProductCode.Trim();
            if (code != entity.ProductCode &&
                await dbContext.PosProducts.IgnoreQueryFilters().AnyAsync(p =>
                    p.StoreId == storeId && p.ProductCode == code && p.Id != id))
                return BadRequest(AppResponse<PosProductDto>.Fail("Mã hàng đã tồn tại"));
            entity.ProductCode = code;
        }

        entity.Barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim();
        entity.Name = name;
        entity.CategoryId = dto.CategoryId;
        entity.BrandId = dto.BrandId;
        entity.StorageLocationId = dto.StorageLocationId;
        entity.SupplierId = dto.SupplierId;
        entity.ProductType = dto.ProductType;
        entity.Description = dto.Description?.Trim();
        var oldCost = entity.CostPrice;
        entity.CostPrice = dto.CostPrice;
        entity.BasePrice = dto.BasePrice;
        entity.VatRate = dto.VatExempt ? 0 : Math.Max(0, dto.VatRate);
        entity.VatExempt = dto.VatExempt;

        var hasVariants = await dbContext.PosProductVariants.AnyAsync(v =>
            v.ProductId == id && v.StoreId == storeId && v.Deleted == null && v.IsActive);
        var usesSharedBase = !hasVariants ||
            await PosVariantStockHelper.UsesSharedBaseStockAsync(dbContext, id);

        var oldOnHand = entity.OnHandQty;
        if (usesSharedBase)
        {
            if (entity.OnHandQty != dto.OnHandQty)
            {
                entity.OnHandQty = dto.OnHandQty;
                PosStockRecording.RecordAdjustIfChanged(
                    dbContext, storeId, entity.Id, null, oldOnHand, dto.OnHandQty, CurrentUserEmail);
            }
        }

        if (oldCost != dto.CostPrice)
        {
            PosStockRecording.RecordCostChangeIfChanged(
                dbContext, storeId, entity.Id, null, entity.OnHandQty,
                oldCost, dto.CostPrice, CurrentUserEmail);
        }

        entity.ReservedQty = dto.ReservedQty;
        entity.MinStockQty = dto.MinStockQty;
        entity.MaxStockQty = dto.MaxStockQty;
        entity.Weight = dto.Weight;
        entity.WeightUnit = string.IsNullOrWhiteSpace(dto.WeightUnit) ? "g" : dto.WeightUnit.Trim();
        // Giữ ĐVT hiện có nếu client không gửi — tránh partial PUT về «Cái».
        if (!string.IsNullOrWhiteSpace(dto.BaseUnitName))
            entity.BaseUnitName = dto.BaseUnitName.Trim();
        entity.IsDirectSale = dto.IsDirectSale;
        entity.IsFavorite = dto.IsFavorite;
        entity.SaleQuickNotesJson = PosSaleQuickNotesHelper.Serialize(dto.SaleQuickNotes);
        entity.DefaultPrinterId = await ResolvePrinterIdAsync(storeId, dto.DefaultPrinterId);
        entity.WarrantyMonths = dto.WarrantyMonths > 0 ? dto.WarrantyMonths : null;
        entity.RequiresSerial = dto.RequiresSerial && !dto.AllowDecimalQty;
        entity.AllowDecimalQty = dto.AllowDecimalQty && !dto.RequiresSerial;
        entity.TrackExpiry = dto.TrackExpiry;
        entity.ExpiryWarningDays = dto.ExpiryWarningDays > 0 ? dto.ExpiryWarningDays : 30;
        entity.ServiceBillingMode = dto.ProductType == PosProductType.Service
            ? dto.ServiceBillingMode
            : PosServiceBillingMode.Flat;
        entity.MinBillMinutes = dto.MinBillMinutes;
        entity.BillRoundMinutes = dto.BillRoundMinutes;
        entity.GraceMinutes = dto.GraceMinutes;
        entity.RoundAfterMinutes = dto.RoundAfterMinutes;
        entity.DefaultDurationMinutes = dto.DefaultDurationMinutes;
        entity.SessionPackCount = Math.Max(0, dto.SessionPackCount);
        entity.OpeningFee = Math.Max(0, dto.OpeningFee);
        entity.OpeningMinutes = dto.OpeningMinutes;
        entity.SessionPackValidDays = Math.Max(0, dto.SessionPackValidDays);
        entity.IsTopping = dto.IsTopping;
        entity.AllowToppings = dto.AllowToppings && !dto.IsTopping;
        entity.AutoOpenToppingPopup = dto.AutoOpenToppingPopup;
        entity.ShowComboComponentsOnSell =
            dto.ProductType == PosProductType.Combo && dto.ShowComboComponentsOnSell;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;

        NormalizeByProductType(entity);

        if (!string.IsNullOrWhiteSpace(dto.ImageUrl))
            entity.ImageUrl = NormalizeStoredImageUrl(dto.ImageUrl);
        else if (!string.IsNullOrWhiteSpace(dto.ImageBase64))
            entity.ImageUrl = await TrySaveImageAsync(storeId, dto.ImageBase64);

        await dbContext.SaveChangesAsync();
        await SyncBaseUnitAsync(entity);
        await SyncAttributesAsync(storeId, entity.Id, dto.Attributes);
        await SyncToppingsAsync(storeId, entity.Id, entity.AllowToppings, dto.Toppings);
        await SyncToppingGroupsAsync(storeId, entity.Id, dto.ToppingGroupIds);

        var result = await MapProductAsync(entity.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(result!));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> DeleteProduct(Guid id)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.UtcNow;
        var affected = await dbContext.PosProducts
            .Where(p => p.Id == id && p.StoreId == storeId && p.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.IsActive, false)
                .SetProperty(p => p.Deleted, now)
                .SetProperty(p => p.DeletedBy, CurrentUserEmail)
                .SetProperty(p => p.UpdatedAt, now));

        if (affected == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa hoặc đã bị xóa"));

        await dbContext.PosProductUnits
            .Where(u => u.ProductId == id && u.StoreId == storeId && u.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.IsActive, false)
                .SetProperty(u => u.Deleted, now)
                .SetProperty(u => u.DeletedBy, CurrentUserEmail)
                .SetProperty(u => u.UpdatedAt, now));

        await dbContext.PosProductVariants
            .Where(v => v.ProductId == id && v.StoreId == storeId && v.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(v => v.IsActive, false)
                .SetProperty(v => v.Deleted, now)
                .SetProperty(v => v.DeletedBy, CurrentUserEmail)
                .SetProperty(v => v.UpdatedAt, now));

        return Ok(AppResponse<object>.Success(new { Id = id }));
    }

    [HttpPost("{id:guid}/copy")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<PosProductDto>>> CopyProduct(Guid id)
    {
        var storeId = RequiredStoreId;
        var source = await dbContext.PosProducts
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (source == null)
            return NotFound(AppResponse<PosProductDto>.Fail("Không tìm thấy hàng hóa"));

        var copy = new PosProduct
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductCode = await GenerateProductCodeAsync(storeId, source.ProductType),
            Barcode = null,
            Name = source.Name + " (bản sao)",
            CategoryId = source.CategoryId,
            BrandId = source.BrandId,
            StorageLocationId = source.StorageLocationId,
            ProductType = source.ProductType,
            Description = source.Description,
            ImageUrl = source.ImageUrl,
            CostPrice = source.CostPrice,
            BasePrice = source.BasePrice,
            VatRate = source.VatRate,
            VatExempt = source.VatExempt,
            OnHandQty = 0,
            ReservedQty = 0,
            MinStockQty = source.MinStockQty,
            MaxStockQty = source.MaxStockQty,
            Weight = source.Weight,
            WeightUnit = source.WeightUnit,
            BaseUnitName = source.BaseUnitName,
            IsDirectSale = source.IsDirectSale,
            IsFavorite = false,
            SortOrder = await NextProductSortOrderAsync(storeId, source.CategoryId),
            SaleQuickNotesJson = source.SaleQuickNotesJson,
            WarrantyMonths = source.WarrantyMonths,
            RequiresSerial = source.RequiresSerial,
            AllowDecimalQty = source.AllowDecimalQty,
            TrackExpiry = source.TrackExpiry,
            ExpiryWarningDays = source.ExpiryWarningDays,
            IsTopping = source.IsTopping,
            AllowToppings = source.AllowToppings,
            AutoOpenToppingPopup = source.AutoOpenToppingPopup,
            ShowComboComponentsOnSell = source.ShowComboComponentsOnSell,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProducts.Add(copy);
        await dbContext.SaveChangesAsync();
        await EnsureBaseUnitAsync(copy);

        if (source.ProductType == Domain.Enums.PosProductType.Combo)
        {
            var sourceLines = await dbContext.PosProductComboLines.AsNoTracking()
                .Where(x => x.ComboProductId == id && x.StoreId == storeId && x.Deleted == null)
                .ToListAsync();
            foreach (var line in sourceLines)
            {
                dbContext.PosProductComboLines.Add(new PosProductComboLine
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ComboProductId = copy.Id,
                    ComponentProductId = line.ComponentProductId,
                    Qty = line.Qty,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                });
            }
            await dbContext.SaveChangesAsync();
        }

        var result = await MapProductAsync(copy.Id, storeId);
        return Ok(AppResponse<PosProductDto>.Success(result!));
    }

    public class ProductSortItemDto
    {
        public Guid Id { get; set; }
        public int SortOrder { get; set; }
    }

    public class ProductSortBatchDto
    {
        public List<ProductSortItemDto> Items { get; set; } = [];
    }

    /// <summary>Sắp xếp thứ tự sản phẩm trên menu bán.</summary>
    [HttpPut("sort")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosProducts", "PosSell")]
    public async Task<ActionResult<AppResponse<object>>> SortProducts([FromBody] ProductSortBatchDto? dto)
    {
        var storeId = RequiredStoreId;
        if (dto?.Items == null || dto.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có thứ tự"));

        var saved = 0;
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        foreach (var item in dto.Items)
        {
            if (item.Id == Guid.Empty) continue;
            saved += await dbContext.PosProducts
                .Where(p => p.Id == item.Id && p.StoreId == storeId && p.Deleted == null)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.SortOrder, item.SortOrder)
                    .SetProperty(p => p.UpdatedAt, now)
                    .SetProperty(p => p.UpdatedBy, by));
        }

        if (saved == 0)
            return BadRequest(AppResponse<object>.Fail("Không khớp sản phẩm nào"));
        return Ok(AppResponse<object>.Success(new { saved }));
    }

    [HttpPost("{id:guid}/favorite")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ToggleFavorite(Guid id, [FromQuery] bool value)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProducts
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy hàng hóa"));
        entity.IsFavorite = value;
        entity.UpdatedAt = DateTime.UtcNow;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { entity.Id, entity.IsFavorite }));
    }

    private async Task<PosProductDto?> MapProductAsync(Guid id, Guid storeId)
    {
        var p = await dbContext.PosProducts
            .AsNoTracking()
            .Include(x => x.Category)
            .Include(x => x.Brand)
            .Include(x => x.StorageLocation)
            .Include(x => x.Supplier)
            .Include(x => x.DefaultPrinter)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return null;

        var units = await dbContext.PosProductUnits
            .AsNoTracking()
            .Where(u => u.ProductId == id && u.Deleted == null)
            .OrderByDescending(u => u.IsBaseUnit)
            .ThenBy(u => u.ConversionRate)
            .Select(u => new PosProductUnitDto(u.Id, u.UnitName, u.ConversionRate, u.BasePrice, u.IsDirectSale, u.IsBaseUnit))
            .ToListAsync();

        var attrs = await dbContext.PosProductAttributeValues
            .AsNoTracking()
            .Include(v => v.Attribute)
            .Where(v => v.ProductId == id && v.Deleted == null)
            .Select(v => new PosProductAttributeDto(v.AttributeId, v.Attribute!.Name, v.Value))
            .ToListAsync();

        var variantCount = await dbContext.PosProductVariants
            .AsNoTracking()
            .CountAsync(v => v.ProductId == id && v.Deleted == null && v.IsActive);

        var metrics = await GetStockoutMetricsBatchAsync(storeId, [id]);
        metrics.TryGetValue(id, out var m);
        var avg = m.AvgDaily;
        var stockout = ComputeStockoutDate(p.OnHandQty, avg);

        string? categoryPath = p.Category?.Name;
        if (p.Category?.ParentId != null)
        {
            var parent = await dbContext.PosProductCategories.AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == p.Category.ParentId);
            if (parent != null)
                categoryPath = $"{parent.Name} → {p.Category.Name}";
        }

        var toppingOpts = await dbContext.PosProductToppingOptions
            .AsNoTracking()
            .Include(t => t.ToppingProduct)
            .Where(t => t.ProductId == id && t.StoreId == storeId && t.Deleted == null && t.IsActive)
            .OrderBy(t => t.SortOrder)
            .Select(t => new PosProductToppingOptionDto(
                t.Id,
                t.ToppingProductId,
                t.ToppingProduct != null ? t.ToppingProduct.Name : "",
                t.ExtraPrice ?? (t.ToppingProduct != null ? t.ToppingProduct.BasePrice : 0),
                t.SortOrder))
            .ToListAsync();

        var (groupIdsMap, groupsMap) = await LoadToppingGroupsForProductsAsync(storeId, [id]);
        groupIdsMap.TryGetValue(id, out var groupIds);
        groupsMap.TryGetValue(id, out var toppingGroups);

        List<PosProductComboLineDto>? comboLines = null;
        List<PosProductComboLineDto>? recipeLines = null;
        decimal? sellableQty = null;
        if (p.ProductType == PosProductType.Combo)
        {
            comboLines = await dbContext.PosProductComboLines.AsNoTracking()
                .Include(x => x.ComponentProduct)
                .Where(x => x.ComboProductId == id && x.StoreId == storeId && x.Deleted == null)
                .OrderBy(x => x.CreatedAt)
                .Select(x => new PosProductComboLineDto(
                    x.Id,
                    x.ComponentProductId,
                    x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                    x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                    x.Qty,
                    x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0m,
                    x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0m,
                    x.ComponentProduct != null ? x.ComponentProduct.BaseUnitName : ""))
                .ToListAsync();
            sellableQty = (await ComputeComboSellableAsync(storeId, [p.Id])).GetValueOrDefault(p.Id);
        }
        else
        {
            recipeLines = await dbContext.PosProductRecipeLines.AsNoTracking()
                .Include(x => x.ComponentProduct)
                .Where(x => x.ParentProductId == id && x.StoreId == storeId && x.Deleted == null)
                .OrderBy(x => x.CreatedAt)
                .Select(x => new PosProductComboLineDto(
                    x.Id,
                    x.ComponentProductId,
                    x.ComponentProduct != null ? x.ComponentProduct.ProductCode : "",
                    x.ComponentProduct != null ? x.ComponentProduct.Name : "",
                    x.Qty,
                    x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0m,
                    x.ComponentProduct != null ? x.ComponentProduct.BasePrice : 0m,
                    x.ComponentProduct != null ? x.ComponentProduct.BaseUnitName : ""))
                .ToListAsync();
            if (recipeLines.Count > 0)
            {
                sellableQty = recipeLines.Min(cl =>
                    cl.Qty > 0 ? Math.Floor(cl.ComponentOnHandQty / cl.Qty) : 0);
            }
        }

        return new PosProductDto(
            p.Id, p.ProductCode, p.Barcode, p.Name,
            p.CategoryId, p.Category?.Name, categoryPath,
            p.BrandId, p.Brand?.Name,
            p.StorageLocationId, p.StorageLocation?.Name,
            p.SupplierId, p.Supplier?.Name,
            p.ProductType.ToString(), p.Description, p.ImageUrl,
            p.CostPrice, p.BasePrice, p.VatRate, p.VatExempt, p.OnHandQty, p.ReservedQty,
            p.MinStockQty, p.MaxStockQty, p.Weight, p.WeightUnit, p.BaseUnitName,
            p.IsDirectSale, p.IsFavorite, p.IsActive, variantCount,
            avg > 0 ? avg : null, stockout,
            units, attrs,
            PosSaleQuickNotesHelper.Parse(p.SaleQuickNotesJson),
            p.CreatedAt, p.UpdatedAt,
            p.DefaultPrinterId, p.DefaultPrinter?.Name,
            p.WarrantyMonths, p.RequiresSerial, p.TrackExpiry, p.ExpiryWarningDays,
            p.ServiceBillingMode.ToString(), p.MinBillMinutes, p.BillRoundMinutes,
            p.GraceMinutes, p.RoundAfterMinutes,
            p.DefaultDurationMinutes, p.SessionPackCount,
            p.OpeningFee, p.OpeningMinutes, p.SessionPackValidDays,
            p.IsTopping, p.AllowToppings, p.AutoOpenToppingPopup,
            p.AllowDecimalQty, toppingOpts,
            groupIds, toppingGroups,
            SellableQty: sellableQty,
            ComboLines: comboLines,
            RecipeLines: recipeLines,
            ShowComboComponentsOnSell: p.ShowComboComponentsOnSell);
    }

    private async Task<(
        Dictionary<Guid, List<Guid>> groupIdsByProduct,
        Dictionary<Guid, List<PosProductToppingGroupDto>> groupsByProduct)>
        LoadToppingGroupsForProductsAsync(Guid storeId, IEnumerable<Guid> productIds)
    {
        var ids = productIds.Distinct().ToList();
        var emptyIds = new Dictionary<Guid, List<Guid>>();
        var emptyGroups = new Dictionary<Guid, List<PosProductToppingGroupDto>>();
        if (ids.Count == 0) return (emptyIds, emptyGroups);

        var links = await dbContext.PosProductToppingGroupLinks.AsNoTracking()
            .Where(l => ids.Contains(l.ProductId) && l.StoreId == storeId &&
                        l.Deleted == null && l.IsActive)
            .OrderBy(l => l.SortOrder)
            .ToListAsync();
        if (links.Count == 0) return (emptyIds, emptyGroups);

        var groupIds = links.Select(l => l.GroupId).Distinct().ToList();
        var groups = await dbContext.PosToppingGroups.AsNoTracking()
            .Where(g => groupIds.Contains(g.Id) && g.StoreId == storeId &&
                        g.Deleted == null && g.IsActive)
            .ToDictionaryAsync(g => g.Id);
        var items = await dbContext.PosToppingGroupItems.AsNoTracking()
            .Include(i => i.ToppingProduct)
            .Where(i => groupIds.Contains(i.GroupId) && i.StoreId == storeId &&
                        i.Deleted == null && i.IsActive)
            .OrderBy(i => i.SortOrder)
            .ToListAsync();
        var itemsByGroup = items.GroupBy(i => i.GroupId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var groupIdsByProduct = links
            .GroupBy(l => l.ProductId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.GroupId).Distinct().ToList());

        var groupsByProduct = new Dictionary<Guid, List<PosProductToppingGroupDto>>();
        foreach (var g in links.GroupBy(l => l.ProductId))
        {
            var list = new List<PosProductToppingGroupDto>();
            foreach (var link in g)
            {
                if (!groups.TryGetValue(link.GroupId, out var grp)) continue;
                itemsByGroup.TryGetValue(grp.Id, out var gItems);
                gItems ??= [];
                list.Add(new PosProductToppingGroupDto(
                    grp.Id,
                    grp.Name,
                    grp.SortOrder,
                    gItems.Select(i => new PosProductToppingOptionDto(
                        i.Id,
                        i.ToppingProductId,
                        i.ToppingProduct?.Name ?? "",
                        i.ExtraPrice ?? i.ToppingProduct?.BasePrice ?? 0,
                        i.SortOrder)).ToList()));
            }
            groupsByProduct[g.Key] = list;
        }
        return (groupIdsByProduct, groupsByProduct);
    }

    private async Task SyncToppingGroupsAsync(
        Guid storeId, Guid productId, List<Guid>? groupIds)
    {
        var existing = await dbContext.PosProductToppingGroupLinks
            .Where(l => l.ProductId == productId && l.StoreId == storeId && l.Deleted == null)
            .ToListAsync();
        if (groupIds == null || groupIds.Count == 0)
        {
            foreach (var e in existing)
            {
                e.Deleted = DateTime.UtcNow;
                e.DeletedBy = CurrentUserEmail;
                e.IsActive = false;
            }
            if (existing.Count > 0) await dbContext.SaveChangesAsync();
            return;
        }

        var want = groupIds.Distinct().ToList();
        var valid = await dbContext.PosToppingGroups.AsNoTracking()
            .Where(g => want.Contains(g.Id) && g.StoreId == storeId && g.Deleted == null)
            .Select(g => g.Id)
            .ToListAsync();
        var validSet = valid.ToHashSet();
        var keep = new HashSet<Guid>();
        var sort = 0;
        foreach (var gid in want)
        {
            if (!validSet.Contains(gid)) continue;
            keep.Add(gid);
            var row = existing.FirstOrDefault(e => e.GroupId == gid);
            if (row == null)
            {
                dbContext.PosProductToppingGroupLinks.Add(new PosProductToppingGroupLink
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = productId,
                    GroupId = gid,
                    SortOrder = sort,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                });
            }
            else
            {
                row.SortOrder = sort;
                row.IsActive = true;
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = CurrentUserEmail;
            }
            sort++;
        }
        foreach (var e in existing.Where(e => !keep.Contains(e.GroupId)))
        {
            e.Deleted = DateTime.UtcNow;
            e.DeletedBy = CurrentUserEmail;
            e.IsActive = false;
        }
        await dbContext.SaveChangesAsync();
    }

    private async Task SyncToppingsAsync(
        Guid storeId, Guid productId, bool allowToppings, List<PosProductToppingInput>? toppings)
    {
        var existing = await dbContext.PosProductToppingOptions
            .Where(t => t.ProductId == productId && t.StoreId == storeId && t.Deleted == null)
            .ToListAsync();
        if (!allowToppings || toppings == null || toppings.Count == 0)
        {
            foreach (var e in existing)
            {
                e.Deleted = DateTime.UtcNow;
                e.DeletedBy = CurrentUserEmail;
                e.IsActive = false;
            }
            if (existing.Count > 0) await dbContext.SaveChangesAsync();
            return;
        }

        var wantIds = toppings.Select(t => t.ToppingProductId).Distinct().ToList();
        var validToppingIds = await dbContext.PosProducts.AsNoTracking()
            .Where(p => wantIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.Id)
            .ToListAsync();
        var validSet = validToppingIds.ToHashSet();

        var now = DateTime.UtcNow;
        var keep = new HashSet<Guid>();
        var sort = 0;
        foreach (var input in toppings)
        {
            if (!validSet.Contains(input.ToppingProductId)) continue;
            if (input.ToppingProductId == productId) continue;
            keep.Add(input.ToppingProductId);
            var row = existing.FirstOrDefault(e => e.ToppingProductId == input.ToppingProductId);
            if (row == null)
            {
                dbContext.PosProductToppingOptions.Add(new PosProductToppingOption
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = productId,
                    ToppingProductId = input.ToppingProductId,
                    ExtraPrice = input.ExtraPrice,
                    SortOrder = input.SortOrder != 0 ? input.SortOrder : sort,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = CurrentUserEmail,
                });
            }
            else
            {
                row.ExtraPrice = input.ExtraPrice;
                row.SortOrder = input.SortOrder != 0 ? input.SortOrder : sort;
                row.IsActive = true;
                row.UpdatedAt = now;
                row.UpdatedBy = CurrentUserEmail;
            }
            sort++;
        }

        foreach (var e in existing.Where(e => !keep.Contains(e.ToppingProductId)))
        {
            e.Deleted = now;
            e.DeletedBy = CurrentUserEmail;
            e.IsActive = false;
        }

        await dbContext.SaveChangesAsync();
    }

    private async Task<Guid?> ResolvePrinterIdAsync(Guid storeId, Guid? printerId)
    {
        if (!printerId.HasValue) return null;
        var ok = await dbContext.PosStorePrinters.AnyAsync(p =>
            p.Id == printerId && p.StoreId == storeId && p.Deleted == null && p.IsActive);
        return ok ? printerId : null;
    }

    private async Task<Dictionary<Guid, decimal>> ComputeComboSellableAsync(
        Guid storeId, IReadOnlyList<Guid> comboIds)
    {
        var map = comboIds.Distinct().ToDictionary(id => id, _ => 0m);
        if (map.Count == 0) return map;
        var lines = await dbContext.PosProductComboLines.AsNoTracking()
            .Where(x => comboIds.Contains(x.ComboProductId) &&
                        x.StoreId == storeId && x.Deleted == null)
            .Select(x => new
            {
                x.ComboProductId,
                x.Qty,
                OnHand = x.ComponentProduct != null ? x.ComponentProduct.OnHandQty : 0m,
            })
            .ToListAsync();
        foreach (var g in lines.GroupBy(x => x.ComboProductId))
        {
            decimal? min = null;
            foreach (var cl in g)
            {
                if (cl.Qty <= 0)
                {
                    min = 0;
                    break;
                }
                var can = Math.Floor(cl.OnHand / cl.Qty);
                if (min == null || can < min) min = can;
            }
            map[g.Key] = min ?? 0;
        }
        return map;
    }

    private static void NormalizeByProductType(PosProduct entity)
    {
        if (entity.ProductType == PosProductType.Service)
        {
            entity.OnHandQty = 0;
            entity.ReservedQty = 0;
            entity.MinStockQty = 0;
            entity.MaxStockQty = 0;
            entity.WarrantyMonths = null;
            entity.RequiresSerial = false;
            entity.AllowDecimalQty = false;
            entity.TrackExpiry = false;
            entity.ShowComboComponentsOnSell = false;
            entity.IsTopping = false;
            // Giữ ServiceBillingMode / phút / SessionPackCount từ DTO
        }
        else if (entity.ProductType == PosProductType.Combo)
        {
            entity.OnHandQty = 0;
            entity.ReservedQty = 0;
            entity.MinStockQty = 0;
            entity.MaxStockQty = 0;
            entity.WarrantyMonths = null;
            entity.RequiresSerial = false;
            entity.AllowDecimalQty = false;
            entity.TrackExpiry = false;
            entity.ServiceBillingMode = PosServiceBillingMode.Flat;
            entity.MinBillMinutes = null;
            entity.BillRoundMinutes = null;
            entity.GraceMinutes = null;
            entity.RoundAfterMinutes = null;
            entity.DefaultDurationMinutes = null;
            entity.SessionPackCount = Math.Max(0, entity.SessionPackCount);
            entity.OpeningFee = 0;
            entity.OpeningMinutes = null;
            entity.SessionPackValidDays = 0;
            entity.IsTopping = false;
            // ShowComboComponentsOnSell chỉ có ý nghĩa với combo — giữ nguyên giá trị đã set từ DTO.
        }
        else
        {
            entity.ShowComboComponentsOnSell = false;
            entity.ServiceBillingMode = PosServiceBillingMode.Flat;
            entity.MinBillMinutes = null;
            entity.BillRoundMinutes = null;
            entity.GraceMinutes = null;
            entity.RoundAfterMinutes = null;
            entity.OpeningFee = 0;
            entity.OpeningMinutes = null;
            entity.SessionPackValidDays = 0;
            entity.DefaultDurationMinutes = null;
            entity.SessionPackCount = Math.Max(0, entity.SessionPackCount);

            if (entity.ProductType == PosProductType.Material)
            {
                entity.IsDirectSale = false;
                entity.IsTopping = false;
                entity.AllowToppings = false;
            }
            else if (entity.ProductType == PosProductType.Topping)
            {
                entity.IsTopping = true;
                entity.IsDirectSale = false;
                entity.AllowToppings = false;
            }
            else
            {
                entity.IsTopping = false;
            }
        }
    }

    private async Task<List<Guid>> GetCategoryDescendantIdsAsync(Guid storeId, Guid categoryId)
    {
        var all = await dbContext.PosProductCategories
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .Select(x => new { x.Id, x.ParentId })
            .ToListAsync();

        var result = new HashSet<Guid> { categoryId };
        var queue = new Queue<Guid>();
        queue.Enqueue(categoryId);
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            foreach (var child in all.Where(x => x.ParentId == current))
            {
                if (result.Add(child.Id))
                    queue.Enqueue(child.Id);
            }
        }

        return result.ToList();
    }

    private async Task<ActionResult<AppResponse<PosProductDto>>?> ValidateRefsAsync(
        Guid storeId, PosProductUpsertDto dto)
    {
        if (dto.CategoryId.HasValue && !await dbContext.PosProductCategories.AnyAsync(x =>
                x.Id == dto.CategoryId && x.StoreId == storeId && x.Deleted == null))
            return BadRequest(AppResponse<PosProductDto>.Fail("Nhóm hàng không hợp lệ"));

        if (dto.BrandId.HasValue && !await dbContext.PosProductBrands.AnyAsync(x =>
                x.Id == dto.BrandId && x.StoreId == storeId && x.Deleted == null))
            return BadRequest(AppResponse<PosProductDto>.Fail("Thương hiệu không hợp lệ"));

        if (dto.StorageLocationId.HasValue && !await dbContext.PosStorageLocations.AnyAsync(x =>
                x.Id == dto.StorageLocationId && x.StoreId == storeId && x.Deleted == null))
            return BadRequest(AppResponse<PosProductDto>.Fail("Vị trí kho không hợp lệ"));

        if (dto.SupplierId.HasValue && !await dbContext.PosSuppliers.AnyAsync(x =>
                x.Id == dto.SupplierId && x.StoreId == storeId && x.Deleted == null))
            return BadRequest(AppResponse<PosProductDto>.Fail("Nhà cung cấp không hợp lệ"));

        return null;
    }

    /// <summary>
    /// Mã tự tăng: HH / DV / CB / NVL / TP.
    /// </summary>
    private async Task<string> GenerateProductCodeAsync(Guid storeId, PosProductType productType)
    {
        var prefix = PosProductTypeRules.CodePrefix(productType);

        // Unique index StoreId+ProductCode includes soft-deleted rows — must IgnoreQueryFilters.
        var existing = await dbContext.PosProducts.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.ProductCode.StartsWith(prefix))
            .Select(p => p.ProductCode)
            .ToListAsync();

        var next = 1;
        foreach (var code in existing)
        {
            if (code.Length <= prefix.Length) continue;
            var tail = code[prefix.Length..];
            if (tail.Length == 0 || !tail.All(char.IsDigit)) continue;
            if (int.TryParse(tail, out var n) && n >= next)
                next = n + 1;
        }

        for (var attempt = 0; attempt < 20; attempt++)
        {
            var candidate = $"{prefix}{next + attempt:D5}";
            if (!existing.Contains(candidate, StringComparer.OrdinalIgnoreCase) &&
                !await dbContext.PosProducts.IgnoreQueryFilters().AnyAsync(p =>
                    p.StoreId == storeId && p.ProductCode == candidate))
                return candidate;
        }

        return $"{prefix}{DateTime.UtcNow:yyMMddHHmm}";
    }

    private async Task<string?> ResolveImageUrlAsync(Guid storeId, PosProductUpsertDto dto)
    {
        if (!string.IsNullOrWhiteSpace(dto.ImageBase64))
            return await TrySaveImageAsync(storeId, dto.ImageBase64);
        if (!string.IsNullOrWhiteSpace(dto.ImageUrl))
            return NormalizeStoredImageUrl(dto.ImageUrl);
        return null;
    }

    private static string NormalizeStoredImageUrl(string imageUrl)
    {
        var normalized = imageUrl.Trim().Replace('\\', '/');
        if (normalized.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                normalized = new Uri(normalized).AbsolutePath.TrimStart('/');
            }
            catch
            {
                normalized = normalized.TrimStart('/');
            }
        }
        else
        {
            normalized = normalized.TrimStart('/');
        }

        if (normalized.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase))
            normalized = normalized["wwwroot/".Length..];

        return normalized;
    }

    private async Task<string?> TrySaveImageAsync(Guid storeId, string? imageBase64)
    {
        if (string.IsNullOrWhiteSpace(imageBase64)) return null;
        try
        {
            var base64Data = imageBase64;
            if (base64Data.Contains(','))
                base64Data = base64Data[(base64Data.IndexOf(',') + 1)..];
            var bytes = Convert.FromBase64String(base64Data);
            var (optimized, fileName, _) = ImageOptimizeHelper.Optimize(
                bytes,
                $"pos_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.jpg",
                ImageOptimizeHelper.ProductMaxEdge,
                ImageOptimizeHelper.ProductJpegQuality);
            await using (optimized)
            {
                var folder = await GetStoreFolderAsync("uploads/pos-products");
                var path = await fileStorageService.UploadAsync(optimized, fileName, folder);
                // Lưu path tương đối (không gắn host) để tránh URL localhost/host cũ.
                return path.TrimStart('/');
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to upload POS product image");
            return null;
        }
    }

    private async Task EnsureBaseUnitAsync(PosProduct product)
    {
        var exists = await dbContext.PosProductUnits.AnyAsync(u =>
            u.ProductId == product.Id && u.IsBaseUnit && u.Deleted == null);
        if (exists) return;
        dbContext.PosProductUnits.Add(new PosProductUnit
        {
            Id = Guid.NewGuid(),
            StoreId = product.StoreId,
            ProductId = product.Id,
            UnitName = product.BaseUnitName,
            ConversionRate = 1,
            BasePrice = product.BasePrice,
            IsDirectSale = product.IsDirectSale,
            IsBaseUnit = true,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        });
        await dbContext.SaveChangesAsync();
    }

    private async Task<int> NextProductSortOrderAsync(Guid storeId, Guid? categoryId)
    {
        var q = dbContext.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null);
        if (categoryId.HasValue)
            q = q.Where(p => p.CategoryId == categoryId);
        var max = await q.Select(p => (int?)p.SortOrder).MaxAsync();
        return (max ?? -1) + 1;
    }

    private async Task SyncBaseUnitAsync(PosProduct product)
    {
        var unit = await dbContext.PosProductUnits
            .AsTracking()
            .FirstOrDefaultAsync(u => u.ProductId == product.Id && u.IsBaseUnit && u.Deleted == null);
        if (unit == null)
        {
            await EnsureBaseUnitAsync(product);
            return;
        }
        unit.UnitName = product.BaseUnitName;
        unit.BasePrice = product.BasePrice;
        unit.IsDirectSale = product.IsDirectSale;
        unit.UpdatedAt = DateTime.UtcNow;
        await dbContext.SaveChangesAsync();
    }

    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var storeId = RequiredStoreId;
        var storeCode = await dbContext.Stores
            .AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Code)
            .FirstOrDefaultAsync();
        if (!string.IsNullOrEmpty(storeCode))
            return $"stores/{storeCode}/{subfolder}";
        return subfolder;
    }

    /// <summary>
    /// Catalog mẫu lưu ở catalog/pos-samples — kho/bán hàng không serve folder đó.
    /// Copy sang stores/{code}/uploads/pos-products khi thêm từ catalog.
    /// </summary>
    private async Task<string?> CopyCatalogImageToStoreAsync(Guid storeId, string? sourceImageUrl)
    {
        if (string.IsNullOrWhiteSpace(sourceImageUrl)) return null;
        var normalized = NormalizeStoredImageUrl(sourceImageUrl);
        if (string.IsNullOrWhiteSpace(normalized)) return null;

        var alreadyStoreProduct = normalized.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase);
        if (alreadyStoreProduct)
            return normalized;

        var src = ResolveProductImagePath(normalized);
        if (src == null || !System.IO.File.Exists(src))
            return normalized;

        try
        {
            await using var fs = System.IO.File.OpenRead(src);
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                fs,
                Path.GetFileName(src),
                ImageOptimizeHelper.ProductMaxEdge,
                ImageOptimizeHelper.ProductJpegQuality);
            await using (optimized)
            {
                var folder = await GetStoreFolderAsync("uploads/pos-products");
                var path = await fileStorageService.UploadAsync(optimized, uploadName, folder);
                return path.TrimStart('/');
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Copy catalog image to store failed: {Path}", normalized);
            return normalized;
        }
    }

    private string? ResolveProductImagePath(string? imageUrl)
    {
        if (string.IsNullOrWhiteSpace(imageUrl)) return null;

        var normalized = imageUrl.Trim().Replace('\\', '/');
        if (normalized.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                normalized = new Uri(normalized).AbsolutePath.TrimStart('/');
            }
            catch
            {
                return null;
            }
        }
        else
        {
            normalized = normalized.TrimStart('/');
        }

        if (normalized.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase))
            normalized = normalized["wwwroot/".Length..];

        var wwwroot = Path.GetFullPath(
            Path.Combine(webHostEnvironment.ContentRootPath, "wwwroot"));
        var candidates = new List<string> { normalized };

        if (normalized.StartsWith("stores/", StringComparison.OrdinalIgnoreCase)
            && normalized.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase))
        {
            var parts = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 4)
                candidates.Add(string.Join('/', parts.Skip(1)));
        }
        else if (normalized.Contains("uploads/pos-products", StringComparison.OrdinalIgnoreCase)
                 && !normalized.StartsWith("stores/", StringComparison.OrdinalIgnoreCase))
        {
            candidates.Add($"stores/{normalized}");
        }

        foreach (var rel in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var full = Path.GetFullPath(
                Path.Combine(wwwroot, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (full.StartsWith(wwwroot, StringComparison.OrdinalIgnoreCase)
                && System.IO.File.Exists(full))
                return full;
        }

        return null;
    }
}
