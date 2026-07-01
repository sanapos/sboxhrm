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
[Route("api/pos/print-templates")]
[Authorize]
public class PosPrintTemplatesController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record PrintTemplateDto(
        Guid Id,
        string Name,
        string DocumentType,
        string PaperSize,
        string HtmlContent,
        bool IsDefault,
        bool IsActive,
        int SortOrder,
        DateTime CreatedAt,
        DateTime? UpdatedAt);

    public record PrintTemplateSaveDto(
        string Name,
        PosPrintDocumentType DocumentType,
        PosPrintPaperSize PaperSize,
        string HtmlContent,
        bool IsDefault,
        bool IsActive,
        int SortOrder);

    public record PrintTemplatePresetDto(
        string PaperSize,
        string Name,
        string HtmlContent);

    static PrintTemplateDto ToDto(PosPrintTemplate t) => new(
        t.Id, t.Name, t.DocumentType.ToString(), t.PaperSize.ToString(),
        t.HtmlContent, t.IsDefault, t.IsActive, t.SortOrder,
        t.CreatedAt, t.UpdatedAt);

    [HttpGet]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] PosPrintDocumentType? documentType,
        [FromQuery] bool? activeOnly)
    {
        var storeId = RequiredStoreId;
        await EnsureDefaultsAsync(storeId, documentType ?? PosPrintDocumentType.SaleInvoice);

        var query = dbContext.PosPrintTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null);
        if (documentType.HasValue)
            query = query.Where(t => t.DocumentType == documentType.Value);
        if (activeOnly != false)
            query = query.Where(t => t.IsActive);

        var items = await query
            .OrderBy(t => t.DocumentType)
            .ThenBy(t => t.SortOrder)
            .ThenBy(t => t.Name)
            .Select(t => ToDto(t))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var t = await dbContext.PosPrintTemplates.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (t == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu in"));
        return Ok(AppResponse<object>.Success(ToDto(t)));
    }

    [HttpGet("presets")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> Presets(
        [FromQuery] PosPrintDocumentType documentType = PosPrintDocumentType.SaleInvoice)
    {
        var presets = Enum.GetValues<PosPrintPaperSize>()
            .Select(s => new PrintTemplatePresetDto(
                s.ToString(),
                PosPrintTemplateDefaults.TemplateName(s),
                PosPrintTemplateDefaults.BuildHtml(documentType, s)))
            .ToList();
        return Ok(AppResponse<object>.Success(presets));
    }

    [HttpPost]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] PrintTemplateSaveDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name))
            return BadRequest(AppResponse<object>.Fail("Tên mẫu in không được trống"));
        if (string.IsNullOrWhiteSpace(dto.HtmlContent))
            return BadRequest(AppResponse<object>.Fail("Nội dung mẫu in không được trống"));

        var storeId = RequiredStoreId;
        var now = DateTime.UtcNow;
        var entity = new PosPrintTemplate
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = dto.Name.Trim(),
            DocumentType = dto.DocumentType,
            PaperSize = dto.PaperSize,
            HtmlContent = dto.HtmlContent,
            IsDefault = dto.IsDefault,
            IsActive = dto.IsActive,
            SortOrder = dto.SortOrder,
            CreatedAt = now,
            CreatedBy = CurrentUserEmail,
        };

        if (dto.IsDefault)
            await ClearDefaultAsync(storeId, dto.DocumentType, null);

        dbContext.PosPrintTemplates.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(ToDto(entity)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Update(Guid id, [FromBody] PrintTemplateSaveDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name))
            return BadRequest(AppResponse<object>.Fail("Tên mẫu in không được trống"));
        if (string.IsNullOrWhiteSpace(dto.HtmlContent))
            return BadRequest(AppResponse<object>.Fail("Nội dung mẫu in không được trống"));

        var storeId = RequiredStoreId;
        var entity = await dbContext.PosPrintTemplates
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId && t.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu in"));

        if (dto.IsDefault)
            await ClearDefaultAsync(storeId, dto.DocumentType, id);

        entity.Name = dto.Name.Trim();
        entity.DocumentType = dto.DocumentType;
        entity.PaperSize = dto.PaperSize;
        entity.HtmlContent = dto.HtmlContent;
        entity.IsDefault = dto.IsDefault;
        entity.IsActive = dto.IsActive;
        entity.SortOrder = dto.SortOrder;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(ToDto(entity)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosPrintTemplates
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId && t.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu in"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;
        entity.IsDefault = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(null));
    }

    [HttpPost("seed")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Seed(
        [FromQuery] PosPrintDocumentType documentType = PosPrintDocumentType.SaleInvoice)
    {
        var storeId = RequiredStoreId;
        var created = await EnsureDefaultsAsync(storeId, documentType, force: true);
        return Ok(AppResponse<object>.Success(new { created }));
    }

    async Task<int> EnsureDefaultsAsync(Guid storeId, PosPrintDocumentType documentType, bool force = false)
    {
        var exists = await dbContext.PosPrintTemplates.AnyAsync(t =>
            t.StoreId == storeId && t.DocumentType == documentType && t.Deleted == null);
        if (exists && !force) return 0;

        if (force)
        {
            var old = await dbContext.PosPrintTemplates
                .Where(t => t.StoreId == storeId && t.DocumentType == documentType && t.Deleted == null)
                .ToListAsync();
            foreach (var t in old)
            {
                t.Deleted = DateTime.UtcNow;
                t.IsActive = false;
                t.IsDefault = false;
            }
        }

        var now = DateTime.UtcNow;
        var sort = 0;
        var created = 0;
        foreach (PosPrintPaperSize size in Enum.GetValues<PosPrintPaperSize>())
        {
            dbContext.PosPrintTemplates.Add(new PosPrintTemplate
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Name = PosPrintTemplateDefaults.TemplateName(size),
                DocumentType = documentType,
                PaperSize = size,
                HtmlContent = PosPrintTemplateDefaults.BuildHtml(documentType, size),
                IsDefault = size == PosPrintPaperSize.K80,
                IsActive = true,
                SortOrder = sort++,
                CreatedAt = now,
                CreatedBy = "system",
            });
            created++;
        }

        if (created > 0)
            await dbContext.SaveChangesAsync();
        return created;
    }

    async Task ClearDefaultAsync(Guid storeId, PosPrintDocumentType docType, Guid? exceptId)
    {
        var q = dbContext.PosPrintTemplates.Where(t =>
            t.StoreId == storeId && t.DocumentType == docType && t.IsDefault && t.Deleted == null);
        if (exceptId.HasValue)
            q = q.Where(t => t.Id != exceptId.Value);
        var list = await q.ToListAsync();
        foreach (var t in list) t.IsDefault = false;
    }
}
