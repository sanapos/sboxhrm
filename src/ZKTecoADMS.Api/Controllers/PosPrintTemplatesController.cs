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
        DateTime? UpdatedAt,
        Guid? SourceCatalogId = null);

    public record PrintTemplateCatalogDto(
        Guid Id,
        string Name,
        string DocumentType,
        string PaperSize,
        string HtmlContent,
        bool IsRecommended,
        bool IsActive,
        int SortOrder);

    public record PrintTemplateSaveDto(
        string Name,
        PosPrintDocumentType DocumentType,
        PosPrintPaperSize PaperSize,
        string HtmlContent,
        bool IsDefault,
        bool IsActive,
        int SortOrder);

    public record AdoptCatalogDto(bool SetAsDefault = true);

    public record PrintTemplatePresetDto(
        string PaperSize,
        string Name,
        string HtmlContent);

    static PrintTemplateDto ToDto(PosPrintTemplate t) => new(
        t.Id, t.Name, t.DocumentType.ToString(), t.PaperSize.ToString(),
        t.HtmlContent, t.IsDefault, t.IsActive, t.SortOrder,
        t.CreatedAt, t.UpdatedAt, t.SourceCatalogId);

    static PrintTemplateCatalogDto ToCatalogDto(PosPrintTemplateCatalog t) => new(
        t.Id, t.Name, t.DocumentType.ToString(), t.PaperSize.ToString(),
        t.HtmlContent, t.IsRecommended, t.IsActive, t.SortOrder);

    /// <summary>Mẫu của cửa hàng (đã clone / tự soạn) — sửa chỉ ảnh hưởng store này.</summary>
    [HttpGet]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] PosPrintDocumentType? documentType,
        [FromQuery] bool? activeOnly)
    {
        var storeId = RequiredStoreId;
        await EnsureCatalogSeededAsync(documentType ?? PosPrintDocumentType.SaleInvoice);

        // Không còn auto-seed 4 khổ vào store — cửa hàng chọn từ catalog.
        // Nếu store chưa có mẫu: clone sẵn mẫu recommended (1 lần) để in không bị trống.
        if (documentType.HasValue)
            await EnsureStoreHasAtLeastOneAsync(storeId, documentType.Value);

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

    /// <summary>Mẫu chung (1–3 / loại) — chỉ đọc khi chọn; sửa catalog không qua API store.</summary>
    [HttpGet("catalog")]
    [RequireModulePermission("PosPrintTemplates", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListCatalog(
        [FromQuery] PosPrintDocumentType documentType = PosPrintDocumentType.SaleInvoice)
    {
        await EnsureCatalogSeededAsync(documentType);
        var items = await dbContext.PosPrintTemplateCatalogs.AsNoTracking()
            .Where(t => t.DocumentType == documentType && t.Deleted == null && t.IsActive)
            .OrderBy(t => t.SortOrder)
            .ThenBy(t => t.Name)
            .Select(t => ToCatalogDto(t))
            .ToListAsync();
        return Ok(AppResponse<object>.Success(items));
    }

    /// <summary>Clone mẫu chung → bản cửa hàng (có thể đặt mặc định toàn store).</summary>
    [HttpPost("catalog/{catalogId:guid}/adopt")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> AdoptCatalog(
        Guid catalogId, [FromBody] AdoptCatalogDto? dto)
    {
        var storeId = RequiredStoreId;
        var setDefault = dto?.SetAsDefault ?? true;
        var catalog = await dbContext.PosPrintTemplateCatalogs.AsNoTracking()
            .FirstOrDefaultAsync(t => t.Id == catalogId && t.Deleted == null && t.IsActive);
        if (catalog == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu chung"));

        // Đã adopt cùng catalog → trả bản hiện có (hoặc tạo bản mới nếu user muốn nhiều bản chỉnh).
        var existing = await dbContext.PosPrintTemplates.AsTracking()
            .FirstOrDefaultAsync(t =>
                t.StoreId == storeId &&
                t.SourceCatalogId == catalogId &&
                t.Deleted == null);
        if (existing != null)
        {
            if (setDefault && !existing.IsDefault)
            {
                await ClearDefaultAsync(storeId, catalog.DocumentType, existing.Id);
                existing.IsDefault = true;
                existing.UpdatedAt = DateTime.UtcNow;
                existing.UpdatedBy = CurrentUserEmail;
                await dbContext.SaveChangesAsync();
            }
            return Ok(AppResponse<object>.Success(ToDto(existing)));
        }

        var now = DateTime.UtcNow;
        var entity = new PosPrintTemplate
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = catalog.Name,
            DocumentType = catalog.DocumentType,
            PaperSize = catalog.PaperSize,
            HtmlContent = catalog.HtmlContent,
            IsDefault = setDefault,
            IsActive = true,
            SortOrder = catalog.SortOrder,
            SourceCatalogId = catalog.Id,
            CreatedAt = now,
            CreatedBy = CurrentUserEmail,
        };
        if (setDefault)
            await ClearDefaultAsync(storeId, catalog.DocumentType, null);

        dbContext.PosPrintTemplates.Add(entity);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(ToDto(entity)));
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
        var presets = PosPrintTemplateDefaults.CatalogSpecs(documentType)
            .Select(s => new PrintTemplatePresetDto(
                s.PaperSize.ToString(),
                s.Name,
                PosPrintTemplateDefaults.BuildHtml(documentType, s.PaperSize)))
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
        var entity = await dbContext.PosPrintTemplates.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId && t.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu in"));

        if (dto.IsDefault)
            await ClearDefaultAsync(storeId, dto.DocumentType, id);

        // Chỉ sửa bản cửa hàng — không đụng catalog / store khác.
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

    [HttpPost("{id:guid}/set-default")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SetDefault(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosPrintTemplates.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == storeId && t.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy mẫu in"));

        await ClearDefaultAsync(storeId, entity.DocumentType, id);
        entity.IsDefault = true;
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
        var entity = await dbContext.PosPrintTemplates.AsTracking()
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
        await EnsureCatalogSeededAsync(documentType);
        var adopted = await EnsureStoreHasAtLeastOneAsync(storeId, documentType);
        return Ok(AppResponse<object>.Success(new { created = adopted ? 1 : 0 }));
    }

    async Task EnsureCatalogSeededAsync(PosPrintDocumentType documentType)
    {
        var specs = PosPrintTemplateDefaults.CatalogSpecs(documentType);
        var existing = await dbContext.PosPrintTemplateCatalogs
            .Where(t => t.DocumentType == documentType && t.Deleted == null)
            .ToListAsync();
        var byName = existing.ToDictionary(t => t.Name, StringComparer.OrdinalIgnoreCase);

        var now = DateTime.UtcNow;
        var created = 0;
        var updated = 0;
        foreach (var spec in specs)
        {
            var html = PosPrintTemplateDefaults.BuildHtml(documentType, spec.PaperSize);
            if (byName.TryGetValue(spec.Name, out var row))
            {
                // Làm mới mẫu catalog (layout gọn) — store đã custom vẫn giữ Html riêng.
                if (!string.Equals(row.HtmlContent, html, StringComparison.Ordinal))
                {
                    row.HtmlContent = html;
                    row.UpdatedAt = now;
                    row.UpdatedBy = "system";
                    updated++;
                }
                continue;
            }
            dbContext.PosPrintTemplateCatalogs.Add(new PosPrintTemplateCatalog
            {
                Id = Guid.NewGuid(),
                Name = spec.Name,
                DocumentType = documentType,
                PaperSize = spec.PaperSize,
                HtmlContent = html,
                IsRecommended = spec.IsRecommended,
                IsActive = true,
                SortOrder = spec.SortOrder,
                CreatedAt = now,
                CreatedBy = "system",
            });
            created++;
        }
        if (created > 0 || updated > 0)
            await dbContext.SaveChangesAsync();

        // Đồng bộ store template chưa sửa tay (còn gắn SourceCatalogId + trùng tên catalog).
        if (updated > 0)
        {
            var catalogIds = existing.Select(c => c.Id).ToList();
            var storeRows = await dbContext.PosPrintTemplates
                .Where(t => t.DocumentType == documentType
                    && t.Deleted == null
                    && t.SourceCatalogId != null
                    && catalogIds.Contains(t.SourceCatalogId.Value))
                .ToListAsync();
            var catalogById = existing.ToDictionary(c => c.Id);
            var storeTouched = 0;
            foreach (var st in storeRows)
            {
                if (!catalogById.TryGetValue(st.SourceCatalogId!.Value, out var cat)) continue;
                if (string.Equals(st.HtmlContent, cat.HtmlContent, StringComparison.Ordinal)) continue;
                st.HtmlContent = cat.HtmlContent;
                st.UpdatedAt = now;
                st.UpdatedBy = "system";
                storeTouched++;
            }
            if (storeTouched > 0)
                await dbContext.SaveChangesAsync();
        }
    }

    async Task<bool> EnsureStoreHasAtLeastOneAsync(Guid storeId, PosPrintDocumentType documentType)
    {
        var hasAny = await dbContext.PosPrintTemplates.AsNoTracking()
            .AnyAsync(t => t.StoreId == storeId && t.DocumentType == documentType && t.Deleted == null && t.IsActive);
        if (hasAny) return false;

        await EnsureCatalogSeededAsync(documentType);
        var catalog = await dbContext.PosPrintTemplateCatalogs.AsNoTracking()
            .Where(t => t.DocumentType == documentType && t.Deleted == null && t.IsActive)
            .OrderByDescending(t => t.IsRecommended)
            .ThenBy(t => t.SortOrder)
            .FirstOrDefaultAsync();
        if (catalog == null) return false;

        var now = DateTime.UtcNow;
        dbContext.PosPrintTemplates.Add(new PosPrintTemplate
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = catalog.Name,
            DocumentType = catalog.DocumentType,
            PaperSize = catalog.PaperSize,
            HtmlContent = catalog.HtmlContent,
            IsDefault = true,
            IsActive = true,
            SortOrder = 0,
            SourceCatalogId = catalog.Id,
            CreatedAt = now,
            CreatedBy = "system",
        });
        await dbContext.SaveChangesAsync();
        return true;
    }

    async Task ClearDefaultAsync(Guid storeId, PosPrintDocumentType docType, Guid? exceptId)
    {
        var q = dbContext.PosPrintTemplates.AsTracking().Where(t =>
            t.StoreId == storeId && t.DocumentType == docType && t.IsDefault && t.Deleted == null);
        if (exceptId.HasValue)
            q = q.Where(t => t.Id != exceptId.Value);
        var list = await q.ToListAsync();
        foreach (var t in list) t.IsDefault = false;
    }
}
