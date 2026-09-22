using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosQuotesController
{
    [HttpGet("{id:guid}/export/excel")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<IActionResult> ExportExcel(Guid id, [FromQuery] bool includeImages = false)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound();
        var profile = await dbContext.PosStoreCommercialProfiles.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        var bytes = PosQuoteExportService.BuildExcel(quote, profile);
        var name = $"BaoGia_{quote.QuoteNo}.xlsx";
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", name);
    }

    [HttpGet("{id:guid}/export/word")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<IActionResult> ExportWord(Guid id, [FromQuery] bool includeImages = false)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound();
        var html = await PosQuoteDocumentHtml.BuildAsync(
            dbContext, quote, PosQuoteDocumentKind.Quote, quote.QuoteNo, quote.Note,
            includeImages, webHostEnvironment.ContentRootPath);
        var bytes = PosQuoteExportService.BuildWordHtml(html, $"Báo giá {quote.QuoteNo}");
        var name = $"BaoGia_{quote.QuoteNo}.doc";
        return File(bytes, "application/msword", name);
    }

    [HttpGet("{id:guid}/export/html")]
    [RequireModulePermission("PosQuotes", ModulePermissionAction.View)]
    public async Task<IActionResult> ExportHtml(Guid id, [FromQuery] bool includeImages = false)
    {
        var storeId = RequiredStoreId;
        var quote = await LoadQuote(storeId, id);
        if (quote == null || !OwnsOrManages(quote))
            return NotFound();
        var html = await PosQuoteDocumentHtml.BuildAsync(
            dbContext, quote, PosQuoteDocumentKind.Quote, quote.QuoteNo, quote.Note,
            includeImages, webHostEnvironment.ContentRootPath);
        return Content(html, "text/html; charset=utf-8");
    }
}
