using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Gán máy in theo sản phẩm / nhóm hàng POS.</summary>
[ApiController]
[Route("api/pos/product-printers")]
[Authorize]
public class PosProductPrinterController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    [HttpGet("export/excel")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<IActionResult> ExportExcel()
    {
        var storeId = RequiredStoreId;
        var products = await db.PosProducts.AsNoTracking()
            .Include(p => p.Category)
            .Include(p => p.DefaultPrinter)
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .OrderBy(p => p.Name)
            .Take(20000)
            .ToListAsync();

        var categories = await db.PosProductCategories.AsNoTracking()
            .Include(c => c.DefaultPrinter)
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive)
            .OrderBy(c => c.Name)
            .ToListAsync();

        using var workbook = new XLWorkbook();

        var wsP = workbook.Worksheets.Add("Sản phẩm");
        var headersP = new[] { "Mã hàng", "Tên hàng", "Nhóm hàng", "Máy in (tên)" };
        var metaP = ReportExcelMeta.FromUser(
            User, "GÁN MÁY IN THEO SẢN PHẨM", null, null,
            new[] { $"Tổng: {products.Count}" }, products.Count);
        var (hrP, drP) = ReportExcelLayout.ApplyMeta(wsP, metaP, headersP.Length);
        ReportExcelLayout.ApplyHeaderRow(wsP, hrP, headersP);
        var row = drP;
        foreach (var p in products)
        {
            wsP.Cell(row, 1).Value = p.ProductCode;
            wsP.Cell(row, 2).Value = p.Name;
            wsP.Cell(row, 3).Value = p.Category?.Name ?? "";
            wsP.Cell(row, 4).Value = p.DefaultPrinter?.Name ?? "";
            row++;
        }
        wsP.Columns(1, headersP.Length).AdjustToContents();

        var wsC = workbook.Worksheets.Add("Nhóm hàng");
        var headersC = new[] { "Tên nhóm hàng", "Máy in (tên)" };
        var metaC = ReportExcelMeta.FromUser(
            User, "GÁN MÁY IN THEO NHÓM HÀNG", null, null,
            new[] { $"Tổng: {categories.Count}" }, categories.Count);
        var (hrC, drC) = ReportExcelLayout.ApplyMeta(wsC, metaC, headersC.Length);
        ReportExcelLayout.ApplyHeaderRow(wsC, hrC, headersC);
        row = drC;
        foreach (var c in categories)
        {
            wsC.Cell(row, 1).Value = c.Name;
            wsC.Cell(row, 2).Value = c.DefaultPrinter?.Name ?? "";
            row++;
        }
        wsC.Columns(1, headersC.Length).AdjustToContents();

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"MayIn_SanPham_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    [HttpPost("import/excel/file")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<object>>> ImportExcel(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("File không hợp lệ"));

        var storeId = RequiredStoreId;
        await using var stream = file.OpenReadStream();
        using var workbook = new XLWorkbook(stream);

        var printers = await db.PosStorePrinters
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .ToDictionaryAsync(p => p.Name.Trim().ToLower(), p => p.Id);

        var updatedProducts = 0;
        var updatedCategories = 0;
        var errors = new List<string>();

        var wsP = workbook.Worksheets.FirstOrDefault(w =>
                      w.Name.Contains("Sản phẩm", StringComparison.OrdinalIgnoreCase) ||
                      w.Name.Contains("San pham", StringComparison.OrdinalIgnoreCase) ||
                      w.Name.Equals("Products", StringComparison.OrdinalIgnoreCase))
                  ?? workbook.Worksheets.First();

        var (pUpdated, pErrors) = await ImportProductSheetAsync(storeId, wsP, printers);
        updatedProducts += pUpdated;
        errors.AddRange(pErrors);

        var wsC = workbook.Worksheets.FirstOrDefault(w =>
            w.Name.Contains("Nhóm", StringComparison.OrdinalIgnoreCase) ||
            w.Name.Contains("Nhom", StringComparison.OrdinalIgnoreCase) ||
            w.Name.Contains("Categories", StringComparison.OrdinalIgnoreCase));
        if (wsC != null)
        {
            var (cUpdated, cErrors) = await ImportCategorySheetAsync(storeId, wsC, printers);
            updatedCategories += cUpdated;
            errors.AddRange(cErrors);
        }

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            updatedProducts,
            updatedCategories,
            errors,
        }));
    }

    async Task<(int updated, List<string> errors)> ImportProductSheetAsync(
        Guid storeId, IXLWorksheet ws, Dictionary<string, Guid> printers)
    {
        var updated = 0;
        var errors = new List<string>();
        var headerRow = FindHeaderRow(ws, "tenhang", "tên hàng", "name");
        if (headerRow <= 0) return (0, ["Sheet sản phẩm: không tìm thấy tiêu đề"]);

        var codeCol = FindCol(ws, headerRow, "mahang", "mã hàng", "code");
        var nameCol = FindCol(ws, headerRow, "tenhang", "tên hàng", "name");
        var printerCol = FindCol(ws, headerRow, "mayin", "máy in", "printer");
        if (codeCol <= 0 && nameCol <= 0)
            return (0, ["Sheet sản phẩm: thiếu cột mã/tên hàng"]);

        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        for (var r = headerRow + 1; r <= lastRow; r++)
        {
            var code = codeCol > 0 ? ws.Cell(r, codeCol).GetFormattedString().Trim() : "";
            var name = nameCol > 0 ? ws.Cell(r, nameCol).GetFormattedString().Trim() : "";
            if (string.IsNullOrEmpty(code) && string.IsNullOrEmpty(name)) continue;

            var printerName = printerCol > 0 ? ws.Cell(r, printerCol).GetFormattedString().Trim() : "";
            Guid? printerId = null;
            if (!string.IsNullOrEmpty(printerName))
            {
                if (!printers.TryGetValue(printerName.ToLower(), out var pid))
                {
                    errors.Add($"SP dòng {r}: không tìm thấy máy in '{printerName}'");
                    continue;
                }
                printerId = pid;
            }

            // AsTracking: DbContext NoTracking toàn cục — thiếu nó là import báo
            // «đã cập nhật N dòng» nhưng gán máy in không vào DB.
            PosProduct? product = null;
            if (!string.IsNullOrEmpty(code))
                product = await db.PosProducts.AsTracking().FirstOrDefaultAsync(p =>
                    p.StoreId == storeId && p.ProductCode == code && p.Deleted == null);
            if (product == null && !string.IsNullOrEmpty(name))
                product = await db.PosProducts.AsTracking().FirstOrDefaultAsync(p =>
                    p.StoreId == storeId && p.Name == name && p.Deleted == null);

            if (product == null)
            {
                errors.Add($"SP dòng {r}: không tìm thấy hàng '{code}/{name}'");
                continue;
            }

            product.DefaultPrinterId = printerId;
            product.UpdatedAt = DateTime.UtcNow;
            product.UpdatedBy = CurrentUserEmail;
            updated++;
        }

        return (updated, errors);
    }

    async Task<(int updated, List<string> errors)> ImportCategorySheetAsync(
        Guid storeId, IXLWorksheet ws, Dictionary<string, Guid> printers)
    {
        var updated = 0;
        var errors = new List<string>();
        var headerRow = FindHeaderRow(ws, "nhomhang", "nhóm hàng", "category", "tennhom", "tên nhóm");
        if (headerRow <= 0) return (0, []);

        var nameCol = FindCol(ws, headerRow, "nhomhang", "nhóm hàng", "tennhom", "tên nhóm", "category");
        var printerCol = FindCol(ws, headerRow, "mayin", "máy in", "printer");
        if (nameCol <= 0) return (0, ["Sheet nhóm: thiếu cột tên nhóm"]);

        var lastRow = ws.LastRowUsed()?.RowNumber() ?? headerRow;
        for (var r = headerRow + 1; r <= lastRow; r++)
        {
            var catName = ws.Cell(r, nameCol).GetFormattedString().Trim();
            if (string.IsNullOrEmpty(catName)) continue;

            var printerName = printerCol > 0 ? ws.Cell(r, printerCol).GetFormattedString().Trim() : "";
            Guid? printerId = null;
            if (!string.IsNullOrEmpty(printerName))
            {
                if (!printers.TryGetValue(printerName.ToLower(), out var pid))
                {
                    errors.Add($"NH dòng {r}: không tìm thấy máy in '{printerName}'");
                    continue;
                }
                printerId = pid;
            }

            var cat = await db.PosProductCategories.AsTracking().FirstOrDefaultAsync(c =>
                c.StoreId == storeId && c.Name == catName && c.Deleted == null);
            if (cat == null)
            {
                errors.Add($"NH dòng {r}: không tìm thấy nhóm '{catName}'");
                continue;
            }

            cat.DefaultPrinterId = printerId;
            cat.UpdatedAt = DateTime.UtcNow;
            cat.UpdatedBy = CurrentUserEmail;
            updated++;
        }

        return (updated, errors);
    }

    static int FindHeaderRow(IXLWorksheet ws, params string[] keys)
    {
        var last = Math.Min(ws.LastRowUsed()?.RowNumber() ?? 20, 20);
        for (var r = 1; r <= last; r++)
        {
            for (var c = 1; c <= 15; c++)
            {
                var h = Norm(ws.Cell(r, c).GetFormattedString());
                if (keys.Any(k => h.Contains(Norm(k), StringComparison.Ordinal)))
                    return r;
            }
        }
        return -1;
    }

    static int FindCol(IXLWorksheet ws, int headerRow, params string[] keys)
    {
        for (var c = 1; c <= 20; c++)
        {
            var h = Norm(ws.Cell(headerRow, c).GetFormattedString());
            if (keys.Any(k => h.Contains(Norm(k), StringComparison.Ordinal)))
                return c;
        }
        return -1;
    }

    static string Norm(string s) =>
        s.Trim().ToLowerInvariant().Replace(" ", "");
}
