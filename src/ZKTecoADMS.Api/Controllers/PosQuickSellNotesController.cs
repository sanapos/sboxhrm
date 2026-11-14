using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Sổ tay bán hàng nhanh — mỗi mục là một tên chung kèm danh sách món + số lượng.
/// Thu ngân bấm một mục là cả danh sách vào giỏ (mỗi món một dòng riêng).
/// </summary>
[ApiController]
[Route("api/pos/quick-sell-notes")]
[Authorize]
public class PosQuickSellNotesController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record QuickSellNoteItemDto(
        Guid Id,
        Guid ProductId,
        string ProductName,
        decimal Qty,
        decimal Price,
        int SortOrder);

    public record QuickSellNoteDto(
        Guid Id,
        string Name,
        string? Description,
        int SortOrder,
        List<QuickSellNoteItemDto> Items);

    public record QuickSellNoteItemInput(Guid ProductId, decimal? Qty = null, int SortOrder = 0);

    public record QuickSellNoteUpsertDto(
        string Name,
        string? Description = null,
        int SortOrder = 0,
        List<QuickSellNoteItemInput>? Items = null);

    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<QuickSellNoteDto>>>> List()
    {
        var storeId = RequiredStoreId;
        var notes = await dbContext.PosQuickSellNotes.AsNoTracking()
            .Where(n => n.StoreId == storeId && n.Deleted == null && n.IsActive)
            .OrderBy(n => n.SortOrder).ThenBy(n => n.Name)
            .ToListAsync();
        if (notes.Count == 0)
            return Ok(AppResponse<List<QuickSellNoteDto>>.Success([]));

        var noteIds = notes.Select(n => n.Id).ToList();
        var items = await dbContext.PosQuickSellNoteItems.AsNoTracking()
            .Include(i => i.Product)
            // Món đã xóa khỏi danh mục thì bỏ qua — sổ tay cũ không làm hỏng màn bán.
            .Where(i => noteIds.Contains(i.NoteId) && i.StoreId == storeId &&
                        i.Deleted == null && i.IsActive &&
                        i.Product != null && i.Product.Deleted == null)
            .OrderBy(i => i.SortOrder)
            .ToListAsync();
        var byNote = items.GroupBy(i => i.NoteId).ToDictionary(g => g.Key, g => g.ToList());

        var result = notes.Select(n => MapNote(n, byNote.GetValueOrDefault(n.Id) ?? [])).ToList();
        return Ok(AppResponse<List<QuickSellNoteDto>>.Success(result));
    }

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<QuickSellNoteDto>>> Create(
        [FromBody] QuickSellNoteUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<QuickSellNoteDto>.Fail("Tên sổ tay bắt buộc"));

        var entity = new PosQuickSellNote
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            Description = Trimmed(dto.Description),
            SortOrder = dto.SortOrder,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosQuickSellNotes.Add(entity);
        await dbContext.SaveChangesAsync();
        await SyncItemsAsync(storeId, entity.Id, dto.Items);
        return Ok(AppResponse<QuickSellNoteDto>.Success(await LoadNoteAsync(storeId, entity.Id)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<QuickSellNoteDto>>> Update(
        Guid id, [FromBody] QuickSellNoteUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        // Context mặc định NoTracking — sửa entity phải AsTracking thì SaveChanges mới ghi.
        var entity = await dbContext.PosQuickSellNotes.AsTracking()
            .FirstOrDefaultAsync(n => n.Id == id && n.StoreId == storeId && n.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<QuickSellNoteDto>.Fail("Không tìm thấy sổ tay"));

        var name = (dto.Name ?? "").Trim();
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<QuickSellNoteDto>.Fail("Tên sổ tay bắt buộc"));

        entity.Name = name;
        entity.Description = Trimmed(dto.Description);
        entity.SortOrder = dto.SortOrder;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        await SyncItemsAsync(storeId, entity.Id, dto.Items);
        return Ok(AppResponse<QuickSellNoteDto>.Success(await LoadNoteAsync(storeId, entity.Id)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await dbContext.PosQuickSellNotes.AsTracking()
            .FirstOrDefaultAsync(n => n.Id == id && n.StoreId == storeId && n.Deleted == null);
        if (entity == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy sổ tay"));

        var now = DateTime.UtcNow;
        entity.Deleted = now;
        entity.DeletedBy = CurrentUserEmail;
        entity.IsActive = false;

        var items = await dbContext.PosQuickSellNoteItems.AsTracking()
            .Where(i => i.NoteId == id && i.StoreId == storeId && i.Deleted == null)
            .ToListAsync();
        foreach (var i in items)
        {
            i.Deleted = now;
            i.DeletedBy = CurrentUserEmail;
            i.IsActive = false;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    private static string? Trimmed(string? s)
    {
        var t = (s ?? "").Trim();
        return t.Length == 0 ? null : t;
    }

    private static QuickSellNoteDto MapNote(PosQuickSellNote n, List<PosQuickSellNoteItem> items) =>
        new(
            n.Id,
            n.Name,
            n.Description,
            n.SortOrder,
            items.Select(i => new QuickSellNoteItemDto(
                i.Id,
                i.ProductId,
                i.Product?.Name ?? "",
                i.Qty,
                i.Product?.BasePrice ?? 0,
                i.SortOrder)).ToList());

    private async Task<QuickSellNoteDto> LoadNoteAsync(Guid storeId, Guid noteId)
    {
        var note = await dbContext.PosQuickSellNotes.AsNoTracking()
            .FirstAsync(n => n.Id == noteId && n.StoreId == storeId);
        var items = await dbContext.PosQuickSellNoteItems.AsNoTracking()
            .Include(i => i.Product)
            .Where(i => i.NoteId == noteId && i.StoreId == storeId &&
                        i.Deleted == null && i.IsActive &&
                        i.Product != null && i.Product.Deleted == null)
            .OrderBy(i => i.SortOrder)
            .ToListAsync();
        return MapNote(note, items);
    }

    private async Task SyncItemsAsync(Guid storeId, Guid noteId, List<QuickSellNoteItemInput>? items)
    {
        var existing = await dbContext.PosQuickSellNoteItems.AsTracking()
            .Where(i => i.NoteId == noteId && i.StoreId == storeId && i.Deleted == null)
            .ToListAsync();

        if (items == null || items.Count == 0)
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

        var wantIds = items.Select(i => i.ProductId).Distinct().ToList();
        var validSet = (await dbContext.PosProducts.AsNoTracking()
            .Where(p => wantIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.Id)
            .ToListAsync()).ToHashSet();

        var keep = new HashSet<Guid>();
        var sort = 0;
        foreach (var input in items)
        {
            if (!validSet.Contains(input.ProductId)) continue;
            // Cùng một món gửi 2 lần: giữ dòng đầu, không tạo dòng trùng.
            if (!keep.Add(input.ProductId)) continue;
            var qty = input.Qty is > 0 ? input.Qty.Value : 1;
            var order = input.SortOrder != 0 ? input.SortOrder : sort;
            var row = existing.FirstOrDefault(e => e.ProductId == input.ProductId);
            if (row == null)
            {
                dbContext.PosQuickSellNoteItems.Add(new PosQuickSellNoteItem
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    NoteId = noteId,
                    ProductId = input.ProductId,
                    Qty = qty,
                    SortOrder = order,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                });
            }
            else
            {
                row.Qty = qty;
                row.SortOrder = order;
                row.IsActive = true;
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = CurrentUserEmail;
            }
            sort++;
        }

        foreach (var e in existing.Where(e => !keep.Contains(e.ProductId)))
        {
            e.Deleted = DateTime.UtcNow;
            e.DeletedBy = CurrentUserEmail;
            e.IsActive = false;
        }

        await dbContext.SaveChangesAsync();
    }
}
