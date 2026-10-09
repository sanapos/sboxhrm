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

/// <summary>
/// Kiểm kho theo mã: quét barcode / thẻ RFID (máy kiểm kho cầm tay, đầu đọc RFID gõ phím hoặc gửi lô mã) rồi
/// đối chiếu với sổ seri — ra máy khớp, máy thiếu, mã lạ. Hoàn thành có thể ghi nhận máy thiếu và cân bằng tồn.
/// </summary>
[ApiController]
[Route("api/pos/serial-counts")]
[Authorize]
public class PosSerialCountsController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record CreateDto(string? Name, Guid? ProductId, string? Source, string? Note);
    public record ScanDto(List<string>? Codes, string? DeviceName);
    public record CompleteDto(bool MarkMissing = true, bool AdjustStock = true, string? Note = null);
    public record BindTagDto(string? Serial, string? TagCode);
    public record BindTagsDto(List<BindTagDto>? Items);

    private Guid? Hq => ZKTecoADMS.Api.Controllers.Base.BranchScopeExtensions.BranchContext(HttpContext)?.HeadquarterBranchId;

    /// <summary>Máy dự kiến có mặt: trong kho, không đang chuyển, đúng chi nhánh đang kiểm.</summary>
    private IQueryable<PosProductSerial> ScopeQuery(PosSerialCount c) =>
        db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == c.StoreId && x.Deleted == null && x.Status == PosSerialStatus.InStock &&
                        x.TransferId == null && (c.ProductId == null || x.ProductId == c.ProductId))
            .InBranch(c.BranchId, Hq);

    private async Task<string> NextNoAsync(Guid storeId)
    {
        var prefix = $"KM{DateTime.UtcNow.AddHours(7):yyMMdd}";
        var n = await db.PosSerialCounts.IgnoreQueryFilters().CountAsync(x => x.StoreId == storeId && x.CountNo.StartsWith(prefix));
        return $"{prefix}-{n + 1:000}";
    }

    [HttpPost]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] CreateDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.ProductId.HasValue &&
            !await db.PosProducts.AnyAsync(p => p.Id == dto.ProductId && p.StoreId == storeId && p.Deleted == null))
            return BadRequest(AppResponse<object>.Fail("Hàng hóa không hợp lệ"));
        var no = await NextNoAsync(storeId);
        var source = dto.Source is "RFID" or "Manual" ? dto.Source : "Barcode";
        var c = new PosSerialCount
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CountNo = no,
            Name = string.IsNullOrWhiteSpace(dto.Name) ? $"Kiểm kho theo mã {no}" : dto.Name.Trim(),
            ProductId = dto.ProductId,
            BranchId = ZKTecoADMS.Api.Controllers.Base.BranchScopeExtensions.BranchContext(HttpContext) is { StoreUsesBranches: true } bc
                ? (bc.CurrentBranchId ?? bc.HeadquarterBranchId) : null,
            Source = source,
            StartedAt = DateTime.UtcNow,
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.PosSerialCounts.Add(c);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(await DetailAsync(c, false)));
    }

    [HttpGet]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List([FromQuery] int page = 1, [FromQuery] int pageSize = 30)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 100);
        var q = db.PosSerialCounts.AsNoTracking().Where(x => x.StoreId == storeId && x.Deleted == null);
        var total = await q.CountAsync();
        var rows = await q.OrderByDescending(x => x.StartedAt).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new
            {
                x.Id, x.CountNo, x.Name, x.Source, Status = x.Status.ToString(), x.StartedAt, x.CompletedAt,
                x.ExpectedQty, x.MatchedQty, x.MissingQty, x.UnknownQty, x.ProductId,
            }).ToListAsync();
        return Ok(AppResponse<object>.Success(new { items = rows, total, page, pageSize }));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid id)
    {
        var c = await db.PosSerialCounts.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        return Ok(AppResponse<object>.Success(await DetailAsync(c, true)));
    }

    /// <summary>Số liệu đối chiếu: dự kiến (trong kho) − đã quét khớp = thiếu; mã lạ / không còn trong kho.</summary>
    private async Task<object> DetailAsync(PosSerialCount c, bool withLists)
    {
        var items = await db.PosSerialCountItems.AsNoTracking()
            .Where(i => i.CountId == c.Id && i.Deleted == null).ToListAsync();
        var matchedIds = items.Where(i => i.Result is PosSerialScanResult.Matched).Select(i => i.SerialId!.Value).ToHashSet();

        int expected, matched, missing;
        List<object> missingList = [];
        if (c.Status == PosSerialCountStatus.InProgress)
        {
            var scope = await ScopeQuery(c).Join(db.PosProducts.AsNoTracking(), x => x.ProductId, p => p.Id,
                (x, p) => new { x.Id, x.SerialNumber, x.TagCode, ProductName = p.Name }).ToListAsync();
            expected = scope.Count;
            matched = scope.Count(s => matchedIds.Contains(s.Id));
            missing = expected - matched;
            if (withLists)
                missingList = scope.Where(s => !matchedIds.Contains(s.Id)).Take(300)
                    .Select(s => (object)new { serial = s.SerialNumber, tag = s.TagCode, productName = s.ProductName }).ToList();
        }
        else
        {
            expected = c.ExpectedQty; matched = c.MatchedQty; missing = c.MissingQty;
        }

        object lists = new { };
        if (withLists)
        {
            lists = new
            {
                unknown = items.Where(i => i.Result == PosSerialScanResult.Unknown).Select(i => i.Code).Take(300).ToList(),
                notInStock = items.Where(i => i.Result == PosSerialScanResult.NotInStock).Select(i => i.Code).Take(300).ToList(),
                outOfScope = items.Where(i => i.Result == PosSerialScanResult.OutOfScope).Select(i => i.Code).Take(300).ToList(),
                recovered = items.Where(i => i.Result == PosSerialScanResult.Recovered).Select(i => i.Code).Take(300).ToList(),
                missing = missingList,
            };
        }
        return new
        {
            c.Id, c.CountNo, c.Name, c.Source, Status = c.Status.ToString(), c.ProductId, c.StartedAt, c.CompletedAt, c.Note,
            expected, matched, missing,
            unknown = items.Count(i => i.Result == PosSerialScanResult.Unknown),
            notInStock = items.Count(i => i.Result == PosSerialScanResult.NotInStock),
            outOfScope = items.Count(i => i.Result == PosSerialScanResult.OutOfScope),
            recovered = items.Count(i => i.Result == PosSerialScanResult.Recovered),
            scanned = items.Count,
            lists,
        };
    }

    /// <summary>Quét một hoặc nhiều mã (máy kiểm kho gửi lô, hoặc nhập tay / gõ phím từ đầu đọc).</summary>
    [HttpPost("{id:guid}/scan")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Scan(Guid id, [FromBody] ScanDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await db.PosSerialCounts.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (c.Status != PosSerialCountStatus.InProgress)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã đóng — không quét thêm"));

        var codes = (dto.Codes ?? []).Select(PosSerialRegistry.Normalize).Where(x => x.Length > 0).Distinct().Take(2000).ToList();
        if (codes.Count == 0) return BadRequest(AppResponse<object>.Fail("Chưa có mã nào"));

        var already = (await db.PosSerialCountItems.AsNoTracking()
            .Where(i => i.CountId == id && i.Deleted == null && codes.Contains(i.Code))
            .Select(i => i.Code).ToListAsync()).ToHashSet();
        var fresh = codes.Where(x => !already.Contains(x)).ToList();

        var rows = await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null &&
                        (fresh.Contains(x.SerialNumber) || (x.TagCode != null && fresh.Contains(x.TagCode))))
            .ToListAsync();
        var names = await db.PosProducts.AsNoTracking()
            .Where(p => rows.Select(r => r.ProductId).Distinct().Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.Name);

        var now = DateTime.UtcNow;
        var results = new List<object>();
        var matchedSerialsThisBatch = new HashSet<Guid>();
        foreach (var code in codes)
        {
            if (already.Contains(code))
            {
                results.Add(new { code, result = "Duplicate" });
                continue;
            }
            var row = rows.Where(r => r.SerialNumber == code || r.TagCode == code)
                .OrderBy(r => r.Status == PosSerialStatus.InStock ? 0 : r.Status == PosSerialStatus.Missing ? 1 : 2)
                .FirstOrDefault();
            PosSerialScanResult res;
            if (row == null) res = PosSerialScanResult.Unknown;
            else if (c.ProductId.HasValue && row.ProductId != c.ProductId) res = PosSerialScanResult.OutOfScope;
            else if (c.BranchId.HasValue && !(row.BranchId == c.BranchId || (c.BranchId == Hq && row.BranchId == null)))
                res = PosSerialScanResult.OutOfScope;
            else if (row.Status == PosSerialStatus.InStock) res = PosSerialScanResult.Matched;
            else if (row.Status == PosSerialStatus.Missing) res = PosSerialScanResult.Recovered;
            else res = PosSerialScanResult.NotInStock;

            // Hai mã (seri + thẻ) cùng trỏ một máy trong một lô: tính một lần.
            if (row != null && res == PosSerialScanResult.Matched && !matchedSerialsThisBatch.Add(row.Id))
            {
                results.Add(new { code, result = "Duplicate" });
                continue;
            }

            db.PosSerialCountItems.Add(new PosSerialCountItem
            {
                Id = Guid.NewGuid(), StoreId = storeId, CountId = id, Code = code,
                SerialId = row?.Id, ProductId = row?.ProductId, Result = res, ScannedAt = now,
                DeviceName = dto.DeviceName?.Trim(), IsActive = true, CreatedBy = CurrentUserEmail,
            });
            results.Add(new
            {
                code, result = res.ToString(), serial = row?.SerialNumber,
                productName = row != null && names.TryGetValue(row.ProductId, out var n) ? n : null,
            });
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { results, summary = await DetailAsync(c, false) }));
    }

    /// <summary>
    /// Hoàn thành: máy thiếu → «Missing» (tuỳ chọn trừ tồn), máy quét thấy lại → về «InStock». Chốt số liệu phiếu.
    /// </summary>
    [HttpPost("{id:guid}/complete")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Complete(Guid id, [FromBody] CompleteDto dto)
    {
        var storeId = RequiredStoreId;
        await using var tx = await db.Database.BeginTransactionAsync();
        var c = await db.PosSerialCounts.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (c.Status != PosSerialCountStatus.InProgress)
            return BadRequest(AppResponse<object>.Fail("Phiếu đã đóng"));

        var items = await db.PosSerialCountItems.AsNoTracking().Where(i => i.CountId == id && i.Deleted == null).ToListAsync();
        var matchedIds = items.Where(i => i.Result == PosSerialScanResult.Matched).Select(i => i.SerialId!.Value).ToHashSet();
        var recoveredIds = items.Where(i => i.Result == PosSerialScanResult.Recovered).Select(i => i.SerialId!.Value).ToList();

        var scope = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == PosSerialStatus.InStock &&
                        x.TransferId == null && (c.ProductId == null || x.ProductId == c.ProductId))
            .InBranch(c.BranchId, Hq)
            .ToListAsync();
        var missingRows = scope.Where(s => !matchedIds.Contains(s.Id)).ToList();
        var recovered = recoveredIds.Count == 0
            ? []
            : await db.PosProductSerials.AsTracking().Where(x => recoveredIds.Contains(x.Id) && x.Status == PosSerialStatus.Missing).ToListAsync();

        c.ExpectedQty = scope.Count;
        c.MatchedQty = scope.Count - missingRows.Count;
        c.MissingQty = missingRows.Count;
        c.UnknownQty = items.Count(i => i.Result == PosSerialScanResult.Unknown);
        c.Status = PosSerialCountStatus.Completed;
        c.CompletedAt = DateTime.UtcNow;
        if (!string.IsNullOrWhiteSpace(dto.Note)) c.Note = dto.Note.Trim();
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;

        var notAdjusted = new List<string>();
        if (dto.MarkMissing)
        {
            foreach (var r in missingRows)
            {
                r.Status = PosSerialStatus.Missing;
                r.Note = $"Thiếu khi kiểm kho {c.CountNo}";
                r.UpdatedAt = DateTime.UtcNow;
                r.UpdatedBy = CurrentUserEmail;
            }
            foreach (var r in recovered)
            {
                r.Status = PosSerialStatus.InStock;
                r.Note = null;
                r.UpdatedAt = DateTime.UtcNow;
                r.UpdatedBy = CurrentUserEmail;
            }

            if (dto.AdjustStock)
            {
                var delta = missingRows.GroupBy(r => r.ProductId).ToDictionary(g => g.Key, g => -g.Count());
                foreach (var g in recovered.GroupBy(r => r.ProductId))
                    delta[g.Key] = delta.GetValueOrDefault(g.Key) + g.Count();
                var ids = delta.Keys.ToList();
                var products = await db.PosProducts.AsTracking()
                    .Where(p => ids.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null).ToDictionaryAsync(p => p.Id);
                foreach (var (pid, change) in delta)
                {
                    if (change == 0 || !products.TryGetValue(pid, out var p)) continue;
                    var hasVariant = missingRows.Concat(recovered).Any(r => r.ProductId == pid && r.VariantId != null);
                    if (hasVariant)
                    {
                        notAdjusted.Add(p.Name);
                        continue;
                    }
                    p.OnHandQty += change;
                    p.UpdatedAt = DateTime.UtcNow;
                    p.UpdatedBy = CurrentUserEmail;
                    db.PosStockTransactions.Add(new PosStockTransaction
                    {
                        Id = Guid.NewGuid(), StoreId = storeId, ProductId = p.Id,
                        TransactionType = PosStockTransactionType.Adjust,
                        QtyChange = change, QtyAfter = p.OnHandQty, UnitCost = p.CostPrice,
                        LineAmount = Math.Abs(change) * p.CostPrice,
                        ReferenceNo = c.CountNo, Note = $"Kiểm kho theo mã {c.CountNo}",
                        IsActive = true, CreatedBy = CurrentUserEmail,
                    });
                }
            }
        }

        await db.SaveChangesAsync();
        await tx.CommitAsync();
        return Ok(AppResponse<object>.Success(new
        {
            count = await DetailAsync(c, true),
            productsNotAdjusted = notAdjusted,
        }));
    }

    [HttpPost("{id:guid}/cancel")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Cancel(Guid id)
    {
        var c = await db.PosSerialCounts.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu"));
        if (c.Status != PosSerialCountStatus.InProgress)
            return BadRequest(AppResponse<object>.Fail("Chỉ hủy được phiếu đang kiểm"));
        c.Status = PosSerialCountStatus.Cancelled;
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { cancelled = true }));
    }

    // ── Gắn mã thẻ RFID / mã kiểm kho vào máy ──

    /// <summary>Tra máy theo seri hoặc mã thẻ (dùng khi quét ở màn bán / kiểm).</summary>
    [HttpGet("resolve")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosStockCounts", "PosSell", "PosPurchaseReceipts")]
    public async Task<ActionResult<AppResponse<object>>> Resolve([FromQuery] string code)
    {
        var row = await PosSerialRegistry.ResolveCodeAsync(db, RequiredStoreId, code);
        if (row == null) return Ok(AppResponse<object>.Success(new { found = false }));
        var name = await db.PosProducts.AsNoTracking().Where(p => p.Id == row.ProductId).Select(p => p.Name).FirstOrDefaultAsync();
        return Ok(AppResponse<object>.Success(new
        {
            found = true, serial = row.SerialNumber, tagCode = row.TagCode, status = row.Status.ToString(),
            productId = row.ProductId, productName = name,
        }));
    }

    /// <summary>Gắn thẻ RFID cho một loạt máy (theo seri). Mã thẻ không được trùng máy khác.</summary>
    [HttpPost("bind-tags")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> BindTags([FromBody] BindTagsDto dto)
    {
        var storeId = RequiredStoreId;
        var items = (dto.Items ?? [])
            .Select(i => (Serial: PosSerialRegistry.Normalize(i.Serial), Tag: PosSerialRegistry.Normalize(i.TagCode)))
            .Where(i => i.Serial.Length > 0 && i.Tag.Length > 0).ToList();
        if (items.Count == 0) return BadRequest(AppResponse<object>.Fail("Chưa có cặp seri – mã thẻ nào"));
        if (items.Select(i => i.Tag).Distinct().Count() != items.Count)
            return BadRequest(AppResponse<object>.Fail("Có mã thẻ bị trùng trong danh sách"));

        var serials = items.Select(i => i.Serial).ToList();
        var tags = items.Select(i => i.Tag).ToList();
        var rows = await db.PosProductSerials.AsTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null &&
                        (x.Status == PosSerialStatus.InStock || x.Status == PosSerialStatus.Sold) &&
                        serials.Contains(x.SerialNumber)).ToListAsync();
        var clash = await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.TagCode != null && tags.Contains(x.TagCode))
            .Select(x => new { x.SerialNumber, x.TagCode }).ToListAsync();

        var errors = new List<string>();
        var ok = 0;
        foreach (var (serial, tag) in items)
        {
            var row = rows.FirstOrDefault(r => r.SerialNumber == serial);
            if (row == null) { errors.Add($"{serial}: không có trong sổ"); continue; }
            if (clash.Any(k => k.TagCode == tag && k.SerialNumber != serial))
            { errors.Add($"{serial}: mã thẻ {tag} đã gắn cho máy khác"); continue; }
            row.TagCode = tag;
            row.UpdatedAt = DateTime.UtcNow;
            row.UpdatedBy = CurrentUserEmail;
            ok++;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { bound = ok, errors }));
    }
}
