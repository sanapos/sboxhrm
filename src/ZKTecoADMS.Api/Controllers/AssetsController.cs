using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Assets;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[Authorize]
[Route("api/[controller]")]
[ApiController]
public class AssetsController(ZKTecoDbContext context) : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _context = context;

    #region Helper Methods
    private string GenerateAssetCode()
    {
        var date = DateTime.UtcNow.ToString("yyyyMMdd");
        var count = _context.Assets.Count(a => a.StoreId == RequiredStoreId && a.AssetCode.StartsWith($"TS-{date}")) + 1;
        return $"TS-{date}-{count:D4}";
    }

    private string GenerateCategoryCode()
    {
        var count = _context.AssetCategories.Count(c => c.StoreId == RequiredStoreId) + 1;
        return $"DM-{count:D4}";
    }

    private string GenerateInventoryCode()
    {
        var date = DateTime.UtcNow.ToString("yyyyMMdd");
        var count = _context.AssetInventories.Count(i => i.StoreId == RequiredStoreId && i.InventoryCode.StartsWith($"KK-{date}")) + 1;
        return $"KK-{date}-{count:D3}";
    }

    private static string GetAssetTypeName(AssetType type) => type switch
    {
        AssetType.Electronics => "Thiáº¿t bá»‹ Ä‘iá»‡n tá»­",
        AssetType.Furniture => "Ná»™i tháº¥t",
        AssetType.Vehicle => "PhÆ°Æ¡ng tiá»‡n",
        AssetType.Tool => "CÃ´ng cá»¥ dá»¥ng cá»¥",
        AssetType.Machinery => "MÃ¡y mÃ³c",
        AssetType.Software => "Pháº§n má»m",
        _ => "KhÃ¡c"
    };

    private static string GetAssetStatusName(AssetStatus status) => status switch
    {
        AssetStatus.Active => "Äang sá»­ dá»¥ng",
        AssetStatus.InMaintenance => "Äang báº£o trÃ¬",
        AssetStatus.Broken => "Há»ng",
        AssetStatus.Disposed => "ÄÃ£ thanh lÃ½",
        AssetStatus.Lost => "ÄÃ£ máº¥t",
        AssetStatus.InStock => "Trong kho",
        _ => "KhÃ´ng xÃ¡c Ä‘á»‹nh"
    };

    private static string GetTransferTypeName(AssetTransferType type) => type switch
    {
        AssetTransferType.Assignment => "Cáº¥p má»›i",
        AssetTransferType.Transfer => "Chuyá»ƒn giao",
        AssetTransferType.Return => "Thu há»“i",
        AssetTransferType.Maintenance => "Báº£o trÃ¬",
        AssetTransferType.Disposal => "Thanh lÃ½",
        _ => "KhÃ¡c"
    };

    private static string GetConditionName(InventoryCondition? condition) => condition switch
    {
        InventoryCondition.Good => "Tá»‘t",
        InventoryCondition.Fair => "BÃ¬nh thÆ°á»ng",
        InventoryCondition.Poor => "KÃ©m",
        InventoryCondition.Damaged => "Há»ng",
        InventoryCondition.NotFound => "KhÃ´ng tÃ¬m tháº¥y",
        _ => "ChÆ°a kiá»ƒm"
    };

    private static string GetInventoryStatusName(int status) => status switch
    {
        0 => "Äang tiáº¿n hÃ nh",
        1 => "HoÃ n thÃ nh",
        2 => "ÄÃ£ há»§y",
        _ => "KhÃ´ng xÃ¡c Ä‘á»‹nh"
    };
    #endregion

    #region Asset Categories
    [HttpGet("categories")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCategories()
    {
        var categories = await _context.AssetCategories
            .Where(c => c.StoreId == RequiredStoreId && c.IsActive)
            .Include(c => c.ParentCategory)
            .Include(c => c.SubCategories)
            .OrderBy(c => c.Name)
            .ToListAsync();

        var assetCounts = await _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.CategoryId != null)
            .GroupBy(a => a.CategoryId)
            .Select(g => new { CategoryId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.CategoryId!.Value, x => x.Count);

        var dtos = categories.Where(c => c.ParentCategoryId == null).Select(c => MapCategoryToDto(c, assetCounts)).ToList();
        return Ok(AppResponse<List<AssetCategoryDto>>.Success(dtos));
    }

    private AssetCategoryDto MapCategoryToDto(AssetCategory c, Dictionary<Guid, int> counts)
    {
        return new AssetCategoryDto
        {
            Id = c.Id,
            CategoryCode = c.CategoryCode,
            Name = c.Name,
            Description = c.Description,
            ParentCategoryId = c.ParentCategoryId,
            ParentCategoryName = c.ParentCategory?.Name,
            AssetCount = counts.GetValueOrDefault(c.Id),
            IsActive = c.IsActive,
            CreatedAt = c.CreatedAt,
            SubCategories = c.SubCategories?.Select(sc => MapCategoryToDto(sc, counts)).ToList()
        };
    }

    [HttpPost("categories")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> CreateCategory([FromBody] CreateAssetCategoryDto request)
    {
        var category = new AssetCategory
        {
            Id = Guid.NewGuid(),
            IsActive = true,
            CategoryCode = GenerateCategoryCode(),
            Name = request.Name,
            Description = request.Description,
            ParentCategoryId = request.ParentCategoryId,
            StoreId = RequiredStoreId,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserId.ToString()
        };

        _context.AssetCategories.Add(category);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<AssetCategoryDto>.Success(new AssetCategoryDto
        {
            Id = category.Id,
            CategoryCode = category.CategoryCode,
            Name = category.Name,
            Description = category.Description,
            ParentCategoryId = category.ParentCategoryId,
            IsActive = category.IsActive,
            CreatedAt = category.CreatedAt
        }));
    }

    [HttpPut("categories/{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateCategory(Guid id, [FromBody] UpdateAssetCategoryDto request)
    {
        var category = await _context.AssetCategories
            .AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

        if (category == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        category.Name = request.Name;
        category.Description = request.Description;
        category.ParentCategoryId = request.ParentCategoryId;
        category.IsActive = request.IsActive;
        category.UpdatedAt = DateTime.UtcNow;
        category.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Cáº­p nháº­t danh má»¥c thÃ nh cÃ´ng"));
    }

    [HttpDelete("categories/{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteCategory(Guid id)
    {
        var category = await _context.AssetCategories
            .Include(c => c.Assets)
            .Include(c => c.SubCategories)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

        if (category == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        if (category.Assets.Any())
            return BadRequest(AppResponse<object>.Error("KhÃ´ng thá»ƒ xÃ³a danh má»¥c Ä‘ang cÃ³ tÃ i sáº£n"));

        if (category.SubCategories.Any())
            return BadRequest(AppResponse<object>.Error("KhÃ´ng thá»ƒ xÃ³a danh má»¥c Ä‘ang cÃ³ danh má»¥c con"));

        _context.AssetCategories.Remove(category);
        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("XÃ³a danh má»¥c thÃ nh cÃ´ng"));
    }
    #endregion

    #region Assets CRUD
    [HttpGet]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAssets([FromQuery] AssetQueryParams query)
    {
        var q = _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.IsActive)
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .Include(a => a.Images.Where(i => i.IsPrimary))
            .AsQueryable();

        // Apply filters
        if (!string.IsNullOrEmpty(query.Search))
        {
            var searchPattern = $"%{query.Search}%";
            q = q.Where(a => EF.Functions.ILike(a.AssetCode, searchPattern) ||
                            EF.Functions.ILike(a.Name, searchPattern) ||
                            (a.SerialNumber != null && EF.Functions.ILike(a.SerialNumber, searchPattern)) ||
                            (a.Brand != null && EF.Functions.ILike(a.Brand, searchPattern)));
        }

        if (query.AssetType.HasValue)
            q = q.Where(a => a.AssetType == query.AssetType.Value);

        if (query.Status.HasValue)
            q = q.Where(a => a.Status == query.Status.Value);

        if (query.CategoryId.HasValue)
            q = q.Where(a => a.CategoryId == query.CategoryId.Value);

        if (!string.IsNullOrEmpty(query.AssigneeId))
            q = q.Where(a => a.CurrentAssigneeId.HasValue && a.CurrentAssigneeId.Value.ToString() == query.AssigneeId);

        if (!string.IsNullOrEmpty(query.Location))
            q = q.Where(a => a.Location != null && a.Location.Contains(query.Location));

        if (query.HasSerialNumber == true)
            q = q.Where(a => a.SerialNumber != null && a.SerialNumber != "");

        if (query.WarrantyExpiringSoon == true)
        {
            var threshold = DateTime.UtcNow.AddDays(30);
            q = q.Where(a => a.WarrantyExpiry.HasValue && a.WarrantyExpiry.Value <= threshold && a.WarrantyExpiry.Value > DateTime.UtcNow);
        }

        if (query.PurchaseDateFrom.HasValue)
            q = q.Where(a => a.PurchaseDate >= query.PurchaseDateFrom.Value);

        if (query.PurchaseDateTo.HasValue)
            q = q.Where(a => a.PurchaseDate <= query.PurchaseDateTo.Value);

        if (query.MinPrice.HasValue)
            q = q.Where(a => a.PurchasePrice >= query.MinPrice.Value);

        if (query.MaxPrice.HasValue)
            q = q.Where(a => a.PurchasePrice <= query.MaxPrice.Value);

        // Sorting
        q = query.SortBy?.ToLower() switch
        {
            "name" => query.SortDesc ? q.OrderByDescending(a => a.Name) : q.OrderBy(a => a.Name),
            "code" => query.SortDesc ? q.OrderByDescending(a => a.AssetCode) : q.OrderBy(a => a.AssetCode),
            "price" => query.SortDesc ? q.OrderByDescending(a => a.PurchasePrice) : q.OrderBy(a => a.PurchasePrice),
            "purchasedate" => query.SortDesc ? q.OrderByDescending(a => a.PurchaseDate) : q.OrderBy(a => a.PurchaseDate),
            "status" => query.SortDesc ? q.OrderByDescending(a => a.Status) : q.OrderBy(a => a.Status),
            _ => q.OrderByDescending(a => a.CreatedAt)
        };

        var total = await q.CountAsync();
        var items = await q.Skip((query.Page - 1) * query.PageSize).Take(query.PageSize).ToListAsync();

        var dtos = items.Select(a => new AssetDto
        {
            Id = a.Id,
            AssetCode = a.AssetCode,
            QrCode = a.QrCode ?? a.AssetCode,
            Name = a.Name,
            Description = a.Description,
            SerialNumber = a.SerialNumber,
            Model = a.Model,
            Brand = a.Brand,
            Size = a.Size,
            Color = a.Color,
            AssetType = a.AssetType,
            AssetTypeName = GetAssetTypeName(a.AssetType),
            CategoryId = a.CategoryId,
            CategoryName = a.Category?.Name,
            Status = a.Status,
            StatusName = GetAssetStatusName(a.Status),
            Quantity = a.Quantity,
            Unit = a.Unit,
            PurchasePrice = a.PurchasePrice,
            Currency = a.Currency,
            PurchaseDate = a.PurchaseDate,
            Supplier = a.Supplier,
            InvoiceNumber = a.InvoiceNumber,
            WarrantyMonths = a.WarrantyMonths,
            WarrantyExpiry = a.WarrantyExpiry,
            IsWarrantyExpired = a.WarrantyExpiry.HasValue && a.WarrantyExpiry.Value < DateTime.UtcNow,
            DaysUntilWarrantyExpiry = a.WarrantyExpiry.HasValue ? (int)(a.WarrantyExpiry.Value - DateTime.UtcNow).TotalDays : 0,
            Location = a.Location,
            Notes = a.Notes,
            DepreciationRate = a.DepreciationRate,
            CurrentValue = a.CurrentValue,
            CurrentAssigneeId = a.CurrentAssigneeId?.ToString(),
            CurrentAssigneeName = a.CurrentAssignee != null ? $"{a.CurrentAssignee.FirstName} {a.CurrentAssignee.LastName}" : null,
            AssignedDate = a.AssignedDate,
            IsActive = a.IsActive,
            CreatedAt = a.CreatedAt,
            PrimaryImageUrl = a.Images.FirstOrDefault(i => i.IsPrimary)?.ImageUrl
        }).ToList();

        return Ok(AppResponse<object>.Success(new { items = dtos, totalCount = total, page = query.Page, pageSize = query.PageSize }));
    }

    [HttpGet("{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAsset(Guid id)
    {
        var asset = await _context.Assets
            .Where(a => a.Id == id && a.StoreId == RequiredStoreId)
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .Include(a => a.Images.OrderBy(i => i.DisplayOrder))
            .Include(a => a.Transfers.OrderByDescending(t => t.TransferDate).Take(20))
                .ThenInclude(t => t.FromUser)
            .Include(a => a.Transfers)
                .ThenInclude(t => t.ToUser)
            .FirstOrDefaultAsync();

        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        var dto = new AssetDetailDto
        {
            Id = asset.Id,
            AssetCode = asset.AssetCode,
            QrCode = asset.QrCode ?? asset.AssetCode,
            Name = asset.Name,
            Description = asset.Description,
            SerialNumber = asset.SerialNumber,
            Model = asset.Model,
            Brand = asset.Brand,
            Size = asset.Size,
            Color = asset.Color,
            AssetType = asset.AssetType,
            AssetTypeName = GetAssetTypeName(asset.AssetType),
            CategoryId = asset.CategoryId,
            CategoryName = asset.Category?.Name,
            Status = asset.Status,
            StatusName = GetAssetStatusName(asset.Status),
            Quantity = asset.Quantity,
            Unit = asset.Unit,
            PurchasePrice = asset.PurchasePrice,
            Currency = asset.Currency,
            PurchaseDate = asset.PurchaseDate,
            Supplier = asset.Supplier,
            InvoiceNumber = asset.InvoiceNumber,
            WarrantyMonths = asset.WarrantyMonths,
            WarrantyExpiry = asset.WarrantyExpiry,
            IsWarrantyExpired = asset.WarrantyExpiry.HasValue && asset.WarrantyExpiry.Value < DateTime.UtcNow,
            DaysUntilWarrantyExpiry = asset.WarrantyExpiry.HasValue ? (int)(asset.WarrantyExpiry.Value - DateTime.UtcNow).TotalDays : 0,
            Location = asset.Location,
            Notes = asset.Notes,
            DepreciationRate = asset.DepreciationRate,
            CurrentValue = asset.CurrentValue,
            CurrentAssigneeId = asset.CurrentAssigneeId?.ToString(),
            CurrentAssigneeName = asset.CurrentAssignee != null ? $"{asset.CurrentAssignee.FirstName} {asset.CurrentAssignee.LastName}" : null,
            AssignedDate = asset.AssignedDate,
            IsActive = asset.IsActive,
            CreatedAt = asset.CreatedAt,
            Images = asset.Images.Select(i => new AssetImageDto
            {
                Id = i.Id,
                AssetId = i.AssetId,
                ImageUrl = i.ImageUrl,
                FileName = i.FileName,
                Description = i.Description,
                IsPrimary = i.IsPrimary,
                DisplayOrder = i.DisplayOrder
            }).ToList(),
            PrimaryImageUrl = asset.Images.FirstOrDefault(i => i.IsPrimary)?.ImageUrl,
            TransferHistory = asset.Transfers.Select(t => new AssetTransferDto
            {
                Id = t.Id,
                AssetId = t.AssetId,
                AssetCode = asset.AssetCode,
                AssetName = asset.Name,
                TransferType = t.TransferType,
                TransferTypeName = GetTransferTypeName(t.TransferType),
                FromUserId = t.FromUserId?.ToString(),
                FromUserName = t.FromUser != null ? $"{t.FromUser.FirstName} {t.FromUser.LastName}" : null,
                ToUserId = t.ToUserId?.ToString(),
                ToUserName = t.ToUser != null ? $"{t.ToUser.FirstName} {t.ToUser.LastName}" : null,
                Quantity = t.Quantity,
                TransferDate = t.TransferDate,
                Reason = t.Reason,
                Notes = t.Notes,
                IsConfirmed = t.IsConfirmed,
                ConfirmedAt = t.ConfirmedAt,
                CreatedAt = t.CreatedAt
            }).ToList()
        };

        return Ok(AppResponse<AssetDetailDto>.Success(dto));
    }

    [HttpPost]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> CreateAsset([FromBody] CreateAssetDto request)
    {
        var asset = new Asset
        {
            Id = Guid.NewGuid(),
            IsActive = true,
            AssetCode = GenerateAssetCode(),
            Name = request.Name,
            Description = request.Description,
            SerialNumber = request.SerialNumber,
            Model = request.Model,
            Brand = request.Brand,
            Size = request.Size,
            Color = request.Color,
            AssetType = request.AssetType,
            CategoryId = request.CategoryId,
            Status = AssetStatus.InStock,
            Quantity = request.Quantity,
            Unit = request.Unit,
            PurchasePrice = request.PurchasePrice,
            Currency = request.Currency,
            PurchaseDate = request.PurchaseDate,
            Supplier = request.Supplier,
            InvoiceNumber = request.InvoiceNumber,
            WarrantyMonths = request.WarrantyMonths,
            WarrantyExpiry = request.WarrantyMonths.HasValue && request.PurchaseDate.HasValue
                ? request.PurchaseDate.Value.AddMonths(request.WarrantyMonths.Value)
                : null,
            Location = request.Location,
            Notes = request.Notes,
            DepreciationRate = request.DepreciationRate,
            CurrentValue = request.PurchasePrice,
            StoreId = RequiredStoreId,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserId.ToString()
        };

        // QrCode defaults to AssetCode if not provided
        asset.QrCode = !string.IsNullOrWhiteSpace(request.QrCode) ? request.QrCode : asset.AssetCode;

        _context.Assets.Add(asset);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<AssetDto>.Success(new AssetDto
        {
            Id = asset.Id,
            AssetCode = asset.AssetCode,
            QrCode = asset.QrCode,
            Name = asset.Name,
            AssetType = asset.AssetType,
            AssetTypeName = GetAssetTypeName(asset.AssetType),
            Status = asset.Status,
            StatusName = GetAssetStatusName(asset.Status),
            CreatedAt = asset.CreatedAt
        }));
    }

    [HttpPut("{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateAsset(Guid id, [FromBody] UpdateAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == id && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        asset.Name = request.Name;
        asset.Description = request.Description;
        asset.SerialNumber = request.SerialNumber;
        if (request.QrCode != null) asset.QrCode = request.QrCode;
        asset.Model = request.Model;
        asset.Brand = request.Brand;
        asset.Size = request.Size;
        asset.Color = request.Color;
        asset.AssetType = request.AssetType;
        asset.CategoryId = request.CategoryId;
        asset.Status = request.Status;
        asset.Quantity = request.Quantity;
        asset.Unit = request.Unit;
        asset.PurchasePrice = request.PurchasePrice;
        asset.Currency = request.Currency;
        asset.PurchaseDate = request.PurchaseDate;
        asset.Supplier = request.Supplier;
        asset.InvoiceNumber = request.InvoiceNumber;
        asset.WarrantyMonths = request.WarrantyMonths;
        asset.WarrantyExpiry = request.WarrantyMonths.HasValue && request.PurchaseDate.HasValue
            ? request.PurchaseDate.Value.AddMonths(request.WarrantyMonths.Value)
            : null;
        asset.Location = request.Location;
        asset.Notes = request.Notes;
        asset.DepreciationRate = request.DepreciationRate;
        asset.CurrentValue = request.CurrentValue;
        asset.UpdatedAt = DateTime.UtcNow;
        asset.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Cáº­p nháº­t tÃ i sáº£n thÃ nh cÃ´ng"));
    }

    [HttpDelete("{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteAsset(Guid id)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == id && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        asset.IsActive = false;
        asset.UpdatedAt = DateTime.UtcNow;
        asset.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("XÃ³a tÃ i sáº£n thÃ nh cÃ´ng"));
    }
    #endregion

    #region Asset Images
    [HttpPost("{assetId}/images")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> AddImage(Guid assetId, [FromBody] AddAssetImageDto request)
    {
        var asset = await _context.Assets.AsTracking().Include(a => a.Images).FirstOrDefaultAsync(a => a.Id == assetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        if (request.IsPrimary)
        {
            foreach (var img in asset.Images.Where(i => i.IsPrimary))
                img.IsPrimary = false;
        }

        var image = new AssetImage
        {
            Id = Guid.NewGuid(),
            AssetId = assetId,
            ImageUrl = request.ImageUrl,
            FileName = request.FileName,
            Description = request.Description,
            IsPrimary = request.IsPrimary || !asset.Images.Any(),
            DisplayOrder = asset.Images.Count,
            CreatedAt = DateTime.UtcNow
        };

        _context.AssetImages.Add(image);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<AssetImageDto>.Success(new AssetImageDto
        {
            Id = image.Id,
            AssetId = image.AssetId,
            ImageUrl = image.ImageUrl,
            FileName = image.FileName,
            Description = image.Description,
            IsPrimary = image.IsPrimary,
            DisplayOrder = image.DisplayOrder
        }));
    }

    [HttpDelete("{assetId}/images/{imageId}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteImage(Guid assetId, Guid imageId)
    {
        var image = await _context.AssetImages.FirstOrDefaultAsync(i => i.Id == imageId && i.AssetId == assetId);
        if (image == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y hÃ¬nh áº£nh"));

        _context.AssetImages.Remove(image);
        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("XÃ³a hÃ¬nh áº£nh thÃ nh cÃ´ng"));
    }

    [HttpPatch("{assetId}/images/{imageId}/primary")]
    [RequireModulePermission("Asset", ModulePermissionAction.Edit)]
    public async Task<IActionResult> SetPrimaryImage(Guid assetId, Guid imageId)
    {
        var images = await _context.AssetImages.AsTracking().Where(i => i.AssetId == assetId).ToListAsync();
        foreach (var img in images)
            img.IsPrimary = img.Id == imageId;

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Äáº·t hÃ¬nh chÃ­nh thÃ nh cÃ´ng"));
    }
    #endregion

    #region Asset Transfer & Assignment
    /// <summary>
    /// Validate EmployeeId: checks that the given ID is a valid Employee.
    /// </summary>
    private async Task<Guid?> ValidateEmployeeIdAsync(string? employeeIdStr)
    {
        if (string.IsNullOrWhiteSpace(employeeIdStr)) return null;
        if (!Guid.TryParse(employeeIdStr, out var parsedId)) return null;

        var exists = await _context.Employees.AnyAsync(e => e.Id == parsedId);
        if (exists) return parsedId;

        return null;
    }

    [HttpPost("assign")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> AssignAsset([FromBody] AssignAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        if (asset.CurrentAssigneeId != null)
            return BadRequest(AppResponse<object>.Error("TÃ i sáº£n Ä‘Ã£ Ä‘Æ°á»£c cáº¥p cho ngÆ°á»i khÃ¡c. Vui lÃ²ng thu há»“i trÆ°á»›c."));

        if (request.Quantity > asset.Quantity)
            return BadRequest(AppResponse<object>.Error("Sá»‘ lÆ°á»£ng cáº¥p vÆ°á»£t quÃ¡ sá»‘ lÆ°á»£ng cÃ³"));

        var employeeId = await ValidateEmployeeIdAsync(request.ToUserId);
        if (employeeId == null)
            return BadRequest(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y nhÃ¢n viÃªn"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Assignment,
            ToUserId = employeeId,
            Quantity = request.Quantity,
            TransferDate = DateTime.UtcNow,
            Reason = request.Reason,
            Notes = request.Notes,
            PerformedById = CurrentUserId,
            IsConfirmed = false,
            CreatedAt = DateTime.UtcNow
        };

        asset.CurrentAssigneeId = employeeId;
        asset.AssignedDate = DateTime.UtcNow;
        asset.Status = AssetStatus.Active;

        _context.AssetTransfers.Add(transfer);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<string>.Success("Cáº¥p tÃ i sáº£n thÃ nh cÃ´ng"));
    }

    [HttpPost("transfer")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> TransferAsset([FromBody] TransferAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        // Validate FromUserId as EmployeeId
        if (!Guid.TryParse(request.FromUserId, out var fromEmployeeId) || asset.CurrentAssigneeId != fromEmployeeId)
            return BadRequest(AppResponse<object>.Error("TÃ i sáº£n khÃ´ng thuá»™c ngÆ°á»i chuyá»ƒn giao"));

        var toEmployeeId = await ValidateEmployeeIdAsync(request.ToUserId);
        if (toEmployeeId == null)
            return BadRequest(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y nhÃ¢n viÃªn nháº­n"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Transfer,
            FromUserId = fromEmployeeId,
            ToUserId = toEmployeeId,
            Quantity = request.Quantity,
            TransferDate = DateTime.UtcNow,
            Reason = request.Reason,
            Notes = request.Notes,
            PerformedById = CurrentUserId,
            IsConfirmed = false,
            CreatedAt = DateTime.UtcNow
        };

        asset.CurrentAssigneeId = toEmployeeId;
        asset.AssignedDate = DateTime.UtcNow;

        _context.AssetTransfers.Add(transfer);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<string>.Success("Chuyá»ƒn giao tÃ i sáº£n thÃ nh cÃ´ng"));
    }

    [HttpPost("return")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> ReturnAsset([FromBody] ReturnAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n"));

        if (!Guid.TryParse(request.FromUserId, out var fromEmployeeId) || asset.CurrentAssigneeId != fromEmployeeId)
            return BadRequest(AppResponse<object>.Error("TÃ i sáº£n khÃ´ng thuá»™c ngÆ°á»i nÃ y"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Return,
            FromUserId = fromEmployeeId,
            Quantity = request.Quantity,
            TransferDate = DateTime.UtcNow,
            Reason = request.Reason,
            Notes = request.Notes,
            PerformedById = CurrentUserId,
            IsConfirmed = true,
            ConfirmedAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow
        };

        asset.CurrentAssigneeId = null;
        asset.AssignedDate = null;
        asset.Status = AssetStatus.InStock;

        _context.AssetTransfers.Add(transfer);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<string>.Success("Thu há»“i tÃ i sáº£n thÃ nh cÃ´ng"));
    }

    [HttpPost("transfers/{transferId}/confirm")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> ConfirmTransfer(Guid transferId, [FromBody] ConfirmTransferDto request)
    {
        var transfer = await _context.AssetTransfers
            .AsTracking()
            .Include(t => t.Asset)
            .FirstOrDefaultAsync(t => t.Id == transferId && t.Asset!.StoreId == RequiredStoreId);

        if (transfer == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y chuyá»ƒn giao"));

        // ToUserId is now EmployeeId, resolve current user's EmployeeId for comparison
        var currentEmployee = await _context.Employees.FirstOrDefaultAsync(e => e.ApplicationUserId == CurrentUserId);
        if (currentEmployee == null || transfer.ToUserId != currentEmployee.Id)
            return BadRequest(AppResponse<object>.Error("Báº¡n khÃ´ng pháº£i ngÆ°á»i nháº­n tÃ i sáº£n nÃ y"));

        transfer.IsConfirmed = true;
        transfer.ConfirmedAt = DateTime.UtcNow;
        transfer.Notes = transfer.Notes != null ? $"{transfer.Notes}\n{request.Notes}" : request.Notes;

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("XÃ¡c nháº­n nháº­n tÃ i sáº£n thÃ nh cÃ´ng"));
    }

    [HttpGet("transfers")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetTransfers([FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] AssetTransferType? type)
    {
        var q = _context.AssetTransfers
            .Where(t => t.Asset!.StoreId == RequiredStoreId)
            .Include(t => t.Asset)
            .Include(t => t.FromUser)
            .Include(t => t.ToUser)
            .Include(t => t.PerformedBy)
            .OrderByDescending(t => t.TransferDate)
            .AsQueryable();

        if (fromDate.HasValue)
            q = q.Where(t => t.TransferDate >= fromDate.Value);
        if (toDate.HasValue)
            q = q.Where(t => t.TransferDate <= toDate.Value);
        if (type.HasValue)
            q = q.Where(t => t.TransferType == type.Value);

        var transfers = await q.Take(100).ToListAsync();

        var dtos = transfers.Select(t => new AssetTransferDto
        {
            Id = t.Id,
            AssetId = t.AssetId,
            AssetCode = t.Asset?.AssetCode,
            AssetName = t.Asset?.Name,
            TransferType = t.TransferType,
            TransferTypeName = GetTransferTypeName(t.TransferType),
            FromUserId = t.FromUserId?.ToString(),
            FromUserName = t.FromUser != null ? $"{t.FromUser.FirstName} {t.FromUser.LastName}" : null,
            ToUserId = t.ToUserId?.ToString(),
            ToUserName = t.ToUser != null ? $"{t.ToUser.FirstName} {t.ToUser.LastName}" : null,
            Quantity = t.Quantity,
            TransferDate = t.TransferDate,
            Reason = t.Reason,
            Notes = t.Notes,
            PerformedById = t.PerformedById?.ToString(),
            PerformedByName = t.PerformedBy?.FullName,
            IsConfirmed = t.IsConfirmed,
            ConfirmedAt = t.ConfirmedAt,
            CreatedAt = t.CreatedAt
        }).ToList();

        return Ok(AppResponse<List<AssetTransferDto>>.Success(dtos));
    }

    [HttpGet("my-assets")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetMyAssets()
    {
        var assets = await _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.CurrentAssigneeId == CurrentUserId && a.IsActive)
            .Include(a => a.Category)
            .Include(a => a.Images.Where(i => i.IsPrimary))
            .OrderBy(a => a.Name)
            .ToListAsync();

        var dtos = assets.Select(a => new AssetDto
        {
            Id = a.Id,
            AssetCode = a.AssetCode,
            QrCode = a.QrCode ?? a.AssetCode,
            Name = a.Name,
            SerialNumber = a.SerialNumber,
            Model = a.Model,
            Brand = a.Brand,
            AssetType = a.AssetType,
            AssetTypeName = GetAssetTypeName(a.AssetType),
            CategoryName = a.Category?.Name,
            Status = a.Status,
            StatusName = GetAssetStatusName(a.Status),
            AssignedDate = a.AssignedDate,
            PrimaryImageUrl = a.Images.FirstOrDefault()?.ImageUrl
        }).ToList();

        return Ok(AppResponse<List<AssetDto>>.Success(dtos));
    }
    #endregion

    #region QR / Lookup
    [HttpGet("lookup")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> LookupAsset([FromQuery] string code)
    {
        if (string.IsNullOrWhiteSpace(code))
            return BadRequest(AppResponse<object>.Error("MÃ£ khÃ´ng há»£p lá»‡"));

        var asset = await _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.IsActive &&
                (a.QrCode == code || a.AssetCode == code))
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .Include(a => a.Images)
            .FirstOrDefaultAsync();

        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i sáº£n vá»›i mÃ£: " + code));

        var dto = new AssetDetailDto
        {
            Id = asset.Id,
            AssetCode = asset.AssetCode,
            QrCode = asset.QrCode ?? asset.AssetCode,
            Name = asset.Name,
            Description = asset.Description,
            SerialNumber = asset.SerialNumber,
            Model = asset.Model,
            Brand = asset.Brand,
            Size = asset.Size,
            Color = asset.Color,
            AssetType = asset.AssetType,
            AssetTypeName = GetAssetTypeName(asset.AssetType),
            CategoryId = asset.CategoryId,
            CategoryName = asset.Category?.Name,
            Status = asset.Status,
            StatusName = GetAssetStatusName(asset.Status),
            PurchaseDate = asset.PurchaseDate,
            PurchasePrice = asset.PurchasePrice,
            CurrentValue = asset.CurrentValue,
            WarrantyExpiry = asset.WarrantyExpiry,
            Location = asset.Location,
            Quantity = asset.Quantity,
            Supplier = asset.Supplier,
            CurrentAssigneeId = asset.CurrentAssigneeId?.ToString(),
            CurrentAssigneeName = asset.CurrentAssignee != null ? $"{asset.CurrentAssignee.FirstName} {asset.CurrentAssignee.LastName}" : null,
            AssignedDate = asset.AssignedDate,
            Notes = asset.Notes,
            PrimaryImageUrl = asset.Images.FirstOrDefault(i => i.IsPrimary)?.ImageUrl,
            Images = asset.Images.OrderByDescending(i => i.IsPrimary).Select(i => new AssetImageDto
            {
                Id = i.Id,
                ImageUrl = i.ImageUrl,
                IsPrimary = i.IsPrimary,
                Description = i.Description
            }).ToList()
        };

        return Ok(AppResponse<AssetDetailDto>.Success(dto));
    }

    [HttpPost("inventories/{id}/scan")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> ScanInventoryItem(Guid id, [FromBody] ScanInventoryItemDto request)
    {
        var inventory = await _context.AssetInventories
            .Include(i => i.Items).ThenInclude(item => item.Asset)
            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == RequiredStoreId);

        if (inventory == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y Ä‘á»£t kiá»ƒm kÃª"));

        if (inventory.Status != 0)
            return BadRequest(AppResponse<object>.Error("Äá»£t kiá»ƒm kÃª Ä‘Ã£ káº¿t thÃºc"));

        var item = inventory.Items.FirstOrDefault(i =>
            i.Asset != null && (i.Asset.QrCode == request.Code || i.Asset.AssetCode == request.Code));

        if (item == null)
            return NotFound(AppResponse<object>.Error("TÃ i sáº£n vá»›i mÃ£ " + request.Code + " khÃ´ng náº±m trong Ä‘á»£t kiá»ƒm kÃª nÃ y"));

        item.IsChecked = true;
        item.CheckedAt = DateTime.UtcNow;
        item.CheckedById = CurrentUserId;
        item.Condition = request.Condition;
        item.ActualQuantity = request.ActualQuantity;
        item.ActualLocation = request.ActualLocation;
        item.HasIssue = request.HasIssue;
        item.IssueDescription = request.IssueDescription;
        item.Notes = request.Notes;

        await _context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            assetId = item.AssetId,
            assetCode = item.Asset?.AssetCode,
            assetName = item.Asset?.Name,
            isChecked = true,
            checkedAt = item.CheckedAt,
            message = "Kiá»ƒm kÃª tÃ i sáº£n thÃ nh cÃ´ng: " + (item.Asset?.Name ?? request.Code)
        }));
    }

    [HttpGet("{assetId}/inventory-history")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAssetInventoryHistory(Guid assetId)
    {
        var items = await _context.AssetInventoryItems
            .Where(i => i.AssetId == assetId && i.Inventory!.StoreId == RequiredStoreId)
            .Include(i => i.Inventory)
            .Include(i => i.CheckedBy)
            .OrderByDescending(i => i.Inventory!.StartDate)
            .ToListAsync();

        var dtos = items.Select(i => new
        {
            i.Id,
            InventoryId = i.InventoryId,
            InventoryName = i.Inventory?.Name,
            InventoryCode = i.Inventory?.InventoryCode,
            InventoryDate = i.Inventory?.StartDate,
            InventoryStatus = i.Inventory?.Status,
            InventoryStatusName = GetInventoryStatusName(i.Inventory?.Status ?? 0),
            i.IsChecked,
            i.CheckedAt,
            CheckedByName = i.CheckedBy?.FullName,
            ExpectedQuantity = i.ExpectedQuantity,
            i.ActualQuantity,
            Diff = i.ActualQuantity.HasValue ? i.ActualQuantity.Value - i.ExpectedQuantity : (int?)null,
            i.Condition,
            ConditionName = GetConditionName(i.Condition),
            i.HasIssue,
            i.IssueDescription,
            i.Notes,
        }).ToList();

        return Ok(AppResponse<object>.Success(dtos));
    }
    #endregion

    #region Asset Inventory
    [HttpGet("inventories")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetInventories([FromQuery] int? status)
    {
        var q = _context.AssetInventories
            .Where(i => i.StoreId == RequiredStoreId && i.IsActive)
            .Include(i => i.ResponsibleUser)
            .Include(i => i.Items)
            .OrderByDescending(i => i.StartDate)
            .AsQueryable();

        if (status.HasValue)
            q = q.Where(i => i.Status == status.Value);

        var inventories = await q.ToListAsync();

        var dtos = inventories.Select(i => new AssetInventoryDto
        {
            Id = i.Id,
            InventoryCode = i.InventoryCode,
            Name = i.Name,
            Description = i.Description,
            StartDate = i.StartDate,
            EndDate = i.EndDate,
            Status = i.Status,
            StatusName = GetInventoryStatusName(i.Status),
            ResponsibleUserId = i.ResponsibleUserId?.ToString(),
            ResponsibleUserName = i.ResponsibleUser != null ? $"{i.ResponsibleUser.FirstName} {i.ResponsibleUser.LastName}" : null,
            Notes = i.Notes,
            TotalAssets = i.Items.Count,
            CheckedCount = i.Items.Count(x => x.IsChecked),
            IssueCount = i.Items.Count(x => x.HasIssue),
            ProgressPercent = i.Items.Count > 0 ? Math.Round(i.Items.Count(x => x.IsChecked) * 100.0 / i.Items.Count, 1) : 0,
            CreatedAt = i.CreatedAt
        }).ToList();

        return Ok(AppResponse<List<AssetInventoryDto>>.Success(dtos));
    }

    [HttpGet("inventories/{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetInventory(Guid id)
    {
        var inventory = await _context.AssetInventories
            .Where(i => i.Id == id && i.StoreId == RequiredStoreId)
            .Include(i => i.ResponsibleUser)
            .Include(i => i.Items)
                .ThenInclude(item => item.Asset)
            .Include(i => i.Items)
                .ThenInclude(item => item.CheckedBy)
            .FirstOrDefaultAsync();

        if (inventory == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y Ä‘á»£t kiá»ƒm kÃª"));

        var dto = new AssetInventoryDetailDto
        {
            Id = inventory.Id,
            InventoryCode = inventory.InventoryCode,
            Name = inventory.Name,
            Description = inventory.Description,
            StartDate = inventory.StartDate,
            EndDate = inventory.EndDate,
            Status = inventory.Status,
            StatusName = GetInventoryStatusName(inventory.Status),
            ResponsibleUserId = inventory.ResponsibleUserId?.ToString(),
            ResponsibleUserName = inventory.ResponsibleUser != null ? $"{inventory.ResponsibleUser.FirstName} {inventory.ResponsibleUser.LastName}" : null,
            Notes = inventory.Notes,
            TotalAssets = inventory.Items.Count,
            CheckedCount = inventory.Items.Count(x => x.IsChecked),
            IssueCount = inventory.Items.Count(x => x.HasIssue),
            ProgressPercent = inventory.Items.Count > 0 ? Math.Round(inventory.Items.Count(x => x.IsChecked) * 100.0 / inventory.Items.Count, 1) : 0,
            CreatedAt = inventory.CreatedAt,
            Items = inventory.Items.Select(item => new AssetInventoryItemDto
            {
                Id = item.Id,
                InventoryId = item.InventoryId,
                AssetId = item.AssetId,
                AssetCode = item.Asset?.AssetCode,
                AssetName = item.Asset?.Name,
                IsChecked = item.IsChecked,
                CheckedAt = item.CheckedAt,
                CheckedById = item.CheckedById?.ToString(),
                CheckedByName = item.CheckedBy?.FullName,
                Condition = item.Condition,
                ConditionName = GetConditionName(item.Condition),
                ExpectedQuantity = item.ExpectedQuantity,
                ActualQuantity = item.ActualQuantity,
                QuantityMismatch = item.ActualQuantity.HasValue && item.ActualQuantity.Value != item.ExpectedQuantity,
                ActualLocation = item.ActualLocation,
                HasIssue = item.HasIssue,
                IssueDescription = item.IssueDescription,
                Notes = item.Notes
            }).ToList()
        };

        return Ok(AppResponse<AssetInventoryDetailDto>.Success(dto));
    }

    [HttpPost("inventories")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> CreateInventory([FromBody] CreateAssetInventoryDto request)
    {
        var responsibleId = !string.IsNullOrEmpty(request.ResponsibleUserId) && Guid.TryParse(request.ResponsibleUserId, out var rGuid) 
            ? (Guid?)rGuid 
            : CurrentUserId;
        
        var inventory = new AssetInventory
        {
            Id = Guid.NewGuid(),
            InventoryCode = GenerateInventoryCode(),
            Name = request.Name,
            Description = request.Description,
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            Status = 0,
            ResponsibleUserId = responsibleId,
            Notes = request.Notes,
            StoreId = RequiredStoreId,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserId.ToString()
        };

        // Add items: prefer Items[] with expected qty, fallback to AssetIds, fallback to all assets
        if (request.Items != null && request.Items.Any())
        {
            foreach (var itemInput in request.Items)
            {
                var invItem = new AssetInventoryItem
                {
                    Id = Guid.NewGuid(),
                    InventoryId = inventory.Id,
                    AssetId = itemInput.AssetId,
                    StoredExpectedQuantity = itemInput.ExpectedQuantity,
                    IsChecked = false,
                    CreatedAt = DateTime.UtcNow
                };
                if (itemInput.ActualQuantity.HasValue)
                {
                    invItem.IsChecked = true;
                    invItem.CheckedAt = DateTime.UtcNow;
                    invItem.CheckedById = CurrentUserId;
                    invItem.ActualQuantity = itemInput.ActualQuantity.Value;
                    invItem.HasIssue = itemInput.ActualQuantity.Value < itemInput.ExpectedQuantity;
                    invItem.Notes = itemInput.Notes;
                }
                inventory.Items.Add(invItem);
            }
        }
        else
        {
            var assetIds = request.AssetIds != null && request.AssetIds.Any()
                ? request.AssetIds
                : await _context.Assets.Where(a => a.StoreId == RequiredStoreId && a.IsActive).Select(a => a.Id).ToListAsync();

            // Lookup quantities for all assets
            var assetQtys = await _context.Assets.Where(a => assetIds.Contains(a.Id)).Select(a => new { a.Id, a.Quantity }).ToDictionaryAsync(a => a.Id, a => a.Quantity);

            foreach (var assetId in assetIds)
            {
                inventory.Items.Add(new AssetInventoryItem
                {
                    Id = Guid.NewGuid(),
                    InventoryId = inventory.Id,
                    AssetId = assetId,
                    StoredExpectedQuantity = assetQtys.GetValueOrDefault(assetId, 0),
                    IsChecked = false,
                    CreatedAt = DateTime.UtcNow
                });
            }
        }

        _context.AssetInventories.Add(inventory);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { id = inventory.Id, code = inventory.InventoryCode }));
    }

    [HttpPost("inventories/items/check")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> CheckInventoryItem([FromBody] CheckInventoryItemDto request)
    {
        var item = await _context.AssetInventoryItems
            .AsTracking()
            .Include(i => i.Inventory)
            .FirstOrDefaultAsync(i => i.Id == request.InventoryItemId && i.Inventory!.StoreId == RequiredStoreId);

        if (item == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y má»¥c kiá»ƒm kÃª"));

        if (item.Inventory!.Status != 0)
            return BadRequest(AppResponse<object>.Error("Äá»£t kiá»ƒm kÃª Ä‘Ã£ káº¿t thÃºc"));

        item.IsChecked = true;
        item.CheckedAt = DateTime.UtcNow;
        item.CheckedById = CurrentUserId;
        item.Condition = request.Condition;
        item.ActualQuantity = request.ActualQuantity;
        item.ActualLocation = request.ActualLocation;
        item.HasIssue = request.HasIssue;
        item.IssueDescription = request.IssueDescription;
        item.Notes = request.Notes;

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Cáº­p nháº­t kiá»ƒm kÃª thÃ nh cÃ´ng"));
    }

    [HttpPatch("inventories/{id}/complete")]
    [RequireModulePermission("Asset", ModulePermissionAction.Edit)]
    public async Task<IActionResult> CompleteInventory(Guid id)
    {
        var inventory = await _context.AssetInventories
            .AsTracking()
            .Include(i => i.Items)
            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == RequiredStoreId);
        if (inventory == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y Ä‘á»£t kiá»ƒm kÃª"));

        if (inventory.Status != 0)
            return BadRequest(AppResponse<object>.Error("Äá»£t kiá»ƒm kÃª khÃ´ng á»Ÿ tráº¡ng thÃ¡i Ä‘ang tiáº¿n hÃ nh"));

        // Auto-adjust stock for items with quantity mismatch
        var checkedItems = inventory.Items.Where(i => i.IsChecked && i.ActualQuantity.HasValue).ToList();
        var assetIds = checkedItems.Select(i => i.AssetId).ToList();
        var assets = await _context.Assets.AsTracking().Where(a => assetIds.Contains(a.Id)).ToDictionaryAsync(a => a.Id);
        
        int adjustedCount = 0;
        foreach (var item in checkedItems)
        {
            if (!assets.TryGetValue(item.AssetId, out var asset)) continue;
            var diff = item.ActualQuantity!.Value - item.ExpectedQuantity;
            if (diff == 0) continue;

            asset.Quantity = item.ActualQuantity.Value;
            adjustedCount++;

            _context.StockTransactions.Add(new StockTransaction
            {
                Id = Guid.NewGuid(),
                AssetId = asset.Id,
                TransactionType = StockTransactionType.Adjustment,
                Quantity = diff,
                BalanceAfter = asset.Quantity,
                Reason = $"Äiá»u chá»‰nh tá»« kiá»ƒm kÃª {inventory.InventoryCode}",
                ReferenceCode = $"DC-{inventory.InventoryCode}",
                RelatedInventoryId = inventory.Id,
                PerformedById = CurrentUserId,
                Notes = $"Tá»“n kho: {item.ExpectedQuantity} â†’ Thá»±c táº¿: {item.ActualQuantity.Value} (chÃªnh lá»‡ch: {(diff > 0 ? "+" : "")}{diff})",
                StoreId = RequiredStoreId,
                TransactionDate = DateTime.UtcNow
            });
        }

        inventory.Status = 1;
        inventory.EndDate = DateTime.UtcNow;
        inventory.UpdatedAt = DateTime.UtcNow;
        inventory.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { message = "HoÃ n thÃ nh kiá»ƒm kÃª", adjustedItems = adjustedCount }));
    }

    [HttpPatch("inventories/{id}/cancel")]
    [RequireModulePermission("Asset", ModulePermissionAction.Edit)]
    public async Task<IActionResult> CancelInventory(Guid id)
    {
        var inventory = await _context.AssetInventories.AsTracking().FirstOrDefaultAsync(i => i.Id == id && i.StoreId == RequiredStoreId);
        if (inventory == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y Ä‘á»£t kiá»ƒm kÃª"));

        if (inventory.Status == 1)
            return BadRequest(AppResponse<object>.Error("KhÃ´ng thá»ƒ há»§y Ä‘á»£t kiá»ƒm kÃª Ä‘Ã£ hoÃ n thÃ nh"));

        inventory.Status = 2;
        inventory.EndDate = DateTime.UtcNow;
        inventory.UpdatedAt = DateTime.UtcNow;
        inventory.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("ÄÃ£ há»§y Ä‘á»£t kiá»ƒm kÃª"));
    }

    [HttpDelete("inventories/{id}")]
    [RequireModulePermission("Asset", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteInventory(Guid id)
    {
        var inventory = await _context.AssetInventories
            .AsTracking()
            .Include(i => i.Items)
            .FirstOrDefaultAsync(i => i.Id == id && i.StoreId == RequiredStoreId);
        if (inventory == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y Ä‘á»£t kiá»ƒm kÃª"));

        _context.AssetInventoryItems.RemoveRange(inventory.Items);
        _context.AssetInventories.Remove(inventory);
        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("ÄÃ£ xÃ³a Ä‘á»£t kiá»ƒm kÃª"));
    }
    #endregion

    #region Stock Transactions
    
    private string GetTransactionTypeName(StockTransactionType type) => type switch
    {
        StockTransactionType.StockIn => "Nháº­p kho",
        StockTransactionType.StockOut => "Xuáº¥t kho",
        StockTransactionType.Adjustment => "Äiá»u chá»‰nh",
        _ => "KhÃ¡c"
    };

    private string GenerateTransactionCode(StockTransactionType type)
    {
        var prefix = type switch
        {
            StockTransactionType.StockIn => "NK",
            StockTransactionType.StockOut => "XK",
            StockTransactionType.Adjustment => "DC",
            _ => "GD"
        };
        return $"{prefix}-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString()[..4].ToUpper()}";
    }

    [HttpPost("stock/in")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> StockIn([FromBody] CreateStockTransactionDto request)
    {
        if (request.Quantity <= 0)
            return BadRequest(AppResponse<object>.Error("Sá»‘ lÆ°á»£ng pháº£i lá»›n hÆ¡n 0"));

        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId && a.IsActive);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y sáº£n pháº©m"));

        asset.Quantity += request.Quantity;

        var transaction = new StockTransaction
        {
            Id = Guid.NewGuid(),
            AssetId = asset.Id,
            TransactionType = StockTransactionType.StockIn,
            Quantity = request.Quantity,
            BalanceAfter = asset.Quantity,
            Reason = request.Reason,
            ReferenceCode = request.ReferenceCode ?? GenerateTransactionCode(StockTransactionType.StockIn),
            PerformedById = CurrentUserId,
            Notes = request.Notes,
            StoreId = RequiredStoreId,
            TransactionDate = DateTime.UtcNow
        };

        _context.StockTransactions.Add(transaction);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { 
            transactionId = transaction.Id, 
            referenceCode = transaction.ReferenceCode,
            newBalance = asset.Quantity 
        }));
    }

    [HttpPost("stock/out")]
    [RequireModulePermission("Asset", ModulePermissionAction.Create)]
    public async Task<IActionResult> StockOut([FromBody] CreateStockTransactionDto request)
    {
        if (request.Quantity <= 0)
            return BadRequest(AppResponse<object>.Error("Sá»‘ lÆ°á»£ng pháº£i lá»›n hÆ¡n 0"));

        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId && a.IsActive);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("KhÃ´ng tÃ¬m tháº¥y sáº£n pháº©m"));

        if (asset.Quantity < request.Quantity)
            return BadRequest(AppResponse<object>.Error($"Tá»“n kho khÃ´ng Ä‘á»§. Hiá»‡n cÃ³: {asset.Quantity}, yÃªu cáº§u: {request.Quantity}"));

        asset.Quantity -= request.Quantity;

        var transaction = new StockTransaction
        {
            Id = Guid.NewGuid(),
            AssetId = asset.Id,
            TransactionType = StockTransactionType.StockOut,
            Quantity = -request.Quantity,
            BalanceAfter = asset.Quantity,
            Reason = request.Reason,
            ReferenceCode = request.ReferenceCode ?? GenerateTransactionCode(StockTransactionType.StockOut),
            PerformedById = CurrentUserId,
            Notes = request.Notes,
            StoreId = RequiredStoreId,
            TransactionDate = DateTime.UtcNow
        };

        _context.StockTransactions.Add(transaction);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { 
            transactionId = transaction.Id,
            referenceCode = transaction.ReferenceCode,
            newBalance = asset.Quantity 
        }));
    }

    [HttpGet("stock/transactions")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetStockTransactions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] Guid? assetId = null,
        [FromQuery] int? transactionType = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] string? search = null)
    {
        var query = _context.StockTransactions
            .Where(t => t.StoreId == RequiredStoreId)
            .Include(t => t.Asset)
            .Include(t => t.PerformedBy)
            .AsQueryable();

        if (assetId.HasValue)
            query = query.Where(t => t.AssetId == assetId.Value);
        if (transactionType.HasValue)
            query = query.Where(t => (int)t.TransactionType == transactionType.Value);
        if (fromDate.HasValue)
            query = query.Where(t => t.TransactionDate >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(t => t.TransactionDate <= toDate.Value);
        if (!string.IsNullOrEmpty(search))
            query = query.Where(t => t.Asset!.Name.Contains(search) || t.Asset.AssetCode.Contains(search) || (t.ReferenceCode != null && t.ReferenceCode.Contains(search)));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(t => t.TransactionDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new StockTransactionDto
            {
                Id = t.Id,
                AssetId = t.AssetId,
                AssetCode = t.Asset!.AssetCode,
                AssetName = t.Asset.Name,
                TransactionType = (int)t.TransactionType,
                TransactionTypeName = t.TransactionType == StockTransactionType.StockIn ? "Nháº­p kho" : t.TransactionType == StockTransactionType.StockOut ? "Xuáº¥t kho" : "Äiá»u chá»‰nh",
                Quantity = t.Quantity,
                BalanceAfter = t.BalanceAfter,
                Reason = t.Reason,
                ReferenceCode = t.ReferenceCode,
                RelatedInventoryId = t.RelatedInventoryId,
                PerformedById = t.PerformedById.HasValue ? t.PerformedById.Value.ToString() : null,
                PerformedByName = t.PerformedBy != null ? t.PerformedBy.FullName : null,
                Notes = t.Notes,
                TransactionDate = t.TransactionDate
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    [HttpGet("stock/summary")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetStockSummary()
    {
        var assets = await _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.IsActive)
            .ToListAsync();

        var transactions = await _context.StockTransactions
            .Where(t => t.StoreId == RequiredStoreId)
            .ToListAsync();

        var summary = new StockSummaryDto
        {
            TotalProducts = assets.Count,
            TotalStockQuantity = assets.Sum(a => a.Quantity),
            TotalStockIn = transactions.Where(t => t.TransactionType == StockTransactionType.StockIn).Sum(t => t.Quantity),
            TotalStockOut = transactions.Where(t => t.TransactionType == StockTransactionType.StockOut).Sum(t => Math.Abs(t.Quantity)),
            TotalAdjustments = transactions.Count(t => t.TransactionType == StockTransactionType.Adjustment),
            TotalStockValue = assets.Sum(a => a.PurchasePrice * a.Quantity),
            LowStockItems = assets.Where(a => a.Quantity <= 5).OrderBy(a => a.Quantity).Take(10).Select(a => new LowStockItemDto
            {
                AssetId = a.Id,
                AssetCode = a.AssetCode,
                AssetName = a.Name,
                Quantity = a.Quantity,
                Unit = a.Unit
            }).ToList()
        };

        return Ok(AppResponse<StockSummaryDto>.Success(summary));
    }

    #endregion

    #region Statistics
    [HttpGet("statistics")]
    [RequireModulePermission("Asset", ModulePermissionAction.View)]
    public async Task<IActionResult> GetStatistics()
    {
        var assets = await _context.Assets
            .Where(a => a.StoreId == RequiredStoreId && a.IsActive)
            .Include(a => a.Category)
            .Include(a => a.CurrentAssignee)
            .ToListAsync();

        var now = DateTime.UtcNow;
        var warningDate = now.AddDays(30);

        var stats = new AssetStatisticsDto
        {
            TotalAssets = assets.Count,
            ActiveAssets = assets.Count(a => a.Status == AssetStatus.Active),
            InStockAssets = assets.Count(a => a.Status == AssetStatus.InStock),
            AssignedAssets = assets.Count(a => a.CurrentAssigneeId != null),
            MaintenanceAssets = assets.Count(a => a.Status == AssetStatus.InMaintenance),
            BrokenAssets = assets.Count(a => a.Status == AssetStatus.Broken),
            DisposedAssets = assets.Count(a => a.Status == AssetStatus.Disposed),
            TotalPurchaseValue = assets.Sum(a => a.PurchasePrice * a.Quantity),
            TotalCurrentValue = assets.Sum(a => (a.CurrentValue ?? a.PurchasePrice) * a.Quantity),
            WarrantyExpiringSoon = assets.Count(a => a.WarrantyExpiry.HasValue && a.WarrantyExpiry.Value <= warningDate && a.WarrantyExpiry.Value > now),
            ByType = assets.GroupBy(a => a.AssetType).Select(g => new AssetByTypeDto
            {
                AssetType = g.Key,
                AssetTypeName = GetAssetTypeName(g.Key),
                Count = g.Count(),
                TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
            }).OrderByDescending(x => x.Count).ToList(),
            ByCategory = assets.Where(a => a.CategoryId != null).GroupBy(a => new { a.CategoryId, a.Category!.Name }).Select(g => new AssetByCategoryDto
            {
                CategoryId = g.Key.CategoryId,
                CategoryName = g.Key.Name,
                Count = g.Count(),
                TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
            }).OrderByDescending(x => x.Count).ToList(),
            ByAssignee = assets.Where(a => a.CurrentAssigneeId != null).GroupBy(a => new { a.CurrentAssigneeId, a.CurrentAssignee!.FirstName, a.CurrentAssignee.LastName }).Select(g => new AssetByAssigneeDto
            {
                AssigneeId = g.Key.CurrentAssigneeId?.ToString(),
                AssigneeName = $"{g.Key.FirstName} {g.Key.LastName}",
                Count = g.Count(),
                TotalValue = g.Sum(a => a.PurchasePrice * a.Quantity)
            }).OrderByDescending(x => x.Count).ToList(),
            ByStatus = assets.GroupBy(a => a.Status).Select(g => new AssetByStatusDto
            {
                Status = g.Key,
                StatusName = GetAssetStatusName(g.Key),
                Count = g.Count()
            }).ToList()
        };

        return Ok(AppResponse<AssetStatisticsDto>.Success(stats));
    }
    #endregion
}







