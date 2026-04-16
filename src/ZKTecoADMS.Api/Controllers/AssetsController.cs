using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
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
        AssetType.Electronics => "Thiết bị điện tử",
        AssetType.Furniture => "Nội thất",
        AssetType.Vehicle => "Phương tiện",
        AssetType.Tool => "Công cụ dụng cụ",
        AssetType.Machinery => "Máy móc",
        AssetType.Software => "Phần mềm",
        _ => "Khác"
    };

    private static string GetAssetStatusName(AssetStatus status) => status switch
    {
        AssetStatus.Active => "Đang sử dụng",
        AssetStatus.InMaintenance => "Đang bảo trì",
        AssetStatus.Broken => "Hỏng",
        AssetStatus.Disposed => "Đã thanh lý",
        AssetStatus.Lost => "Đã mất",
        AssetStatus.InStock => "Trong kho",
        _ => "Không xác định"
    };

    private static string GetTransferTypeName(AssetTransferType type) => type switch
    {
        AssetTransferType.Assignment => "Cấp mới",
        AssetTransferType.Transfer => "Chuyển giao",
        AssetTransferType.Return => "Thu hồi",
        AssetTransferType.Maintenance => "Bảo trì",
        AssetTransferType.Disposal => "Thanh lý",
        _ => "Khác"
    };

    private static string GetConditionName(InventoryCondition? condition) => condition switch
    {
        InventoryCondition.Good => "Tốt",
        InventoryCondition.Fair => "Bình thường",
        InventoryCondition.Poor => "Kém",
        InventoryCondition.Damaged => "Hỏng",
        InventoryCondition.NotFound => "Không tìm thấy",
        _ => "Chưa kiểm"
    };

    private static string GetInventoryStatusName(int status) => status switch
    {
        0 => "Đang tiến hành",
        1 => "Hoàn thành",
        2 => "Đã hủy",
        _ => "Không xác định"
    };
    #endregion

    #region Asset Categories
    [HttpGet("categories")]
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
    public async Task<IActionResult> UpdateCategory(Guid id, [FromBody] UpdateAssetCategoryDto request)
    {
        var category = await _context.AssetCategories
            .AsTracking()
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

        if (category == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy danh mục"));

        category.Name = request.Name;
        category.Description = request.Description;
        category.ParentCategoryId = request.ParentCategoryId;
        category.IsActive = request.IsActive;
        category.UpdatedAt = DateTime.UtcNow;
        category.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Cập nhật danh mục thành công"));
    }

    [HttpDelete("categories/{id}")]
    public async Task<IActionResult> DeleteCategory(Guid id)
    {
        var category = await _context.AssetCategories
            .Include(c => c.Assets)
            .Include(c => c.SubCategories)
            .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

        if (category == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy danh mục"));

        if (category.Assets.Any())
            return BadRequest(AppResponse<object>.Error("Không thể xóa danh mục đang có tài sản"));

        if (category.SubCategories.Any())
            return BadRequest(AppResponse<object>.Error("Không thể xóa danh mục đang có danh mục con"));

        _context.AssetCategories.Remove(category);
        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Xóa danh mục thành công"));
    }
    #endregion

    #region Assets CRUD
    [HttpGet]
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
            Name = a.Name,
            Description = a.Description,
            SerialNumber = a.SerialNumber,
            Model = a.Model,
            Brand = a.Brand,
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
            CurrentAssigneeName = a.CurrentAssignee?.FullName,
            AssignedDate = a.AssignedDate,
            IsActive = a.IsActive,
            CreatedAt = a.CreatedAt,
            PrimaryImageUrl = a.Images.FirstOrDefault(i => i.IsPrimary)?.ImageUrl
        }).ToList();

        return Ok(AppResponse<object>.Success(new { items = dtos, totalCount = total, page = query.Page, pageSize = query.PageSize }));
    }

    [HttpGet("{id}")]
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
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        var dto = new AssetDetailDto
        {
            Id = asset.Id,
            AssetCode = asset.AssetCode,
            Name = asset.Name,
            Description = asset.Description,
            SerialNumber = asset.SerialNumber,
            Model = asset.Model,
            Brand = asset.Brand,
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
            CurrentAssigneeName = asset.CurrentAssignee?.FullName,
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
                FromUserName = t.FromUser?.FullName,
                ToUserId = t.ToUserId?.ToString(),
                ToUserName = t.ToUser?.FullName,
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

        _context.Assets.Add(asset);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<AssetDto>.Success(new AssetDto
        {
            Id = asset.Id,
            AssetCode = asset.AssetCode,
            Name = asset.Name,
            AssetType = asset.AssetType,
            AssetTypeName = GetAssetTypeName(asset.AssetType),
            Status = asset.Status,
            StatusName = GetAssetStatusName(asset.Status),
            CreatedAt = asset.CreatedAt
        }));
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> UpdateAsset(Guid id, [FromBody] UpdateAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == id && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        asset.Name = request.Name;
        asset.Description = request.Description;
        asset.SerialNumber = request.SerialNumber;
        asset.Model = request.Model;
        asset.Brand = request.Brand;
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
        return Ok(AppResponse<string>.Success("Cập nhật tài sản thành công"));
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteAsset(Guid id)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == id && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        asset.IsActive = false;
        asset.UpdatedAt = DateTime.UtcNow;
        asset.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Xóa tài sản thành công"));
    }
    #endregion

    #region Asset Images
    [HttpPost("{assetId}/images")]
    public async Task<IActionResult> AddImage(Guid assetId, [FromBody] AddAssetImageDto request)
    {
        var asset = await _context.Assets.AsTracking().Include(a => a.Images).FirstOrDefaultAsync(a => a.Id == assetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

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
    public async Task<IActionResult> DeleteImage(Guid assetId, Guid imageId)
    {
        var image = await _context.AssetImages.FirstOrDefaultAsync(i => i.Id == imageId && i.AssetId == assetId);
        if (image == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy hình ảnh"));

        _context.AssetImages.Remove(image);
        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Xóa hình ảnh thành công"));
    }

    [HttpPatch("{assetId}/images/{imageId}/primary")]
    public async Task<IActionResult> SetPrimaryImage(Guid assetId, Guid imageId)
    {
        var images = await _context.AssetImages.AsTracking().Where(i => i.AssetId == assetId).ToListAsync();
        foreach (var img in images)
            img.IsPrimary = img.Id == imageId;

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Đặt hình chính thành công"));
    }
    #endregion

    #region Asset Transfer & Assignment
    [HttpPost("assign")]
    public async Task<IActionResult> AssignAsset([FromBody] AssignAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        if (asset.CurrentAssigneeId != null)
            return BadRequest(AppResponse<object>.Error("Tài sản đã được cấp cho người khác. Vui lòng thu hồi trước."));

        if (request.Quantity > asset.Quantity)
            return BadRequest(AppResponse<object>.Error("Số lượng cấp vượt quá số lượng có"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Assignment,
            ToUserId = Guid.TryParse(request.ToUserId, out var toGuid) ? toGuid : null,
            Quantity = request.Quantity,
            TransferDate = DateTime.UtcNow,
            Reason = request.Reason,
            Notes = request.Notes,
            PerformedById = CurrentUserId,
            IsConfirmed = false,
            CreatedAt = DateTime.UtcNow
        };

        asset.CurrentAssigneeId = Guid.TryParse(request.ToUserId, out var toUserGuid) ? toUserGuid : null;
        asset.AssignedDate = DateTime.UtcNow;
        asset.Status = AssetStatus.Active;

        _context.AssetTransfers.Add(transfer);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<string>.Success("Cấp tài sản thành công"));
    }

    [HttpPost("transfer")]
    public async Task<IActionResult> TransferAsset([FromBody] TransferAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        if (asset.CurrentAssigneeId?.ToString() != request.FromUserId)
            return BadRequest(AppResponse<object>.Error("Tài sản không thuộc người chuyển giao"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Transfer,
            FromUserId = Guid.TryParse(request.FromUserId, out var fromGuid) ? fromGuid : null,
            ToUserId = Guid.TryParse(request.ToUserId, out var toGuid) ? toGuid : null,
            Quantity = request.Quantity,
            TransferDate = DateTime.UtcNow,
            Reason = request.Reason,
            Notes = request.Notes,
            PerformedById = CurrentUserId,
            IsConfirmed = false,
            CreatedAt = DateTime.UtcNow
        };

        asset.CurrentAssigneeId = Guid.TryParse(request.ToUserId, out var toTransferGuid) ? toTransferGuid : null;
        asset.AssignedDate = DateTime.UtcNow;

        _context.AssetTransfers.Add(transfer);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<string>.Success("Chuyển giao tài sản thành công"));
    }

    [HttpPost("return")]
    public async Task<IActionResult> ReturnAsset([FromBody] ReturnAssetDto request)
    {
        var asset = await _context.Assets.AsTracking().FirstOrDefaultAsync(a => a.Id == request.AssetId && a.StoreId == RequiredStoreId);
        if (asset == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy tài sản"));

        if (asset.CurrentAssigneeId?.ToString() != request.FromUserId)
            return BadRequest(AppResponse<object>.Error("Tài sản không thuộc người này"));

        var transfer = new AssetTransfer
        {
            Id = Guid.NewGuid(),
            AssetId = request.AssetId,
            TransferType = AssetTransferType.Return,
            FromUserId = Guid.TryParse(request.FromUserId, out var fromGuid) ? fromGuid : null,
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

        return Ok(AppResponse<string>.Success("Thu hồi tài sản thành công"));
    }

    [HttpPost("transfers/{transferId}/confirm")]
    public async Task<IActionResult> ConfirmTransfer(Guid transferId, [FromBody] ConfirmTransferDto request)
    {
        var transfer = await _context.AssetTransfers
            .AsTracking()
            .Include(t => t.Asset)
            .FirstOrDefaultAsync(t => t.Id == transferId && t.Asset!.StoreId == RequiredStoreId);

        if (transfer == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy chuyển giao"));

        if (transfer.ToUserId != CurrentUserId)
            return BadRequest(AppResponse<object>.Error("Bạn không phải người nhận tài sản này"));

        transfer.IsConfirmed = true;
        transfer.ConfirmedAt = DateTime.UtcNow;
        transfer.Notes = transfer.Notes != null ? $"{transfer.Notes}\n{request.Notes}" : request.Notes;

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Xác nhận nhận tài sản thành công"));
    }

    [HttpGet("transfers")]
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
            FromUserName = t.FromUser?.FullName,
            ToUserId = t.ToUserId?.ToString(),
            ToUserName = t.ToUser?.FullName,
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

    #region Asset Inventory
    [HttpGet("inventories")]
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
            ResponsibleUserName = i.ResponsibleUser?.FullName,
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
            return NotFound(AppResponse<object>.Error("Không tìm thấy đợt kiểm kê"));

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
            ResponsibleUserName = inventory.ResponsibleUser?.FullName,
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
                ExpectedQuantity = item.Asset?.Quantity ?? 0,
                ActualQuantity = item.ActualQuantity,
                QuantityMismatch = item.ActualQuantity.HasValue && item.ActualQuantity.Value != (item.Asset?.Quantity ?? 0),
                ActualLocation = item.ActualLocation,
                HasIssue = item.HasIssue,
                IssueDescription = item.IssueDescription,
                Notes = item.Notes
            }).ToList()
        };

        return Ok(AppResponse<AssetInventoryDetailDto>.Success(dto));
    }

    [HttpPost("inventories")]
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
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserId.ToString()
        };

        // Add items
        var assetIds = request.AssetIds != null && request.AssetIds.Any()
            ? request.AssetIds
            : await _context.Assets.Where(a => a.StoreId == RequiredStoreId && a.IsActive).Select(a => a.Id).ToListAsync();

        foreach (var assetId in assetIds)
        {
            inventory.Items.Add(new AssetInventoryItem
            {
                Id = Guid.NewGuid(),
                InventoryId = inventory.Id,
                AssetId = assetId,
                IsChecked = false,
                CreatedAt = DateTime.UtcNow
            });
        }

        _context.AssetInventories.Add(inventory);
        await _context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { id = inventory.Id, code = inventory.InventoryCode }));
    }

    [HttpPost("inventories/items/check")]
    public async Task<IActionResult> CheckInventoryItem([FromBody] CheckInventoryItemDto request)
    {
        var item = await _context.AssetInventoryItems
            .AsTracking()
            .Include(i => i.Inventory)
            .FirstOrDefaultAsync(i => i.Id == request.InventoryItemId && i.Inventory!.StoreId == RequiredStoreId);

        if (item == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy mục kiểm kê"));

        if (item.Inventory!.Status != 0)
            return BadRequest(AppResponse<object>.Error("Đợt kiểm kê đã kết thúc"));

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
        return Ok(AppResponse<string>.Success("Cập nhật kiểm kê thành công"));
    }

    [HttpPatch("inventories/{id}/complete")]
    public async Task<IActionResult> CompleteInventory(Guid id)
    {
        var inventory = await _context.AssetInventories.AsTracking().FirstOrDefaultAsync(i => i.Id == id && i.StoreId == RequiredStoreId);
        if (inventory == null)
            return NotFound(AppResponse<object>.Error("Không tìm thấy đợt kiểm kê"));

        inventory.Status = 1;
        inventory.EndDate = DateTime.UtcNow;
        inventory.UpdatedAt = DateTime.UtcNow;
        inventory.UpdatedBy = CurrentUserId.ToString();

        await _context.SaveChangesAsync();
        return Ok(AppResponse<string>.Success("Hoàn thành kiểm kê"));
    }
    #endregion

    #region Statistics
    [HttpGet("statistics")]
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
            ByAssignee = assets.Where(a => a.CurrentAssigneeId != null).GroupBy(a => new { a.CurrentAssigneeId, Name = a.CurrentAssignee!.FullName }).Select(g => new AssetByAssigneeDto
            {
                AssigneeId = g.Key.CurrentAssigneeId?.ToString(),
                AssigneeName = g.Key.Name ?? "Unknown",
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







