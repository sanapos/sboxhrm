using ZKTecoADMS.Application.Helpers;
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
[Route("api/pos/warranty")]
[Authorize]
public class PosWarrantyController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record WarrantyRegistrationDto(
        Guid Id,
        string SerialNumber,
        string? Imei,
        int WarrantyMonths,
        DateTime SaleDate,
        DateTime WarrantyExpiry,
        string Status,
        string ProductName,
        string? ProductCode,
        string? CustomerName,
        string? CustomerPhone,
        string OrderNo,
        Guid SaleOrderId,
        Guid ProductId,
        Guid? VariantId,
        string? Note,
        int ClaimCount = 0);

    [HttpGet("lookup")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Lookup(
        [FromQuery] string? serial,
        [FromQuery] string? phone,
        [FromQuery] string? orderNo)
    {
        var storeId = RequiredStoreId;
        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (!string.IsNullOrWhiteSpace(serial))
        {
            var s = PosSaleWarrantyHelper.NormalizeSerial(serial);
            q = q.Where(r => r.SerialNumber.ToUpper() == s || (r.Imei != null && r.Imei.ToUpper() == s));
        }
        else if (!string.IsNullOrWhiteSpace(phone))
        {
            var p = new string(phone.Where(char.IsDigit).ToArray());
            if (p.StartsWith("84") && p.Length > 9) p = "0" + p[2..];
            if (p.Length < 3)
                return BadRequest(AppResponse<object>.Fail("Nhập ít nhất 3 số của SĐT"));
            q = q.Where(r => r.Customer != null && r.Customer.Phone != null &&
                             r.Customer.Phone.Replace(" ", "").Replace(".", "").Replace("-", "").Contains(p));
        }
        else if (!string.IsNullOrWhiteSpace(orderNo))
        {
            var o = orderNo.Trim();
            q = q.Where(r => r.SaleOrder != null && r.SaleOrder.OrderNo == o);
        }
        else
        {
            return BadRequest(AppResponse<object>.Fail("Nhập seri, SĐT khách hoặc mã đơn"));
        }

        var rows = await q.OrderByDescending(r => r.SaleDate).Take(50).ToListAsync();
        var counts = await ClaimCountsAsync(storeId, rows.Select(r => r.Id));
        var items = rows.Select(r => MapDto(r) with { ClaimCount = counts.GetValueOrDefault(r.Id) }).ToList();

        return Ok(AppResponse<object>.Success(new { items, count = items.Count }));
    }

    [HttpGet("expiring")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Expiring(
        [FromQuery] int days = 30,
        [FromQuery] bool includeExpired = false)
    {
        var storeId = RequiredStoreId;
        days = Math.Clamp(days, 1, 365);
        var now = DateTime.UtcNow;
        var until = now.AddDays(days);

        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosWarrantyStatus.Active && r.WarrantyMonths > 0);

        if (includeExpired)
            q = q.Where(r => r.WarrantyExpiry <= until);
        else
            q = q.Where(r => r.WarrantyExpiry >= now && r.WarrantyExpiry <= until);

        var rows = await q.OrderBy(r => r.WarrantyExpiry).Take(200).ToListAsync();
        var items = rows.Select(MapDto).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            days,
            includeExpired,
            expiringSoonCount = items.Count,
            items,
        }));
    }

    [HttpGet]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var q = dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            q = q.Where(r =>
                VnSearch.Has(r.SerialNumber, s) ||
                (r.Imei != null && VnSearch.Has(r.Imei, s)) ||
                (r.Product != null && VnSearch.Has(r.Product.Name, s)) ||
                (r.SaleOrder != null && VnSearch.Has(r.SaleOrder.OrderNo, s)) ||
                (r.Customer != null && VnSearch.Has(r.Customer.Name, s)));
        }

        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosWarrantyStatus>(status, true, out var st))
        {
            q = q.Where(r => r.Status == st);
        }

        var total = await q.CountAsync();
        var rows = await q
            .OrderByDescending(r => r.SaleDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();
        var items = rows.Select(MapDto).ToList();

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    private async Task<Dictionary<Guid, int>> ClaimCountsAsync(Guid storeId, IEnumerable<Guid> regIds)
    {
        var ids = regIds.ToList();
        if (ids.Count == 0) return [];
        return await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && ids.Contains(c.RegistrationId))
            .GroupBy(c => c.RegistrationId)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);
    }

    public record ClaimDto(
        Guid Id, Guid RegistrationId, string ClaimType, string Status, DateTime ReceivedDate,
        DateTime? ResolvedDate, bool InWarranty, string? Description, string? Resolution,
        Guid? NewRegistrationId, string? CreatedBy);

    private static ClaimDto MapClaim(PosWarrantyClaim c) =>
        new(c.Id, c.RegistrationId, c.ClaimType.ToString(), c.Status.ToString(), c.ReceivedDate,
            c.ResolvedDate, c.InWarranty, c.Description, c.Resolution, c.NewRegistrationId, c.CreatedBy);

    /// <summary>Lịch sử bảo hành của một máy (seri).</summary>
    [HttpGet("{id:guid}/claims")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetClaims(Guid id)
    {
        var storeId = RequiredStoreId;
        var exists = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (!exists) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy"));

        var rows = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.RegistrationId == id && c.Deleted == null)
            .OrderByDescending(c => c.ReceivedDate)
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { items = rows.Select(MapClaim).ToList() }));
    }

    public record CreateClaimDto(string? ClaimType, string? Description);

    /// <summary>Tiếp nhận bảo hành / sửa chữa (hoặc ghi chú) cho một máy. Hết hạn vẫn nhận nhưng đánh dấu tính phí.</summary>
    [HttpPost("{id:guid}/claims")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ClaimDto>>> CreateClaim(Guid id, [FromBody] CreateClaimDto dto)
    {
        var storeId = RequiredStoreId;
        var reg = await dbContext.PosProductWarrantyRegistrations.AsTracking()
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (reg == null) return NotFound(AppResponse<ClaimDto>.Fail("Không tìm thấy máy"));
        if (reg.Status != PosWarrantyStatus.Active)
            return BadRequest(AppResponse<ClaimDto>.Fail("Máy này không còn ở trạng thái bảo hành (đã trả / hủy / đã đổi)"));

        var type = Enum.TryParse<PosWarrantyClaimType>(dto.ClaimType, true, out var t) ? t : PosWarrantyClaimType.Repair;
        if (type == PosWarrantyClaimType.Replace)
            return BadRequest(AppResponse<ClaimDto>.Fail("Dùng chức năng «Đổi máy» để đổi seri"));
        if (string.IsNullOrWhiteSpace(dto.Description))
            return BadRequest(AppResponse<ClaimDto>.Fail("Nhập mô tả lỗi / nội dung tiếp nhận"));

        var now = DateTime.UtcNow;
        var claim = new PosWarrantyClaim
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            RegistrationId = reg.Id,
            ClaimType = type,
            Status = type == PosWarrantyClaimType.Note ? PosWarrantyClaimStatus.Done : PosWarrantyClaimStatus.Received,
            ReceivedDate = now,
            ResolvedDate = type == PosWarrantyClaimType.Note ? now : null,
            InWarranty = reg.WarrantyMonths > 0 && reg.WarrantyExpiry >= now,
            Description = dto.Description.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosWarrantyClaims.Add(claim);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ClaimDto>.Success(MapClaim(claim)));
    }

    public record UpdateClaimDto(string? Status, string? Resolution);

    /// <summary>Cập nhật tiến độ xử lý: đang xử lý / hoàn tất / từ chối + kết quả.</summary>
    [HttpPost("claims/{claimId:guid}")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ClaimDto>>> UpdateClaim(Guid claimId, [FromBody] UpdateClaimDto dto)
    {
        var storeId = RequiredStoreId;
        var claim = await dbContext.PosWarrantyClaims.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == claimId && c.StoreId == storeId && c.Deleted == null);
        if (claim == null) return NotFound(AppResponse<ClaimDto>.Fail("Không tìm thấy phiếu bảo hành"));
        if (!Enum.TryParse<PosWarrantyClaimStatus>(dto.Status, true, out var st))
            return BadRequest(AppResponse<ClaimDto>.Fail("Trạng thái không hợp lệ"));
        if (claim.ClaimType == PosWarrantyClaimType.Replace)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đổi máy đã hoàn tất, không sửa"));
        if (claim.Status is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đã đóng"));

        var closing = st is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected;
        if (closing && string.IsNullOrWhiteSpace(dto.Resolution))
            return BadRequest(AppResponse<ClaimDto>.Fail("Nhập kết quả xử lý khi đóng phiếu"));

        claim.Status = st;
        if (!string.IsNullOrWhiteSpace(dto.Resolution)) claim.Resolution = dto.Resolution.Trim();
        if (closing) claim.ResolvedDate = DateTime.UtcNow;
        claim.UpdatedAt = DateTime.UtcNow;
        claim.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ClaimDto>.Success(MapClaim(claim)));
    }

    public record ReplaceDto(string? NewSerial, string? NewImei, string? Description);

    /// <summary>
    /// Đổi máy bảo hành: seri cũ → «Replaced», seri mới thừa hưởng thời hạn bảo hành còn lại của máy cũ
    /// (không gia hạn). Chỉ đổi khi máy còn hạn bảo hành.
    /// </summary>
    [HttpPost("{id:guid}/replace")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Replace(Guid id, [FromBody] ReplaceDto dto)
    {
        var storeId = RequiredStoreId;
        var newSerial = PosSaleWarrantyHelper.NormalizeSerial(dto.NewSerial);
        if (newSerial.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Nhập seri máy mới"));
        if (string.IsNullOrWhiteSpace(dto.Description))
            return BadRequest(AppResponse<object>.Fail("Nhập lý do đổi máy"));

        await using var tx = await dbContext.Database.BeginTransactionAsync();
        var old = await dbContext.PosProductWarrantyRegistrations.AsTracking()
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (old == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy"));
        if (old.Status != PosWarrantyStatus.Active)
            return BadRequest(AppResponse<object>.Fail("Máy này không còn ở trạng thái bảo hành"));

        var now = DateTime.UtcNow;
        if (old.WarrantyMonths <= 0 || old.WarrantyExpiry < now)
            return BadRequest(AppResponse<object>.Fail("Máy đã hết hạn bảo hành — không đổi máy miễn phí"));
        if (PosSaleWarrantyHelper.NormalizeSerial(old.SerialNumber) == newSerial)
            return BadRequest(AppResponse<object>.Fail("Seri mới trùng seri cũ"));

        var taken = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .AnyAsync(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosWarrantyStatus.Active
                           && r.SerialNumber.ToUpper() == newSerial);
        if (taken)
            return BadRequest(AppResponse<object>.Fail($"Seri {newSerial} đã được đăng ký bảo hành"));

        var serialErr = await PosSerialRegistry.ReplaceAsync(
            dbContext, storeId, old.SaleOrderId, old.ProductId, old.SerialNumber, newSerial, CurrentUserEmail);
        if (serialErr != null)
            return BadRequest(AppResponse<object>.Fail(serialErr));

        old.Status = PosWarrantyStatus.Replaced;
        old.UpdatedAt = now;
        old.UpdatedBy = CurrentUserEmail;

        var fresh = new PosProductWarrantyRegistration
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = old.SaleOrderId,
            SaleOrderLineId = old.SaleOrderLineId,
            ProductId = old.ProductId,
            VariantId = old.VariantId,
            CustomerId = old.CustomerId,
            SerialNumber = newSerial,
            Imei = string.IsNullOrWhiteSpace(dto.NewImei) ? null : dto.NewImei.Trim(),
            WarrantyMonths = old.WarrantyMonths,
            SaleDate = old.SaleDate,
            WarrantyExpiry = old.WarrantyExpiry,
            Status = PosWarrantyStatus.Active,
            Note = $"Đổi từ seri {old.SerialNumber}",
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosProductWarrantyRegistrations.Add(fresh);
        dbContext.PosWarrantyClaims.Add(new PosWarrantyClaim
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            RegistrationId = old.Id,
            ClaimType = PosWarrantyClaimType.Replace,
            Status = PosWarrantyClaimStatus.Done,
            ReceivedDate = now,
            ResolvedDate = now,
            InWarranty = true,
            Description = dto.Description.Trim(),
            Resolution = $"Đổi sang seri {newSerial}",
            NewRegistrationId = fresh.Id,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        });
        await dbContext.SaveChangesAsync();
        await tx.CommitAsync();
        return Ok(AppResponse<object>.Success(new { newRegistrationId = fresh.Id, serial = newSerial }));
    }

    /// <summary>Phiếu bảo hành đang xử lý của cửa hàng (chưa đóng).</summary>
    [HttpGet("claims/open")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> OpenClaims()
    {
        var storeId = RequiredStoreId;
        var rows = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Include(c => c.Registration).ThenInclude(r => r!.Product)
            .Where(c => c.StoreId == storeId && c.Deleted == null &&
                        (c.Status == PosWarrantyClaimStatus.Received || c.Status == PosWarrantyClaimStatus.Processing))
            .OrderBy(c => c.ReceivedDate)
            .Take(200)
            .ToListAsync();
        var items = rows.Select(c => new
        {
            claim = MapClaim(c),
            serial = c.Registration?.SerialNumber,
            productName = c.Registration?.Product?.Name,
        }).ToList();
        return Ok(AppResponse<object>.Success(new { items, count = items.Count }));
    }

    private static WarrantyRegistrationDto MapDto(PosProductWarrantyRegistration r) =>
        new(
            r.Id,
            r.SerialNumber,
            r.Imei,
            r.WarrantyMonths,
            r.SaleDate,
            r.WarrantyExpiry,
            r.Status.ToString(),
            r.Product?.Name ?? "",
            r.Product?.ProductCode,
            r.Customer?.Name ?? r.SaleOrder?.CustomerName,
            r.Customer?.Phone,
            r.SaleOrder?.OrderNo ?? "",
            r.SaleOrderId,
            r.ProductId,
            r.VariantId,
            r.Note);
}
