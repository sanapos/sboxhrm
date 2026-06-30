using ClosedXML.Excel;
using ZKTecoADMS.Api.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosProductsController
{
    [HttpGet("export/excel")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportExcel(
        [FromQuery] string? search,
        [FromQuery] Guid? categoryId,
        [FromQuery] Guid? supplierId)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosProducts
            .AsNoTracking()
            .Include(p => p.Category)
            .Include(p => p.Brand)
            .Include(p => p.Supplier)
            .Include(p => p.StorageLocation)
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(p =>
                p.Name.ToLower().Contains(s) ||
                p.ProductCode.ToLower().Contains(s) ||
                (p.Barcode != null && p.Barcode.ToLower().Contains(s)));
        }
        if (categoryId.HasValue) query = query.Where(p => p.CategoryId == categoryId);
        if (supplierId.HasValue) query = query.Where(p => p.SupplierId == supplierId);

        var products = await query.OrderBy(p => p.Name).Take(10000).ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Hàng hóa");
        var headers = new[]
        {
            "STT", "Mã hàng", "Mã vạch", "Tên hàng", "Nhóm hàng", "Thương hiệu", "Nhà cung cấp",
            "Giá vốn", "Giá bán", "Tồn kho", "Tồn thấp nhất", "Tồn cao nhất",
            "Đơn vị", "Loại hàng", "Bán trực tiếp", "Trọng lượng", "Vị trí", "Mô tả"
        };

        var meta = ReportExcelMeta.FromUser(
            User, "DANH SÁCH HÀNG HÓA POS", null, null,
            new[] { $"Tổng: {products.Count}" }, products.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var p in products)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = p.ProductCode;
            ws.Cell(row, 3).Value = p.Barcode ?? "";
            ws.Cell(row, 4).Value = p.Name;
            ws.Cell(row, 5).Value = p.Category?.Name ?? "";
            ws.Cell(row, 6).Value = p.Brand?.Name ?? "";
            ws.Cell(row, 7).Value = p.Supplier?.Name ?? "";
            ws.Cell(row, 8).Value = p.CostPrice;
            ws.Cell(row, 9).Value = p.BasePrice;
            ws.Cell(row, 10).Value = p.OnHandQty;
            ws.Cell(row, 11).Value = p.MinStockQty;
            ws.Cell(row, 12).Value = p.MaxStockQty;
            ws.Cell(row, 13).Value = p.BaseUnitName;
            ws.Cell(row, 14).Value = p.ProductType == PosProductType.Service ? "Dịch vụ" : "Hàng hóa";
            ws.Cell(row, 15).Value = p.IsDirectSale ? "Có" : "Không";
            ws.Cell(row, 16).Value = p.Weight.HasValue ? p.Weight.Value : "";
            ws.Cell(row, 17).Value = p.StorageLocation?.Name ?? "";
            ws.Cell(row, 18).Value = p.Description ?? "";
            row++;
        }

        ws.Columns(1, headers.Length).AdjustToContents();
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        var fileName = $"HangHoa_POS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx";
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
    }

    [HttpPost("import/excel/file")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult<AppResponse<object>>> ImportExcelFile(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("File không hợp lệ"));

        var storeId = RequiredStoreId;
        List<PosProductExcelImportParser.ImportRow> rows;
        try
        {
            await using var stream = file.OpenReadStream();
            rows = PosProductExcelImportParser.Parse(stream);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "POS product import parse failed");
            return BadRequest(AppResponse<object>.Fail("Không đọc được file Excel"));
        }

        if (rows.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có dòng dữ liệu hợp lệ"));

        var categories = await dbContext.PosProductCategories
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToDictionaryAsync(x => x.Name.ToLower(), x => x.Id);
        var brands = await dbContext.PosProductBrands
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToDictionaryAsync(x => x.Name.ToLower(), x => x.Id);
        var suppliers = await dbContext.PosSuppliers
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToDictionaryAsync(x => x.Name.ToLower(), x => x.Id);
        var locations = await dbContext.PosStorageLocations
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToDictionaryAsync(x => x.Name.ToLower(), x => x.Id);

        var created = 0;
        var updated = 0;
        var errors = new List<string>();

        foreach (var (row, i) in rows.Select((r, idx) => (r, idx + 1)))
        {
            try
            {
                Guid? catId = null;
                if (!string.IsNullOrWhiteSpace(row.CategoryName))
                {
                    var key = row.CategoryName.ToLower();
                    if (!categories.TryGetValue(key, out var cid))
                    {
                        var cat = new PosProductCategory
                        {
                            Id = Guid.NewGuid(), StoreId = storeId, Name = row.CategoryName.Trim(),
                            IsActive = true, CreatedBy = CurrentUserEmail,
                        };
                        dbContext.PosProductCategories.Add(cat);
                        categories[key] = cat.Id;
                        catId = cat.Id;
                    }
                    else catId = cid;
                }

                Guid? brandId = await EnsureMasterAsync(row.BrandName, brands, name =>
                {
                    var e = new PosProductBrand { Id = Guid.NewGuid(), StoreId = storeId, Name = name, IsActive = true, CreatedBy = CurrentUserEmail };
                    dbContext.PosProductBrands.Add(e);
                    return e.Id;
                });

                Guid? supplierId = await EnsureMasterAsync(row.SupplierName, suppliers, name =>
                {
                    var e = new PosSupplier { Id = Guid.NewGuid(), StoreId = storeId, Name = name, IsActive = true, CreatedBy = CurrentUserEmail };
                    dbContext.PosSuppliers.Add(e);
                    return e.Id;
                });

                Guid? locId = await EnsureMasterAsync(row.LocationName, locations, name =>
                {
                    var e = new PosStorageLocation { Id = Guid.NewGuid(), StoreId = storeId, Name = name, IsActive = true, CreatedBy = CurrentUserEmail };
                    dbContext.PosStorageLocations.Add(e);
                    return e.Id;
                });

                PosProduct? entity = null;
                if (!string.IsNullOrWhiteSpace(row.ProductCode))
                {
                    entity = await dbContext.PosProducts.FirstOrDefaultAsync(p =>
                        p.StoreId == storeId && p.ProductCode == row.ProductCode && p.Deleted == null);
                }

                if (entity == null)
                {
                    var code = row.ProductCode?.Trim();
                    if (string.IsNullOrEmpty(code))
                        code = await GenerateProductCodeAsync(storeId);

                    entity = new PosProduct
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        ProductCode = code,
                        IsActive = true,
                        CreatedBy = CurrentUserEmail,
                    };
                    dbContext.PosProducts.Add(entity);
                    created++;
                }
                else updated++;

                entity.Barcode = row.Barcode;
                entity.Name = row.Name;
                entity.CategoryId = catId;
                entity.BrandId = brandId;
                entity.SupplierId = supplierId;
                entity.StorageLocationId = locId;
                entity.ProductType = row.ProductType;
                entity.CostPrice = row.CostPrice;
                entity.BasePrice = row.BasePrice;
                entity.OnHandQty = row.OnHandQty;
                entity.MinStockQty = row.MinStockQty;
                entity.MaxStockQty = row.MaxStockQty;
                entity.BaseUnitName = row.BaseUnitName;
                entity.IsDirectSale = row.IsDirectSale;
                entity.Weight = row.Weight;
                entity.Description = row.Description;
                entity.UpdatedAt = DateTime.UtcNow;
                entity.UpdatedBy = CurrentUserEmail;
            }
            catch (Exception ex)
            {
                errors.Add($"Dòng {i}: {ex.Message}");
            }
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            created,
            updated,
            total = rows.Count,
            errors,
        }));
    }

    private static async Task<Guid?> EnsureMasterAsync(
        string? name,
        Dictionary<string, Guid> cache,
        Func<string, Guid> create)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var key = name.Trim().ToLower();
        if (cache.TryGetValue(key, out var id)) return id;
        id = create(name.Trim());
        cache[key] = id;
        await Task.CompletedTask;
        return id;
    }

    private async Task<Dictionary<Guid, (decimal AvgDaily, DateTime? Stockout)>> GetStockoutMetricsBatchAsync(
        Guid storeId, IEnumerable<Guid> productIds)
    {
        var ids = productIds.ToList();
        if (ids.Count == 0) return [];

        var from = DateTime.UtcNow.Date.AddDays(-30);
        var sales = await dbContext.PosSaleOrderLines
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && ids.Contains(l.ProductId) &&
                        l.CreatedAt >= from && l.Deleted == null)
            .GroupBy(l => l.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Qty) })
            .ToDictionaryAsync(x => x.ProductId, x => x.Qty / 30m);

        var result = new Dictionary<Guid, (decimal, DateTime?)>();
        foreach (var id in ids)
        {
            sales.TryGetValue(id, out var avg);
            result[id] = (avg, null);
        }
        return result;
    }

    private static DateTime? ComputeStockoutDate(decimal onHand, decimal avgDaily) =>
        avgDaily > 0 && onHand > 0 ? DateTime.UtcNow.AddDays((double)(onHand / avgDaily)) : null;

    private async Task SyncAttributesAsync(Guid storeId, Guid productId, List<PosProductAttributeInput>? inputs)
    {
        if (inputs == null) return;

        var existing = await dbContext.PosProductAttributeValues
            .AsTracking()
            .Where(v => v.ProductId == productId && v.Deleted == null)
            .ToListAsync();

        var keepAttrIds = new HashSet<Guid>();
        var now = DateTime.UtcNow;

        foreach (var input in inputs)
        {
            if (string.IsNullOrWhiteSpace(input.Value)) continue;

            Guid attrId;
            if (input.AttributeId.HasValue)
            {
                attrId = input.AttributeId.Value;
            }
            else if (!string.IsNullOrWhiteSpace(input.AttributeName))
            {
                var name = input.AttributeName.Trim();
                var attr = await dbContext.PosProductAttributes
                    .FirstOrDefaultAsync(a => a.StoreId == storeId && a.Name == name && a.Deleted == null);
                if (attr == null)
                {
                    attr = new PosProductAttribute
                    {
                        Id = Guid.NewGuid(), StoreId = storeId, Name = name,
                        IsActive = true, CreatedBy = CurrentUserEmail,
                    };
                    dbContext.PosProductAttributes.Add(attr);
                    await dbContext.SaveChangesAsync();
                }
                attrId = attr.Id;
            }
            else continue;

            keepAttrIds.Add(attrId);

            var val = existing.FirstOrDefault(v => v.AttributeId == attrId);
            if (val == null)
            {
                val = new PosProductAttributeValue
                {
                    Id = Guid.NewGuid(), StoreId = storeId, ProductId = productId,
                    AttributeId = attrId, Value = input.Value.Trim(),
                    IsActive = true, CreatedBy = CurrentUserEmail,
                };
                dbContext.PosProductAttributeValues.Add(val);
                existing.Add(val);
            }
            else
            {
                val.Value = input.Value.Trim();
                val.UpdatedAt = now;
                val.UpdatedBy = CurrentUserEmail;
            }
        }

        foreach (var val in existing.Where(v => !keepAttrIds.Contains(v.AttributeId)))
        {
            val.Deleted = now;
            val.DeletedBy = CurrentUserEmail;
            val.UpdatedAt = now;
        }

        await dbContext.SaveChangesAsync();
    }
}
