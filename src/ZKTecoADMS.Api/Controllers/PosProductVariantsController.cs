using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/products/{productId:guid}/variants")]
[Authorize]
public class PosProductVariantsController(
    ZKTecoDbContext dbContext,
    ILogger<PosProductVariantsController> logger) : AuthenticatedControllerBase
{
    public record VariantDto(
        Guid Id, string SkuCode, string? Barcode, string Name, string? AttributeJson,
        decimal CostPrice, decimal BasePrice, decimal OnHandQty, bool IsActive);

    public record VariantUpsertDto(
        string? SkuCode, string? Barcode, string Name, string? AttributeJson,
        decimal CostPrice, decimal BasePrice, decimal OnHandQty);

    public record GenerateAttributeInput(Guid? AttributeId, string AttributeName, List<string> Values);

    public record GenerateUnitInput(string UnitName, decimal ConversionRate, decimal BasePrice, bool IsDirectSale);

    public record GenerateVariantsDto(
        List<GenerateAttributeInput> Attributes,
        List<GenerateUnitInput>? Units,
        decimal? DefaultBasePrice,
        decimal? DefaultCostPrice);

    public record SyncVariantInput(
        Guid? Id,
        string? SkuCode,
        string? Barcode,
        string Name,
        string? AttributeJson,
        decimal CostPrice,
        decimal BasePrice,
        decimal OnHandQty);

    public record SyncVariantsDto(List<SyncVariantInput> Variants);

    [HttpGet]
    [RequireModulePermission("PosProducts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<VariantDto>>>> List(Guid productId)
    {
        var storeId = RequiredStoreId;
        var product = await dbContext.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (product == null)
            return NotFound(AppResponse<List<VariantDto>>.Fail("Không tìm thấy hàng hóa"));

        var items = await dbContext.PosProductVariants
            .AsNoTracking()
            .Where(v => v.ProductId == productId && v.StoreId == storeId &&
                        v.Deleted == null && v.IsActive)
            .OrderBy(v => v.SkuCode)
            .ToListAsync();
        var dtos = items.Select(v => Map(v, product.OnHandQty)).ToList();
        return Ok(AppResponse<List<VariantDto>>.Success(dtos));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<VariantDto>>> Create(
        Guid productId, [FromBody] VariantUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var product = await dbContext.PosProducts
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (product == null)
            return NotFound(AppResponse<VariantDto>.Fail("Không tìm thấy hàng hóa"));
        if (product.ProductType != PosProductType.Goods)
            return BadRequest(AppResponse<VariantDto>.Fail("Chỉ hàng hóa mới có biến thể"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<VariantDto>.Fail("Tên biến thể không được để trống"));

        var sku = dto.SkuCode?.Trim();
        if (string.IsNullOrEmpty(sku))
            sku = await GenerateSkuAsync(productId, product.ProductCode);

        var entity = new PosProductVariant
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            ProductId = productId,
            SkuCode = sku,
            Barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim(),
            Name = name,
            AttributeJson = dto.AttributeJson,
            CostPrice = dto.CostPrice,
            BasePrice = dto.BasePrice,
            OnHandQty = PosVariantStockHelper.IsUnitOnlyVariant(dto.AttributeJson) ? 0 : dto.OnHandQty,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductVariants.Add(entity);
        await dbContext.SaveChangesAsync();
        await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, product);

        return Ok(AppResponse<VariantDto>.Success(Map(entity, product.OnHandQty)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<VariantDto>>> Update(
        Guid productId, Guid id, [FromBody] VariantUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductVariants
            .AsTracking()
            .Include(v => v.Product)
            .FirstOrDefaultAsync(v => v.Id == id && v.ProductId == productId &&
                v.StoreId == storeId && v.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<VariantDto>.Fail("Không tìm thấy biến thể"));

        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<VariantDto>.Fail("Tên biến thể không được để trống"));

        if (!string.IsNullOrWhiteSpace(dto.SkuCode))
            entity.SkuCode = dto.SkuCode.Trim();
        entity.Barcode = string.IsNullOrWhiteSpace(dto.Barcode) ? null : dto.Barcode.Trim();
        entity.Name = name;
        entity.AttributeJson = dto.AttributeJson;
        entity.CostPrice = dto.CostPrice;
        entity.BasePrice = dto.BasePrice;
        if (!PosVariantStockHelper.IsUnitOnlyVariant(entity.AttributeJson))
        {
            PosVariantStockHelper.TryApplyVariantStockEdit(
                dbContext, storeId, productId, entity, dto.OnHandQty, CurrentUserEmail);
        }
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        if (entity.Product != null)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, entity.Product);

        var baseQty = entity.Product?.OnHandQty ?? 0;
        return Ok(AppResponse<VariantDto>.Success(Map(entity, baseQty)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid productId, Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductVariants
            .AsTracking()
            .Include(v => v.Product)
            .FirstOrDefaultAsync(v => v.Id == id && v.ProductId == productId &&
                v.StoreId == storeId && v.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy biến thể"));

        entity.IsActive = false;
        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        ReleaseSkuCode(entity);
        await dbContext.SaveChangesAsync();
        if (entity.Product != null)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, entity.Product);

        return Ok(AppResponse<object>.Success(new { entity.Id }));
    }

    public record VariantQuickPatchDto(decimal? BasePrice, decimal? OnHandQty, decimal? CostPrice);

    [HttpPatch("{id:guid}/quick")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<VariantDto>>> QuickPatch(
        Guid productId, Guid id, [FromBody] VariantQuickPatchDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosProductVariants
            .AsTracking()
            .Include(v => v.Product)
            .FirstOrDefaultAsync(v => v.Id == id && v.ProductId == productId &&
                v.StoreId == storeId && v.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<VariantDto>.Fail("Không tìm thấy biến thể"));

        if (dto.BasePrice.HasValue) entity.BasePrice = dto.BasePrice.Value;
        if (dto.CostPrice.HasValue) entity.CostPrice = dto.CostPrice.Value;
        if (dto.OnHandQty.HasValue && entity.Product != null)
        {
            var oldDisplay = PosVariantStockHelper.ResolveVariantDisplayQty(
                entity.Product.OnHandQty, entity.AttributeJson, entity.OnHandQty);
            if (oldDisplay != dto.OnHandQty.Value)
            {
                PosVariantStockHelper.TryApplyVariantStockEdit(
                    dbContext, storeId, productId, entity, dto.OnHandQty.Value, CurrentUserEmail);
            }
        }
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        if (entity.Product != null)
            await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, entity.Product);

        var baseQty = entity.Product?.OnHandQty ?? 0;
        return Ok(AppResponse<VariantDto>.Success(Map(entity, baseQty)));
    }

    [HttpPost("generate")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<VariantDto>>>> Generate(
        Guid productId, [FromBody] GenerateVariantsDto dto)
    {
        var storeId = RequiredStoreId;
        var product = await dbContext.PosProducts
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (product == null)
            return NotFound(AppResponse<List<VariantDto>>.Fail("Không tìm thấy hàng hóa"));
        if (product.ProductType != PosProductType.Goods)
            return BadRequest(AppResponse<List<VariantDto>>.Fail("Chỉ hàng hóa mới sinh biến thể"));

        var attrs = dto.Attributes?
            .Where(a => a.Values != null && a.Values.Count > 0 &&
                        !string.IsNullOrWhiteSpace(a.AttributeName))
            .ToList() ?? [];

        var unitInputs = dto.Units?
            .Where(u => !string.IsNullOrWhiteSpace(u.UnitName) && u.ConversionRate > 0)
            .ToList();
        if (unitInputs == null || unitInputs.Count == 0)
        {
            unitInputs =
            [
                new GenerateUnitInput(product.BaseUnitName, 1, product.BasePrice, product.IsDirectSale),
            ];
        }

        List<List<(string AttributeName, string Value)>> combinations;
        if (attrs.Count == 0)
        {
            combinations = [new List<(string, string)> { ("", "") }];
        }
        else
        {
            combinations = BuildCombinations(attrs);
            if (combinations.Count == 0)
                combinations = [new List<(string, string)> { ("", "") }];
        }

        var created = new List<PosProductVariant>();
        var seq = 1;
        foreach (var combo in combinations)
        {
            foreach (var unit in unitInputs)
            {
                var unitName = unit.UnitName.Trim();
                var isBase = unit.ConversionRate == 1 &&
                             unitInputs.Count(u => u.ConversionRate == 1) == 1 &&
                             unit == unitInputs.First(u => u.ConversionRate == 1);
                if (isBase && combo.Count == 1 && string.IsNullOrWhiteSpace(combo[0].Value))
                    continue;

                var attrParts = combo
                    .Where(c => !string.IsNullOrWhiteSpace(c.Value))
                    .Select(c => c.Value)
                    .ToList();
                var label = attrParts.Count > 0
                    ? $"{string.Join(" / ", attrParts)} · {unitName}"
                    : unitName;

                var attrDict = combo
                    .Where(c => !string.IsNullOrWhiteSpace(c.AttributeName) &&
                                !string.IsNullOrWhiteSpace(c.Value))
                    .ToDictionary(c => c.AttributeName, c => c.Value);
                attrDict["_unit"] = unitName;
                attrDict["_conversion"] = unit.ConversionRate.ToString(System.Globalization.CultureInfo.InvariantCulture);

                var attrJson = JsonSerializer.Serialize(attrDict);
                var sku = $"{product.ProductCode}-{seq:D2}";
                while (await SkuTakenAsync(productId, sku))
                {
                    seq++;
                    sku = $"{product.ProductCode}-{seq:D2}";
                }

                var entity = new PosProductVariant
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ProductId = productId,
                    SkuCode = sku,
                    Name = label,
                    AttributeJson = attrJson,
                    CostPrice = dto.DefaultCostPrice ?? product.CostPrice,
                    BasePrice = unit.BasePrice > 0 ? unit.BasePrice : (dto.DefaultBasePrice ?? product.BasePrice),
                    OnHandQty = 0,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                dbContext.PosProductVariants.Add(entity);
                created.Add(entity);
                seq++;
            }
        }

        await dbContext.SaveChangesAsync();
        await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, product);

        return Ok(AppResponse<List<VariantDto>>.Success(
            created.Select(v => Map(v, product.OnHandQty)).ToList()));
    }

    [HttpPost("sync")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<VariantDto>>>> Sync(
        Guid productId, [FromBody] SyncVariantsDto dto)
    {
        try
        {
            return await SyncCoreAsync(productId, dto);
        }
        catch (DbUpdateException ex)
        {
            logger.LogError(ex, "variants/sync failed for product {ProductId}", productId);
            var detail = ex.InnerException?.Message ?? ex.Message;
            return BadRequest(AppResponse<List<VariantDto>>.Fail(
                $"Không thể lưu biến thể: {detail}"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "variants/sync failed for product {ProductId}", productId);
            return StatusCode(500, AppResponse<List<VariantDto>>.Fail(ex.Message));
        }
    }

    private async Task<ActionResult<AppResponse<List<VariantDto>>>> SyncCoreAsync(
        Guid productId, SyncVariantsDto dto)
    {
        var storeId = RequiredStoreId;
        var product = await dbContext.PosProducts
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == productId && p.StoreId == storeId && p.Deleted == null);
        if (product == null)
            return NotFound(AppResponse<List<VariantDto>>.Fail("Không tìm thấy hàng hóa"));
        if (product.ProductType != PosProductType.Goods)
            return BadRequest(AppResponse<List<VariantDto>>.Fail("Chỉ hàng hóa mới có biến thể"));

        var productCode = string.IsNullOrWhiteSpace(product.ProductCode)
            ? product.Id.ToString("N")[..8]
            : product.ProductCode.Trim();

        var inputs = dto.Variants ?? [];
        var keepIds = inputs.Where(v => v.Id.HasValue).Select(v => v.Id!.Value).ToHashSet();

        // Bao gồm cả bản ghi soft-delete (global filter ẩn chúng). AsTracking bắt buộc vì DbContext NoTracking.
        var allVariants = await dbContext.PosProductVariants
            .AsTracking()
            .IgnoreQueryFilters()
            .Where(v => v.ProductId == productId && v.StoreId == storeId)
            .ToListAsync();

        var activeVariants = allVariants
            .Where(v => v.Deleted == null && v.IsActive)
            .ToList();

        var toRemoveIds = activeVariants
            .Where(e => !keepIds.Contains(e.Id))
            .Select(e => e.Id)
            .ToList();
        if (toRemoveIds.Count > 0)
        {
            var now = DateTime.UtcNow;
            foreach (var entity in activeVariants.Where(e => toRemoveIds.Contains(e.Id)))
            {
                entity.IsActive = false;
                entity.Deleted = now;
                entity.DeletedBy = CurrentUserEmail;
                entity.UpdatedAt = now;
                ReleaseSkuCode(entity);
            }
        }

        var result = new List<PosProductVariant>();
        // Mọi SkuCode trong DB (kể cả soft-delete) đều chiếm unique index
        var reservedSkus = allVariants
            .Select(v => v.SkuCode)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var input in inputs)
        {
            var name = input.Name?.Trim() ?? "";
            if (string.IsNullOrEmpty(name)) continue;

            PosProductVariant entity;
            if (input.Id.HasValue)
            {
                entity = allVariants.FirstOrDefault(v => v.Id == input.Id.Value);
                if (entity == null)
                {
                    entity = NewVariantEntity(storeId, productId);
                    dbContext.PosProductVariants.Add(entity);
                }
                else if (entity.Deleted != null)
                {
                    entity.Deleted = null;
                    entity.DeletedBy = null;
                    entity.IsActive = true;
                }
            }
            else
            {
                entity = NewVariantEntity(storeId, productId);
                dbContext.PosProductVariants.Add(entity);
            }

            var sku = input.SkuCode?.Trim();
            if (string.IsNullOrEmpty(sku) || await SkuTakenAsync(productId, sku, entity.Id))
                sku = await GenerateSkuAsync(productId, productCode, reservedSkus);
            reservedSkus.Add(sku);
            entity.SkuCode = sku;
            entity.Barcode = string.IsNullOrWhiteSpace(input.Barcode) ? null : input.Barcode.Trim();
            entity.Name = name;
            entity.AttributeJson = input.AttributeJson;
            entity.CostPrice = input.CostPrice;
            entity.BasePrice = input.BasePrice;
            entity.Product = product;
            if (PosVariantStockHelper.IsUnitOnlyVariant(input.AttributeJson))
            {
                entity.OnHandQty = 0;
            }
            else
            {
                var oldVariantQty = entity.OnHandQty;
                entity.OnHandQty = input.OnHandQty;
                if (oldVariantQty != input.OnHandQty)
                {
                    PosStockRecording.RecordAdjustIfChanged(
                        dbContext, storeId, productId, entity.Id,
                        oldVariantQty, input.OnHandQty, CurrentUserEmail);
                }
            }
            entity.UpdatedAt = DateTime.UtcNow;
            entity.UpdatedBy = CurrentUserEmail;
            entity.IsActive = true;
            result.Add(entity);
        }

        // Dọn biến thể thừa — kể cả khi client không gửi đủ id cũ
        var finalIds = result.Select(r => r.Id).ToHashSet();
        var nowCleanup = DateTime.UtcNow;
        foreach (var orphan in allVariants.Where(v =>
                     v.Deleted == null && v.IsActive &&
                     v.ProductId == productId && !finalIds.Contains(v.Id)))
        {
            orphan.IsActive = false;
            orphan.Deleted = nowCleanup;
            orphan.DeletedBy = CurrentUserEmail;
            orphan.UpdatedAt = nowCleanup;
            ReleaseSkuCode(orphan);
        }

        await dbContext.SaveChangesAsync();
        await PosVariantStockHelper.SyncParentStockFromVariantsAsync(dbContext, product);

        return Ok(AppResponse<List<VariantDto>>.Success(
            result.Select(v => Map(v, product.OnHandQty)).ToList()));
    }

    private PosProductVariant NewVariantEntity(Guid storeId, Guid productId) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = storeId,
        ProductId = productId,
        IsActive = true,
        CreatedBy = CurrentUserEmail,
    };

    private static VariantDto Map(PosProductVariant v, decimal productBaseQty) => new(
        v.Id, v.SkuCode, v.Barcode, v.Name, v.AttributeJson,
        v.CostPrice, v.BasePrice,
        PosVariantStockHelper.ResolveVariantDisplayQty(productBaseQty, v.AttributeJson, v.OnHandQty),
        v.IsActive);

    private Task<bool> ProductOkAsync(Guid storeId, Guid productId) =>
        dbContext.PosProducts.AnyAsync(p =>
            p.Id == productId && p.StoreId == storeId && p.Deleted == null);

    private Task<bool> SkuTakenAsync(Guid productId, string sku, Guid? exceptId = null) =>
        dbContext.PosProductVariants
            .IgnoreQueryFilters()
            .AnyAsync(v =>
                v.ProductId == productId &&
                v.SkuCode == sku &&
                (!exceptId.HasValue || v.Id != exceptId.Value));

    private static void ReleaseSkuCode(PosProductVariant entity)
    {
        const int maxLen = 50;
        var suffix = $"-X{Guid.NewGuid().ToString("N")[..5]}";
        var baseSku = entity.SkuCode;
        if (baseSku.Length + suffix.Length > maxLen)
            baseSku = baseSku[..Math.Max(1, maxLen - suffix.Length)];
        entity.SkuCode = baseSku + suffix;
    }

    private async Task<string> GenerateSkuAsync(
        Guid productId, string productCode, HashSet<string>? reserved = null)
    {
        reserved ??= new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 1; i < 1000; i++)
        {
            var sku = $"{productCode}-V{i:D2}";
            if (reserved.Contains(sku)) continue;
            if (!await SkuTakenAsync(productId, sku))
                return sku;
        }

        return $"{productCode}-V{Guid.NewGuid().ToString("N")[..6]}";
    }

    private static List<List<(string AttributeName, string Value)>> BuildCombinations(
        List<GenerateAttributeInput> attrs)
    {
        var result = new List<List<(string, string)>> { new List<(string, string)>() };
        foreach (var attr in attrs)
        {
            var next = new List<List<(string, string)>>();
            foreach (var partial in result)
            {
                foreach (var val in attr.Values.Where(v => !string.IsNullOrWhiteSpace(v)))
                {
                    var row = new List<(string, string)>(partial)
                    {
                        (attr.AttributeName.Trim(), val.Trim()),
                    };
                    next.Add(row);
                }
            }

            result = next;
        }

        return result;
    }
}
