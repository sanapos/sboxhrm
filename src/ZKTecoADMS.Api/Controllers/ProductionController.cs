using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Api.Services.Production;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public partial class ProductionController(
    ZKTecoDbContext dbContext,
    IKpiGoogleSheetService kpiSheetService,
    ISystemNotificationService notificationService,
    ILogger<ProductionController> logger) : AuthenticatedControllerBase
{
    #region DTOs

    public record ProductGroupDto(Guid Id, string Name, string? Description, int SortOrder, int ProductCount);
    public record ProductGroupCreateDto(string Name, string? Description, int SortOrder);

    public record ProductItemDto(
        Guid Id, string Code, string Name, string? Unit, string? Description,
        int SortOrder, Guid ProductGroupId, string? ProductGroupName,
        List<ProductPriceTierDto> PriceTiers);
    public record ProductItemCreateDto(
        string Code, string Name, string? Unit, string? Description,
        int SortOrder, Guid ProductGroupId, List<ProductPriceTierCreateDto>? PriceTiers);

    public record ProductPriceTierDto(Guid Id, int MinQuantity, int? MaxQuantity, decimal UnitPrice, int TierLevel);
    public record ProductPriceTierCreateDto(int MinQuantity, int? MaxQuantity, decimal UnitPrice, int TierLevel);

    public record ProductionEntryDto(
        Guid Id, Guid EmployeeId, string? EmployeeName, string? EmployeeCode,
        Guid ProductItemId, string? ProductItemName, string? ProductGroupName,
        DateTime WorkDate, decimal Quantity, decimal? UnitPrice, decimal? Amount, string? Note);
    public record ProductionEntryCreateDto(
        Guid EmployeeId, Guid ProductItemId, DateTime WorkDate,
        decimal Quantity, string? Note);
    public record ProductionEntryBatchDto(List<ProductionEntryCreateDto> Entries);

    public record ProductionSummaryDto(
        string EmployeeId, string EmployeeName, string EmployeeCode,
        decimal TotalQuantity, decimal TotalAmount,
        List<ProductionSummaryItemDto> Items);
    public record ProductionSummaryItemDto(
        string ProductName, string? GroupName, decimal Quantity, decimal Amount);

    public record ProductionImportRowDto(string EmployeeCode, string ProductCode, decimal Quantity, string? Note, string? WorkDate);
    public record ProductionImportDto(DateTime WorkDate, List<ProductionImportRowDto> Rows);
    public record ProductionExportRowDto(
        string EmployeeName, string EmployeeCode, string ProductName, string? GroupName,
        DateTime WorkDate, decimal Quantity, decimal? UnitPrice, decimal? Amount, string? Note);
    public record ProductionGSheetSyncDto(string SpreadsheetUrl, string SheetName, DateTime WorkDate);
    public record GSheetTabSyncInfo(string SheetName, DateTime WorkDate);
    public record ProductionGSheetMultiSyncDto(string SpreadsheetUrl, List<GSheetTabSyncInfo> Tabs);

    #endregion

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• PRODUCT GROUPS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpGet("groups")]
    [RequireModulePermission("Production", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductGroupDto>>>> GetGroups()
    {
        var storeId = RequiredStoreId;
        var groups = await dbContext.ProductGroups
            .Where(g => g.StoreId == storeId && g.Deleted == null)
            .OrderBy(g => g.SortOrder).ThenBy(g => g.Name)
            .Select(g => new ProductGroupDto(
                g.Id, g.Name, g.Description, g.SortOrder,
                g.Products.Count(p => p.Deleted == null)))
            .ToListAsync();
        return Ok(AppResponse<List<ProductGroupDto>>.Success(groups));
    }

    [HttpPost("groups")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ProductGroupDto>>> CreateGroup([FromBody] ProductGroupCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var group = new ProductGroup
        {
            Name = dto.Name,
            Description = dto.Description,
            SortOrder = dto.SortOrder,
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString(),
        };
        dbContext.ProductGroups.Add(group);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ProductGroupDto>.Success(
            new ProductGroupDto(group.Id, group.Name, group.Description, group.SortOrder, 0)));
    }

    [HttpPut("groups/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ProductGroupDto>>> UpdateGroup(Guid id, [FromBody] ProductGroupCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var group = await dbContext.ProductGroups.AsTracking()
            .FirstOrDefaultAsync(g => g.Id == id && g.StoreId == storeId && g.Deleted == null);
        if (group == null) return NotFound(AppResponse<ProductGroupDto>.Fail("Không tìm thấy nhóm sản phẩm"));

        group.Name = dto.Name;
        group.Description = dto.Description;
        group.SortOrder = dto.SortOrder;
        group.UpdatedAt = DateTime.Now;
        group.UpdatedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        var count = await dbContext.ProductItems.CountAsync(p => p.ProductGroupId == id && p.Deleted == null);
        return Ok(AppResponse<ProductGroupDto>.Success(
            new ProductGroupDto(group.Id, group.Name, group.Description, group.SortOrder, count)));
    }

    [HttpDelete("groups/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteGroup(Guid id)
    {
        var storeId = RequiredStoreId;
        var group = await dbContext.ProductGroups.AsTracking()
            .FirstOrDefaultAsync(g => g.Id == id && g.StoreId == storeId && g.Deleted == null);
        if (group == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy nhóm sản phẩm"));

        group.Deleted = DateTime.Now;
        group.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• PRODUCT ITEMS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpGet("items")]
    [RequireModulePermission("Production", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductItemDto>>>> GetItems([FromQuery] Guid? groupId)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.ProductItems
            .Include(p => p.PriceTiers.Where(t => t.Deleted == null))
            .Include(p => p.ProductGroup)
            .Where(p => p.StoreId == storeId && p.Deleted == null);

        if (groupId.HasValue)
            query = query.Where(p => p.ProductGroupId == groupId.Value);

        var items = await query
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .Select(p => new ProductItemDto(
                p.Id, p.Code, p.Name, p.Unit, p.Description, p.SortOrder,
                p.ProductGroupId, p.ProductGroup.Name,
                p.PriceTiers.OrderBy(t => t.TierLevel).Select(t =>
                    new ProductPriceTierDto(t.Id, t.MinQuantity, t.MaxQuantity, t.UnitPrice, t.TierLevel)).ToList()))
            .ToListAsync();
        return Ok(AppResponse<List<ProductItemDto>>.Success(items));
    }

    [HttpPost("items")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ProductItemDto>>> CreateItem([FromBody] ProductItemCreateDto dto)
    {
        var storeId = RequiredStoreId;
        if (await ItemCodeTakenAsync(storeId, dto.Code, null))
            return BadRequest(AppResponse<ProductItemDto>.Fail($"Mã sản phẩm «{dto.Code}» đã tồn tại"));
        var item = new ProductItem
        {
            Code = dto.Code,
            Name = dto.Name,
            Unit = dto.Unit,
            Description = dto.Description,
            SortOrder = dto.SortOrder,
            ProductGroupId = dto.ProductGroupId,
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString(),
        };

        if (dto.PriceTiers != null)
        {
            var overlapError = ValidatePriceTiers(dto.PriceTiers);
            if (overlapError != null)
                return BadRequest(AppResponse<ProductItemDto>.Fail(overlapError));

            foreach (var tier in dto.PriceTiers)
            {
                item.PriceTiers.Add(new ProductPriceTier
                {
                    MinQuantity = tier.MinQuantity,
                    MaxQuantity = tier.MaxQuantity,
                    UnitPrice = tier.UnitPrice,
                    TierLevel = tier.TierLevel,
                    StoreId = storeId,
                    IsActive = true,
                    CreatedBy = CurrentUserId.ToString(),
                });
            }
        }

        dbContext.ProductItems.Add(item);
        await dbContext.SaveChangesAsync();

        var groupName = await dbContext.ProductGroups
            .Where(g => g.Id == dto.ProductGroupId).Select(g => g.Name).FirstOrDefaultAsync();

        return Ok(AppResponse<ProductItemDto>.Success(new ProductItemDto(
            item.Id, item.Code, item.Name, item.Unit, item.Description, item.SortOrder,
            item.ProductGroupId, groupName,
            item.PriceTiers.OrderBy(t => t.TierLevel).Select(t =>
                new ProductPriceTierDto(t.Id, t.MinQuantity, t.MaxQuantity, t.UnitPrice, t.TierLevel)).ToList())));
    }

    [HttpPut("items/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ProductItemDto>>> UpdateItem(Guid id, [FromBody] ProductItemCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var item = await dbContext.ProductItems.AsTracking()
            .Include(p => p.PriceTiers)
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (item == null) return NotFound(AppResponse<ProductItemDto>.Fail("Không tìm thấy sản phẩm"));
        if (await ItemCodeTakenAsync(storeId, dto.Code, id))
            return BadRequest(AppResponse<ProductItemDto>.Fail($"Mã sản phẩm «{dto.Code}» đã tồn tại"));

        item.Code = dto.Code;
        item.Name = dto.Name;
        item.Unit = dto.Unit;
        item.Description = dto.Description;
        item.SortOrder = dto.SortOrder;
        item.ProductGroupId = dto.ProductGroupId;
        item.UpdatedAt = DateTime.Now;
        item.UpdatedBy = CurrentUserId.ToString();

        // Replace price tiers
        dbContext.ProductPriceTiers.RemoveRange(item.PriceTiers);
        if (dto.PriceTiers != null)
        {
            var overlapError = ValidatePriceTiers(dto.PriceTiers);
            if (overlapError != null)
                return BadRequest(AppResponse<ProductItemDto>.Fail(overlapError));

            foreach (var tier in dto.PriceTiers)
            {
                item.PriceTiers.Add(new ProductPriceTier
                {
                    MinQuantity = tier.MinQuantity,
                    MaxQuantity = tier.MaxQuantity,
                    UnitPrice = tier.UnitPrice,
                    TierLevel = tier.TierLevel,
                    StoreId = storeId,
                    IsActive = true,
                    CreatedBy = CurrentUserId.ToString(),
                });
            }
        }

        await dbContext.SaveChangesAsync();

        var groupName = await dbContext.ProductGroups
            .Where(g => g.Id == item.ProductGroupId).Select(g => g.Name).FirstOrDefaultAsync();

        return Ok(AppResponse<ProductItemDto>.Success(new ProductItemDto(
            item.Id, item.Code, item.Name, item.Unit, item.Description, item.SortOrder,
            item.ProductGroupId, groupName,
            item.PriceTiers.OrderBy(t => t.TierLevel).Select(t =>
                new ProductPriceTierDto(t.Id, t.MinQuantity, t.MaxQuantity, t.UnitPrice, t.TierLevel)).ToList())));
    }

    [HttpDelete("items/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteItem(Guid id)
    {
        var storeId = RequiredStoreId;
        var item = await dbContext.ProductItems.AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (item == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy sản phẩm"));

        item.Deleted = DateTime.Now;
        item.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• PRODUCTION ENTRIES â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpGet("entries")]
    [RequireModulePermission("Production", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetEntries(
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
        [FromQuery] Guid? employeeId, [FromQuery] Guid? productGroupId,
        [FromQuery] Guid? productItemId, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.ProductionEntries
            .Include(e => e.Employee)
            .Include(e => e.ProductItem).ThenInclude(p => p.ProductGroup)
            .Where(e => e.StoreId == storeId && e.Deleted == null);

        if (IsEmployee && !IsManager)
        {
            if (!EmployeeId.HasValue)
                return Ok(AppResponse<object>.Success(new { items = Array.Empty<ProductionEntryDto>(), total = 0, page, pageSize }));
            employeeId = EmployeeId.Value;
        }

        if (fromDate.HasValue) query = query.Where(e => e.WorkDate >= fromDate.Value.Date);
        if (toDate.HasValue) query = query.Where(e => e.WorkDate < toDate.Value.Date.AddDays(1));
        if (employeeId.HasValue) query = query.Where(e => e.EmployeeId == employeeId.Value);
        if (productItemId.HasValue) query = query.Where(e => e.ProductItemId == productItemId.Value);
        if (productGroupId.HasValue) query = query.Where(e => e.ProductItem.ProductGroupId == productGroupId.Value);

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(e => e.WorkDate).ThenBy(e => e.Employee.LastName).ThenBy(e => e.Employee.FirstName)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(e => new ProductionEntryDto(
                e.Id, e.EmployeeId,
                (e.Employee.LastName + " " + e.Employee.FirstName).Trim(), e.Employee.EmployeeCode,
                e.ProductItemId, e.ProductItem.Name,
                e.ProductItem.ProductGroup.Name,
                e.WorkDate, e.Quantity, e.UnitPrice, e.Amount, e.Note))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    [HttpPost("entries")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ProductionEntryDto>>> CreateEntry([FromBody] ProductionEntryCreateDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.Quantity <= 0)
            return BadRequest(AppResponse<ProductionEntryDto>.Fail("Số lượng phải lớn hơn 0"));
        var lockErr = await LockErrorAsync(storeId, [(dto.EmployeeId, dto.WorkDate)]);
        if (lockErr != null) return BadRequest(AppResponse<ProductionEntryDto>.Fail(lockErr));

        var entry = new ProductionEntry
        {
            EmployeeId = dto.EmployeeId,
            ProductItemId = dto.ProductItemId,
            WorkDate = dto.WorkDate.Date,
            Quantity = dto.Quantity,
            Note = dto.Note,
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString(),
        };
        dbContext.ProductionEntries.Add(entry);
        await SaveAndRepriceAsync(storeId);

        // Reload with navigation properties
        await dbContext.Entry(entry).Reference(e => e.Employee).LoadAsync();
        await dbContext.Entry(entry).Reference(e => e.ProductItem).LoadAsync();
        await dbContext.Entry(entry.ProductItem).Reference(p => p.ProductGroup).LoadAsync();

        // Notification
        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: entry.Employee.ApplicationUserId,
                type: NotificationType.Info,
                title: "Sản lượng mới",
                message: $"Đã ghi nhận {entry.Quantity} {entry.ProductItem.Unit ?? "SP"} - {entry.ProductItem.Name} ngày {entry.WorkDate:dd/MM/yyyy}",
                relatedEntityId: entry.Id,
                relatedEntityType: "ProductionEntry",
                categoryCode: "production",
                storeId: storeId);
        }
        catch { }

        return Ok(AppResponse<ProductionEntryDto>.Success(new ProductionEntryDto(
            entry.Id, entry.EmployeeId, $"{entry.Employee.LastName} {entry.Employee.FirstName}".Trim(), entry.Employee.EmployeeCode,
            entry.ProductItemId, entry.ProductItem.Name, entry.ProductItem.ProductGroup.Name,
            entry.WorkDate, entry.Quantity, entry.UnitPrice, entry.Amount, entry.Note)));
    }

    [HttpPost("entries/batch")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateBatch([FromBody] ProductionEntryBatchDto dto)
    {
        var storeId = RequiredStoreId;
        var entries = new List<ProductionEntry>();
        int duplicateSkipped = 0;

        // Detect duplicates: same employee + product + workDate
        var seen = new HashSet<string>();
        var existingKeys = await dbContext.ProductionEntries
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && dto.Entries.Select(d => d.WorkDate.Date).Contains(e.WorkDate))
            .Select(e => e.EmployeeId + "|" + e.ProductItemId + "|" + e.WorkDate.Date)
            .ToListAsync();
        var existingSet = existingKeys.ToHashSet();
        var locked = await ProductionPricing.LockedEmployeeMonthsAsync(
            dbContext, storeId, dto.Entries.Select(e => (e.EmployeeId, e.WorkDate)));
        int lockedSkipped = 0;

        foreach (var item in dto.Entries)
        {
            var key = item.EmployeeId + "|" + item.ProductItemId + "|" + item.WorkDate.Date;
            if (existingSet.Contains(key) || !seen.Add(key))
            {
                duplicateSkipped++;
                continue;
            }
            if (item.Quantity <= 0) continue;
            if (locked.Contains(ProductionPricing.LockKey(item.EmployeeId, item.WorkDate)))
            {
                lockedSkipped++;
                continue;
            }

            entries.Add(new ProductionEntry
            {
                EmployeeId = item.EmployeeId,
                ProductItemId = item.ProductItemId,
                WorkDate = item.WorkDate.Date,
                Quantity = item.Quantity,
                Note = item.Note,
                StoreId = storeId,
                IsActive = true,
                CreatedBy = CurrentUserId.ToString(),
            });
        }

        dbContext.ProductionEntries.AddRange(entries);
        await SaveAndRepriceAsync(storeId);

        // Batch notification
        try
        {
            var empIds = entries.Select(e => e.EmployeeId).Distinct().ToList();
            var empUserIds = await dbContext.Employees
                .Where(e => empIds.Contains(e.Id) && e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToListAsync();
            if (empUserIds.Count > 0)
            {
                await notificationService.CreateAndSendToUsersAsync(
                    targetUserIds: empUserIds,
                    type: NotificationType.Info,
                    title: "Nhập sản lượng hàng loạt",
                    message: $"Đã ghi nhận {entries.Count} bản ghi sản lượng ngày {DateTime.Now:dd/MM/yyyy}",
                    categoryCode: "production",
                    storeId: storeId);
            }
        }
        catch { }

        return Ok(AppResponse<object>.Success(new { created = entries.Count, duplicateSkipped, lockedSkipped }));
    }

    [HttpPut("entries/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ProductionEntryDto>>> UpdateEntry(Guid id, [FromBody] ProductionEntryCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var entry = await dbContext.ProductionEntries.AsTracking()
            .Include(e => e.Employee)
            .Include(e => e.ProductItem).ThenInclude(p => p.ProductGroup)
            .FirstOrDefaultAsync(e => e.Id == id && e.StoreId == storeId && e.Deleted == null);
        if (entry == null) return NotFound(AppResponse<ProductionEntryDto>.Fail("Không tìm thấy bản ghi"));
        if (dto.Quantity <= 0)
            return BadRequest(AppResponse<ProductionEntryDto>.Fail("Số lượng phải lớn hơn 0"));
        var lockErr = await LockErrorAsync(storeId,
            [(entry.EmployeeId, entry.WorkDate), (dto.EmployeeId, dto.WorkDate)]);
        if (lockErr != null) return BadRequest(AppResponse<ProductionEntryDto>.Fail(lockErr));

        entry.EmployeeId = dto.EmployeeId;
        entry.ProductItemId = dto.ProductItemId;
        entry.WorkDate = dto.WorkDate.Date;
        entry.Quantity = dto.Quantity;
        entry.Note = dto.Note;
        entry.UpdatedAt = DateTime.Now;
        entry.UpdatedBy = CurrentUserId.ToString();

        await SaveAndRepriceAsync(storeId);

        // Reload navigation properties in case FKs changed
        await dbContext.Entry(entry).Reference(e => e.Employee).LoadAsync();
        await dbContext.Entry(entry).Reference(e => e.ProductItem).LoadAsync();
        await dbContext.Entry(entry.ProductItem).Reference(p => p.ProductGroup).LoadAsync();

        // Notification
        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: entry.Employee.ApplicationUserId,
                type: NotificationType.Info,
                title: "Cập nhật sản lượng",
                message: $"Sản lượng {entry.ProductItem.Name} ngày {entry.WorkDate:dd/MM/yyyy} đã cập nhật: {entry.Quantity} {entry.ProductItem.Unit ?? "SP"}",
                relatedEntityId: entry.Id,
                relatedEntityType: "ProductionEntry",
                categoryCode: "production",
                storeId: storeId);
        }
        catch { }

        return Ok(AppResponse<ProductionEntryDto>.Success(new ProductionEntryDto(
            entry.Id, entry.EmployeeId, $"{entry.Employee.LastName} {entry.Employee.FirstName}".Trim(), entry.Employee.EmployeeCode,
            entry.ProductItemId, entry.ProductItem.Name, entry.ProductItem.ProductGroup.Name,
            entry.WorkDate, entry.Quantity, entry.UnitPrice, entry.Amount, entry.Note)));
    }

    [HttpDelete("entries/{id}")]
    [RequireModulePermission("Production", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteEntry(Guid id)
    {
        var storeId = RequiredStoreId;
        var entry = await dbContext.ProductionEntries.AsTracking()
            .Include(e => e.Employee)
            .Include(e => e.ProductItem)
            .FirstOrDefaultAsync(e => e.Id == id && e.StoreId == storeId && e.Deleted == null);
        if (entry == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy bản ghi"));
        var lockErr = await LockErrorAsync(storeId, [(entry.EmployeeId, entry.WorkDate)]);
        if (lockErr != null) return BadRequest(AppResponse<bool>.Fail(lockErr));

        var empUserId = entry.Employee?.ApplicationUserId;
        var productName = entry.ProductItem?.Name;
        var workDate = entry.WorkDate;
        var qty = entry.Quantity;

        entry.Deleted = DateTime.Now;
        entry.DeletedBy = CurrentUserId.ToString();
        await SaveAndRepriceAsync(storeId);

        // Notification
        try
        {
            if (empUserId.HasValue)
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: empUserId.Value,
                    type: NotificationType.Warning,
                    title: "Xóa sản lượng",
                    message: $"Đã xóa {qty} {productName} ngày {workDate:dd/MM/yyyy}",
                    relatedEntityId: id,
                    relatedEntityType: "ProductionEntry",
                    categoryCode: "production",
                    storeId: storeId);
            }
        }
        catch { }

        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• SUMMARY â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpGet("summary")]
    [RequireModulePermission("Production", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ProductionSummaryDto>>>> GetSummary(
        [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate,
        [FromQuery] Guid? employeeId, [FromQuery] Guid? productGroupId)
    {
        var storeId = RequiredStoreId;
        if (IsEmployee && !IsManager)
        {
            if (!EmployeeId.HasValue)
                return Ok(AppResponse<List<ProductionSummaryDto>>.Success([]));
            employeeId = EmployeeId.Value;
        }

        var query = dbContext.ProductionEntries
            .Include(e => e.Employee)
            .Include(e => e.ProductItem).ThenInclude(p => p.ProductGroup)
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkDate >= fromDate.Date && e.WorkDate < toDate.Date.AddDays(1));

        if (employeeId.HasValue) query = query.Where(e => e.EmployeeId == employeeId.Value);
        if (productGroupId.HasValue) query = query.Where(e => e.ProductItem.ProductGroupId == productGroupId.Value);

        var grouped = await query
            .GroupBy(e => new { e.EmployeeId, e.Employee.LastName, e.Employee.FirstName, e.Employee.EmployeeCode })
            .Select(g => new
            {
                g.Key.EmployeeId,
                FullName = (g.Key.LastName + " " + g.Key.FirstName).Trim(),
                g.Key.EmployeeCode,
                TotalQuantity = g.Sum(e => e.Quantity),
                TotalAmount = g.Sum(e => e.Amount ?? 0),
                Items = g.GroupBy(e => new { e.ProductItem.Name, GroupName = e.ProductItem.ProductGroup.Name })
                    .Select(ig => new ProductionSummaryItemDto(
                        ig.Key.Name, ig.Key.GroupName,
                        ig.Sum(e => e.Quantity), ig.Sum(e => e.Amount ?? 0)))
                    .ToList()
            })
            .ToListAsync();

        var result = grouped.Select(g => new ProductionSummaryDto(
            g.EmployeeId.ToString(), g.FullName, g.EmployeeCode,
            g.TotalQuantity, g.TotalAmount, g.Items)).ToList();

        return Ok(AppResponse<List<ProductionSummaryDto>>.Success(result));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• EXPORT â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpGet("export")]
    [RequireModulePermission("Production", ModulePermissionAction.Export)]
    public async Task<ActionResult<AppResponse<List<ProductionExportRowDto>>>> ExportEntries(
        [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate,
        [FromQuery] Guid? employeeId, [FromQuery] Guid? productGroupId)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.ProductionEntries
            .Include(e => e.Employee)
            .Include(e => e.ProductItem).ThenInclude(p => p.ProductGroup)
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkDate >= fromDate.Date && e.WorkDate < toDate.Date.AddDays(1));

        if (employeeId.HasValue) query = query.Where(e => e.EmployeeId == employeeId.Value);
        if (productGroupId.HasValue) query = query.Where(e => e.ProductItem.ProductGroupId == productGroupId.Value);

        var rows = await query
            .OrderBy(e => e.WorkDate).ThenBy(e => e.Employee.LastName).ThenBy(e => e.Employee.FirstName)
            .Select(e => new ProductionExportRowDto(
                (e.Employee.LastName + " " + e.Employee.FirstName).Trim(),
                e.Employee.EmployeeCode,
                e.ProductItem.Name,
                e.ProductItem.ProductGroup.Name,
                e.WorkDate, e.Quantity, e.UnitPrice, e.Amount, e.Note))
            .ToListAsync();

        return Ok(AppResponse<List<ProductionExportRowDto>>.Success(rows));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• IMPORT â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    [HttpPost("import")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ImportFromExcel([FromBody] ProductionImportDto dto)
    {
        if (dto.Rows == null || dto.Rows.Count == 0)
            return Ok(AppResponse<object>.Fail("Không có dữ liệu import"));

        var storeId = RequiredStoreId;
        var employees = await dbContext.Employees
            .Where(e => e.StoreId == storeId && e.Deleted == null)
            .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName })
            .ToListAsync();
        var products = await dbContext.ProductItems
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .Select(p => new { p.Id, p.Code })
            .ToListAsync();

        int created = 0, updated = 0;
        var errors = new List<string>();
        var upsert = new EntryUpserter(dbContext, storeId, CurrentUserId.ToString());

        foreach (var row in dto.Rows)
        {
            if (string.IsNullOrWhiteSpace(row.EmployeeCode) || string.IsNullOrWhiteSpace(row.ProductCode))
                continue;

            var normalizedEmpCode = NormalizeCode(row.EmployeeCode);
            var emp = employees.FirstOrDefault(e =>
                NormalizeCode(e.EmployeeCode ?? "").Equals(normalizedEmpCode, StringComparison.OrdinalIgnoreCase));
            if (emp == null)
            {
                errors.Add($"Không tìm thấy NV '{row.EmployeeCode}'");
                continue;
            }

            var normalizedProdCode = row.ProductCode.Trim();
            var prod = products.FirstOrDefault(p =>
                (p.Code ?? "").Trim().Equals(normalizedProdCode, StringComparison.OrdinalIgnoreCase));
            if (prod == null)
            {
                errors.Add($"Không tìm thấy SP '{row.ProductCode}'");
                continue;
            }

            if (row.Quantity <= 0) continue;

            // Use per-row date if provided, otherwise fall back to global WorkDate
            DateTime entryDate = dto.WorkDate.Date;
            if (!string.IsNullOrWhiteSpace(row.WorkDate))
            {
                if (DateTime.TryParseExact(row.WorkDate.Trim(),
                    new[] { "dd/MM/yyyy", "yyyy-MM-dd", "d/M/yyyy", "MM/dd/yyyy" },
                    System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var parsedDate))
                {
                    entryDate = parsedDate.Date;
                }
            }

            var outcome = await upsert.UpsertAsync(emp.Id, prod.Id, entryDate, row.Quantity, row.Note ?? "Excel import");
            if (outcome == UpsertOutcome.Locked)
                errors.Add($"NV '{row.EmployeeCode}' tháng {entryDate:MM/yyyy} đã chốt lương — bỏ qua");
            else if (outcome == UpsertOutcome.Updated) updated++;
            else created++;
        }

        await SaveAndRepriceAsync(storeId);

        // Notification for import
        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: CurrentUserId,
                type: NotificationType.Success,
                title: "Import sản lượng hoàn tất",
                message: $"Đã import {created}/{dto.Rows.Count} dòng từ Excel",
                relatedEntityType: "ProductionEntry",
                categoryCode: "production",
                storeId: storeId);
        }
        catch { }

        return Ok(AppResponse<object>.Success(new
        {
            created,
            updated,
            totalRows = dto.Rows.Count,
            errors = errors.Take(20).ToList()
        }));
    }

    [HttpPost("gsheet/test-connection")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> TestGSheetConnection([FromBody] ProductionGSheetSyncDto dto)
    {
        try
        {
            var spreadsheetId = ExtractSpreadsheetId(dto.SpreadsheetUrl);
            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("URL Google Sheet không hợp lệ"));

            var sheetNames = await kpiSheetService.GetSheetNamesAsync(spreadsheetId);
            return Ok(AppResponse<object>.Success(new
            {
                connected = true,
                spreadsheetId,
                sheetNames,
                selectedSheet = dto.SheetName
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Fail($"Lỗi kết nối: {ex.Message}"));
        }
    }

    [HttpPost("gsheet/sheet-names")]
    [RequireModulePermission("Production", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<List<string>>>> GetGSheetNames([FromBody] ProductionGSheetSyncDto dto)
    {
        try
        {
            var spreadsheetId = ExtractSpreadsheetId(dto.SpreadsheetUrl);
            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<List<string>>.Fail("URL không hợp lệ"));

            var names = await kpiSheetService.GetSheetNamesAsync(spreadsheetId);
            return Ok(AppResponse<List<string>>.Success(names));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<List<string>>.Fail($"Lỗi: {ex.Message}"));
        }
    }

    [HttpPost("gsheet/sync")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SyncFromGSheet([FromBody] ProductionGSheetSyncDto dto)
    {
        try
        {
            var spreadsheetId = ExtractSpreadsheetId(dto.SpreadsheetUrl);
            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("URL Google Sheet không hợp lệ"));

            var storeId = RequiredStoreId;

            // Read all data from sheet
            var sheetData = await kpiSheetService.ReadKpiDataAsync(spreadsheetId, dto.SheetName);
            if (sheetData.Count == 0)
                return Ok(AppResponse<object>.Fail("Không có dữ liệu trong sheet"));

            // Load employees and products
            var employees = await dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName })
                .ToListAsync();
            var products = await dbContext.ProductItems
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => new { p.Id, p.Code, p.Name })
                .ToListAsync();

            // Get header columns (all columns except EmployeeCode)
            var allColumns = sheetData
                .SelectMany(r => r.KpiValues.Keys)
                .Distinct()
                .ToList();

            int created = 0;
            var errors = new List<string>();
            var upsert = new EntryUpserter(dbContext, storeId, CurrentUserId.ToString());

            foreach (var row in sheetData)
            {
                if (string.IsNullOrWhiteSpace(row.EmployeeCode)) continue;

                var normalizedEmpCode = NormalizeCode(row.EmployeeCode);
                var emp = employees.FirstOrDefault(e =>
                    NormalizeCode(e.EmployeeCode ?? "").Equals(normalizedEmpCode, StringComparison.OrdinalIgnoreCase));
                if (emp == null)
                {
                    errors.Add($"Không tìm thấy NV '{row.EmployeeCode}'");
                    continue;
                }

                // Each column = product code, value = quantity
                foreach (var kv in row.KpiValues)
                {
                    var columnName = kv.Key.Trim();
                    var quantity = kv.Value;
                    if (quantity <= 0) continue;

                    // Match column name to product code or name
                    var prod = products.FirstOrDefault(p =>
                        (p.Code ?? "").Trim().Equals(columnName, StringComparison.OrdinalIgnoreCase)
                        || (p.Name ?? "").Trim().Equals(columnName, StringComparison.OrdinalIgnoreCase));
                    if (prod == null)
                    {
                        errors.Add($"Không tìm thấy SP '{columnName}'");
                        continue;
                    }

                    // Đồng bộ lại cùng ngày: cập nhật số lượng thay vì nhân đôi dòng.
                    var outcome = await upsert.UpsertAsync(emp.Id, prod.Id, dto.WorkDate.Date, quantity, "Google Sheet sync");
                    if (outcome == UpsertOutcome.Locked)
                        errors.Add($"NV '{row.EmployeeCode}' tháng {dto.WorkDate:MM/yyyy} đã chốt lương — bỏ qua");
                    else created++;
                }
            }

            await SaveAndRepriceAsync(storeId);
            return Ok(AppResponse<object>.Success(new
            {
                created,
                totalRows = sheetData.Count,
                columns = allColumns,
                errors = errors.Distinct().Take(20).ToList()
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Fail($"Lỗi đồng bộ: {ex.Message}"));
        }
    }

    [HttpPost("gsheet/sync-multi")]
    [RequireModulePermission("Production", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SyncMultiFromGSheet([FromBody] ProductionGSheetMultiSyncDto dto)
    {
        try
        {
            var spreadsheetId = ExtractSpreadsheetId(dto.SpreadsheetUrl);
            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("URL Google Sheet không hợp lệ"));

            if (dto.Tabs == null || dto.Tabs.Count == 0)
                return Ok(AppResponse<object>.Fail("Chưa chọn sheet nào"));

            var storeId = RequiredStoreId;
            var employees = await dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName })
                .ToListAsync();
            var products = await dbContext.ProductItems
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                .Select(p => new { p.Id, p.Code, p.Name })
                .ToListAsync();

            int totalCreated = 0;
            var upsert = new EntryUpserter(dbContext, storeId, CurrentUserId.ToString());
            var errors = new List<string>();

            foreach (var tab in dto.Tabs)
            {
                try
                {
                    var sheetData = await kpiSheetService.ReadKpiDataAsync(spreadsheetId, tab.SheetName);
                    if (sheetData.Count == 0) continue;

                    foreach (var row in sheetData)
                    {
                        if (string.IsNullOrWhiteSpace(row.EmployeeCode)) continue;

                        var normalizedEmpCode = NormalizeCode(row.EmployeeCode);
                        var emp = employees.FirstOrDefault(e =>
                            NormalizeCode(e.EmployeeCode ?? "").Equals(normalizedEmpCode, StringComparison.OrdinalIgnoreCase));
                        if (emp == null)
                        {
                            errors.Add($"[{tab.SheetName}] Không tìm thấy NV '{row.EmployeeCode}'");
                            continue;
                        }

                        foreach (var kv in row.KpiValues)
                        {
                            var columnName = kv.Key.Trim();
                            var quantity = kv.Value;
                            if (quantity <= 0) continue;

                            var prod = products.FirstOrDefault(p =>
                                (p.Code ?? "").Trim().Equals(columnName, StringComparison.OrdinalIgnoreCase)
                                || (p.Name ?? "").Trim().Equals(columnName, StringComparison.OrdinalIgnoreCase));
                            if (prod == null)
                            {
                                errors.Add($"[{tab.SheetName}] Không tìm thấy SP '{columnName}'");
                                continue;
                            }

                            var outcome = await upsert.UpsertAsync(
                                emp.Id, prod.Id, tab.WorkDate.Date, quantity, $"GSheet sync - {tab.SheetName}");
                            if (outcome == UpsertOutcome.Locked)
                                errors.Add($"[{tab.SheetName}] NV '{row.EmployeeCode}' đã chốt lương tháng {tab.WorkDate:MM/yyyy} — bỏ qua");
                            else totalCreated++;
                        }
                    }
                }
                catch (Exception ex)
                {
                    errors.Add($"[{tab.SheetName}] Lỗi: {ex.Message}");
                }
            }

            await SaveAndRepriceAsync(storeId);
            return Ok(AppResponse<object>.Success(new
            {
                created = totalCreated,
                totalTabs = dto.Tabs.Count,
                errors = errors.Distinct().Take(30).ToList()
            }));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<object>.Fail($"Lỗi đồng bộ: {ex.Message}"));
        }
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• HELPERS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    private static string NormalizeCode(string code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "";
        code = code.Trim();
        // Handle Excel scientific notation / decimal (e.g., "1.23456E+09", "123.0")
        if (code.Contains('.') || code.Contains('E', StringComparison.OrdinalIgnoreCase))
        {
            if (double.TryParse(code, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var num))
            {
                code = ((long)num).ToString();
            }
        }
        return code;
    }

    /// <summary>
    /// Validate bậc giá không chồng lấn (overlap)
    /// </summary>
    private static string? ValidatePriceTiers(List<ProductPriceTierCreateDto> tiers)
    {
        if (tiers.Count <= 1) return null;
        var sorted = tiers.OrderBy(t => t.TierLevel).ThenBy(t => t.MinQuantity).ToList();
        for (int i = 1; i < sorted.Count; i++)
        {
            var prev = sorted[i - 1];
            var curr = sorted[i];
            if (prev.MaxQuantity.HasValue && curr.MinQuantity <= prev.MaxQuantity.Value)
                return $"Bậc giá {prev.TierLevel} và {curr.TierLevel} bị chồng lấn: [{prev.MinQuantity}-{prev.MaxQuantity}] vs [{curr.MinQuantity}-{curr.MaxQuantity}]";
            if (!prev.MaxQuantity.HasValue && curr.MinQuantity > 0)
                return $"Bậc {prev.TierLevel} không giới hạn trên (MaxQuantity=null) nhưng có bậc {curr.TierLevel} phía sau";
        }
        return null;
    }

    private static string? ExtractSpreadsheetId(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        // https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/...
        var match = System.Text.RegularExpressions.Regex.Match(
            url, @"/spreadsheets/d/([a-zA-Z0-9_-]+)");
        return match.Success ? match.Groups[1].Value : null;
    }
}

