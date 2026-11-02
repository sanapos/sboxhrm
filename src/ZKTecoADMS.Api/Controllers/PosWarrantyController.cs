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
using ZKTecoADMS.Infrastructure.Services;

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
        int ClaimCount = 0,
        // Phiếu sửa đang mở của máy (đang ở cửa hàng) — null nếu không có.
        string? OpenClaimStatus = null);

    /// <summary>
    /// Phiếu sửa «máy đang ở cửa hàng»: chưa trả máy cho khách. Hoàn tất / từ chối giữ nguyên trạng thái
    /// (báo cáo còn biết kết quả); trả máy chỉ ghi <see cref="PosWarrantyClaim.DeliveredDate"/>.
    /// </summary>
    private static readonly System.Linq.Expressions.Expression<Func<PosWarrantyClaim, bool>> InShop = c =>
        c.ClaimType == PosWarrantyClaimType.Repair && c.DeliveredDate == null &&
        c.Deleted == null;

    private IQueryable<PosProductWarrantyRegistration> Registrations(Guid storeId) =>
        dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product)
            .Include(r => r.SaleOrder)
            .Include(r => r.Customer)
            .Where(r => r.StoreId == storeId && r.Deleted == null);

    [HttpGet("lookup")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Lookup(
        [FromQuery] string? serial,
        [FromQuery] string? phone,
        [FromQuery] string? orderNo)
    {
        var storeId = RequiredStoreId;
        var q = Registrations(storeId);

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
        var items = await WithClaimInfoAsync(storeId, rows);
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

        var q = Registrations(storeId)
            .Where(r => r.Status == PosWarrantyStatus.Active && r.WarrantyMonths > 0);

        if (includeExpired)
            q = q.Where(r => r.WarrantyExpiry <= until);
        else
            q = q.Where(r => r.WarrantyExpiry >= now && r.WarrantyExpiry <= until);

        var rows = await q.OrderBy(r => r.WarrantyExpiry).Take(200).ToListAsync();
        var items = rows.Select(r => MapDto(r)).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            days,
            includeExpired,
            expiringSoonCount = items.Count,
            items,
        }));
    }

    /// <summary>
    /// Danh sách máy đã bán có bảo hành. <paramref name="status"/>: Active / Returned / Voided / Replaced,
    /// «InWarranty» (còn hạn) hoặc «Expired» (chưa trả / đổi nhưng đã quá hạn). Hàng không seri vẫn hiện
    /// (mã AUTO-…, app ghi «Không có seri — bảo hành theo đơn»).
    /// </summary>
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
        var now = DateTime.UtcNow;

        var q = Registrations(storeId);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            var digits = new string(search.Where(char.IsDigit).ToArray());
            q = q.Where(r =>
                VnSearch.Has(r.SerialNumber, s) ||
                (r.Imei != null && VnSearch.Has(r.Imei, s)) ||
                (r.Product != null && VnSearch.Has(r.Product.Name, s)) ||
                (r.SaleOrder != null && VnSearch.Has(r.SaleOrder.OrderNo, s)) ||
                (r.Customer != null && VnSearch.Has(r.Customer.Name, s)) ||
                (digits.Length >= 3 && r.Customer != null && r.Customer.Phone != null && r.Customer.Phone.Contains(digits)));
        }

        switch (status)
        {
            case "InWarranty":
                q = q.Where(r => r.Status == PosWarrantyStatus.Active && r.WarrantyMonths > 0 && r.WarrantyExpiry >= now);
                break;
            case "Expired":
                q = q.Where(r => r.Status == PosWarrantyStatus.Active && (r.WarrantyMonths <= 0 || r.WarrantyExpiry < now));
                break;
            default:
                if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<PosWarrantyStatus>(status, true, out var st))
                    q = q.Where(r => r.Status == st);
                break;
        }

        var total = await q.CountAsync();
        var rows = await q
            .OrderByDescending(r => r.SaleDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();
        var items = await WithClaimInfoAsync(storeId, rows);

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    /// <summary>Gắn số lần bảo hành (cả máy trước khi đổi) và phiếu đang mở cho từng máy.</summary>
    private async Task<List<WarrantyRegistrationDto>> WithClaimInfoAsync(
        Guid storeId, List<PosProductWarrantyRegistration> rows)
    {
        var result = new List<WarrantyRegistrationDto>(rows.Count);
        if (rows.Count == 0) return result;
        var ids = rows.Select(r => r.Id).ToList();
        // Máy đổi về: lịch sử nằm ở máy cũ → gom cả chuỗi.
        var predecessors = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.NewRegistrationId != null)
            .Select(c => new { New = c.NewRegistrationId!.Value, Old = c.RegistrationId })
            .ToListAsync();
        var prevOf = predecessors.GroupBy(x => x.New).ToDictionary(g => g.Key, g => g.First().Old);
        var chains = rows.ToDictionary(r => r.Id, r => ChainBack(r.Id, prevOf));
        var allIds = chains.Values.SelectMany(x => x).Distinct().ToList();
        var claims = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && allIds.Contains(c.RegistrationId))
            .Select(c => new { c.RegistrationId, c.ClaimType, c.Status, c.DeliveredDate })
            .ToListAsync();
        foreach (var r in rows)
        {
            var chain = chains[r.Id];
            var mine = claims.Where(c => chain.Contains(c.RegistrationId)).ToList();
            var open = claims.FirstOrDefault(c => c.RegistrationId == r.Id &&
                                                  c.ClaimType == PosWarrantyClaimType.Repair &&
                                                  c.DeliveredDate == null);
            result.Add(MapDto(r) with
            {
                ClaimCount = mine.Count(c => c.ClaimType != PosWarrantyClaimType.Note),
                OpenClaimStatus = open?.Status.ToString(),
            });
        }
        return result;
    }

    private static List<Guid> ChainBack(Guid id, IReadOnlyDictionary<Guid, Guid> prevOf)
    {
        var chain = new List<Guid> { id };
        var cur = id;
        while (prevOf.TryGetValue(cur, out var prev) && !chain.Contains(prev) && chain.Count < 20)
        {
            chain.Add(prev);
            cur = prev;
        }
        return chain;
    }

    public record ClaimDto(
        Guid Id, Guid RegistrationId, string ClaimType, string Status, DateTime ReceivedDate,
        DateTime? ResolvedDate, bool InWarranty, string? Description, string? Resolution,
        Guid? NewRegistrationId, string? CreatedBy,
        string? ClaimNo = null,
        string? ContactName = null,
        string? ContactPhone = null,
        string? DeviceCondition = null,
        string? Accessories = null,
        DateTime? ExpectedReturnDate = null,
        string? AssignedTo = null,
        decimal Fee = 0,
        bool FeePaid = false,
        DateTime? DeliveredDate = null,
        // Thông tin máy (phiếu in / danh sách phiếu).
        string? SerialNumber = null,
        string? Imei = null,
        string? ProductName = null,
        string? CustomerName = null,
        string? CustomerPhone = null,
        string? OrderNo = null,
        DateTime? SaleDate = null,
        DateTime? WarrantyExpiry = null,
        int WarrantyMonths = 0);

    private static ClaimDto MapClaim(PosWarrantyClaim c, PosProductWarrantyRegistration? reg = null)
    {
        reg ??= c.Registration;
        return new ClaimDto(
            c.Id, c.RegistrationId, c.ClaimType.ToString(), c.Status.ToString(), c.ReceivedDate,
            c.ResolvedDate, c.InWarranty, c.Description, c.Resolution, c.NewRegistrationId, c.CreatedBy,
            c.ClaimNo, c.ContactName, c.ContactPhone, c.DeviceCondition, c.Accessories,
            c.ExpectedReturnDate, c.AssignedTo, c.Fee, c.FeePaid, c.DeliveredDate,
            reg?.SerialNumber, reg?.Imei, reg?.Product?.Name,
            reg?.Customer?.Name ?? reg?.SaleOrder?.CustomerName, reg?.Customer?.Phone,
            reg?.SaleOrder?.OrderNo, reg?.SaleDate, reg?.WarrantyExpiry, reg?.WarrantyMonths ?? 0);
    }

    private IQueryable<PosWarrantyClaim> Claims(Guid storeId) =>
        dbContext.PosWarrantyClaims.AsNoTracking()
            .Include(c => c.Registration).ThenInclude(r => r!.Product)
            .Include(c => c.Registration).ThenInclude(r => r!.SaleOrder)
            .Include(c => c.Registration).ThenInclude(r => r!.Customer)
            .Where(c => c.StoreId == storeId && c.Deleted == null);

    /// <summary>Lịch sử bảo hành của một máy (seri) — gồm cả các máy trước khi đổi.</summary>
    [HttpGet("{id:guid}/claims")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetClaims(Guid id)
    {
        var storeId = RequiredStoreId;
        var exists = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .AnyAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (!exists) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy"));

        var prevOf = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.NewRegistrationId != null)
            .Select(c => new { New = c.NewRegistrationId!.Value, Old = c.RegistrationId })
            .ToListAsync();
        var chain = ChainBack(id, prevOf.GroupBy(x => x.New).ToDictionary(g => g.Key, g => g.First().Old));

        var rows = await Claims(storeId)
            .Where(c => chain.Contains(c.RegistrationId))
            .OrderByDescending(c => c.ReceivedDate)
            .ToListAsync();
        return Ok(AppResponse<object>.Success(new { items = rows.Select(c => MapClaim(c)).ToList() }));
    }

    /// <summary>Một phiếu bảo hành (in lại phiếu tiếp nhận / trả máy).</summary>
    [HttpGet("claims/{claimId:guid}")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ClaimDto>>> GetClaim(Guid claimId)
    {
        var storeId = RequiredStoreId;
        var c = await Claims(storeId).FirstOrDefaultAsync(x => x.Id == claimId);
        if (c == null) return NotFound(AppResponse<ClaimDto>.Fail("Không tìm thấy phiếu bảo hành"));
        return Ok(AppResponse<ClaimDto>.Success(MapClaim(c)));
    }

    public record CreateClaimDto(
        string? ClaimType,
        string? Description,
        string? ContactName = null,
        string? ContactPhone = null,
        string? DeviceCondition = null,
        string? Accessories = null,
        DateTime? ExpectedReturnDate = null,
        string? AssignedTo = null);

    private static string? Clip(string? s, int max)
    {
        var t = s?.Trim();
        if (string.IsNullOrEmpty(t)) return null;
        return t.Length > max ? t[..max] : t;
    }

    /// <summary>Số phiếu theo ngày VN: BH + yyMMdd + 3 số thứ tự (BH0211260001… khi quá 999 vẫn tăng).</summary>
    private async Task<string> NextClaimNoAsync(Guid storeId)
    {
        var prefix = "BH" + VnTimeHelper.NowVn().ToString("ddMMyy");
        var used = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.ClaimNo != null && c.ClaimNo.StartsWith(prefix))
            .Select(c => c.ClaimNo!)
            .ToListAsync();
        var max = used.Select(n => int.TryParse(n[prefix.Length..], out var k) ? k : 0).DefaultIfEmpty(0).Max();
        return $"{prefix}{max + 1:D4}";
    }

    /// <summary>
    /// Tiếp nhận bảo hành / sửa chữa (hoặc ghi chú) cho một máy. Hết hạn vẫn nhận nhưng đánh dấu tính phí.
    /// Ghi chú được thêm cả cho máy đã trả / đã đổi (lưu vết); sửa chữa chỉ cho máy đang bảo hành.
    /// </summary>
    [HttpPost("{id:guid}/claims")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ClaimDto>>> CreateClaim(Guid id, [FromBody] CreateClaimDto dto)
    {
        var storeId = RequiredStoreId;
        var reg = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product).Include(r => r.SaleOrder).Include(r => r.Customer)
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (reg == null) return NotFound(AppResponse<ClaimDto>.Fail("Không tìm thấy máy"));

        var type = Enum.TryParse<PosWarrantyClaimType>(dto.ClaimType, true, out var t) ? t : PosWarrantyClaimType.Repair;
        if (type == PosWarrantyClaimType.Replace)
            return BadRequest(AppResponse<ClaimDto>.Fail("Dùng chức năng «Đổi máy» để đổi seri"));
        if (type == PosWarrantyClaimType.Repair && reg.Status != PosWarrantyStatus.Active)
            return BadRequest(AppResponse<ClaimDto>.Fail("Máy này không còn ở trạng thái bảo hành (đã trả / hủy / đã đổi) — chỉ thêm được ghi chú"));
        if (string.IsNullOrWhiteSpace(dto.Description))
            return BadRequest(AppResponse<ClaimDto>.Fail("Nhập mô tả lỗi / nội dung tiếp nhận"));
        if (type == PosWarrantyClaimType.Repair)
        {
            var hasOpen = await dbContext.PosWarrantyClaims.AsNoTracking()
                .Where(InShop)
                .AnyAsync(c => c.StoreId == storeId && c.RegistrationId == id);
            if (hasOpen)
                return BadRequest(AppResponse<ClaimDto>.Fail("Máy đang có phiếu bảo hành chưa trả khách — mở phiếu đó để cập nhật"));
        }

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
            Description = Clip(dto.Description, 1000),
            ClaimNo = type == PosWarrantyClaimType.Repair ? await NextClaimNoAsync(storeId) : null,
            ContactName = Clip(dto.ContactName, 150) ?? reg.Customer?.Name ?? reg.SaleOrder?.CustomerName,
            ContactPhone = Clip(dto.ContactPhone, 30) ?? reg.Customer?.Phone,
            DeviceCondition = Clip(dto.DeviceCondition, 500),
            Accessories = Clip(dto.Accessories, 500),
            ExpectedReturnDate = dto.ExpectedReturnDate,
            AssignedTo = Clip(dto.AssignedTo, 150),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosWarrantyClaims.Add(claim);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<ClaimDto>.Success(MapClaim(claim, reg)));
    }

    public record UpdateClaimDto(
        string? Status,
        string? Resolution,
        decimal? Fee = null,
        bool CollectFee = false,
        string? PaymentMethod = null,
        Guid? BankAccountId = null,
        string? AssignedTo = null,
        DateTime? ExpectedReturnDate = null,
        // Trả máy cho khách (sau khi hoàn tất / từ chối).
        bool Deliver = false);

    /// <summary>
    /// Cập nhật phiếu: đang xử lý / hoàn tất / từ chối (+ kết quả), «Đã trả khách», phí sửa và thu phí
    /// (ghi phiếu thu «Phí sửa chữa bảo hành»), người phụ trách, ngày hẹn trả.
    /// </summary>
    [HttpPost("claims/{claimId:guid}")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ClaimDto>>> UpdateClaim(Guid claimId, [FromBody] UpdateClaimDto dto)
    {
        var storeId = RequiredStoreId;
        var claim = await dbContext.PosWarrantyClaims.AsTracking()
            .FirstOrDefaultAsync(c => c.Id == claimId && c.StoreId == storeId && c.Deleted == null);
        if (claim == null) return NotFound(AppResponse<ClaimDto>.Fail("Không tìm thấy phiếu bảo hành"));
        if (claim.ClaimType == PosWarrantyClaimType.Replace)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đổi máy đã hoàn tất, không sửa"));
        if (claim.ClaimType == PosWarrantyClaimType.Note)
            return BadRequest(AppResponse<ClaimDto>.Fail("Ghi chú không có bước xử lý"));
        if (claim.DeliveredDate != null)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đã trả máy cho khách"));

        PosWarrantyClaimStatus? next = null;
        if (!string.IsNullOrWhiteSpace(dto.Status))
        {
            if (!Enum.TryParse<PosWarrantyClaimStatus>(dto.Status, true, out var st))
                return BadRequest(AppResponse<ClaimDto>.Fail("Trạng thái không hợp lệ"));
            next = st;
        }

        var closed = claim.Status is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected;
        if (next is PosWarrantyClaimStatus.Received or PosWarrantyClaimStatus.Processing && closed)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đã xử lý xong — chỉ còn bước trả máy cho khách"));
        if (next is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected && closed && next != claim.Status)
            return BadRequest(AppResponse<ClaimDto>.Fail("Phiếu đã đóng"));
        var closing = next is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected && !closed;
        if (dto.Deliver && !closed && !closing)
            return BadRequest(AppResponse<ClaimDto>.Fail("Bấm «Hoàn tất» hoặc «Từ chối» (ghi kết quả) trước khi trả máy"));
        if (closing && string.IsNullOrWhiteSpace(dto.Resolution) && string.IsNullOrWhiteSpace(claim.Resolution))
            return BadRequest(AppResponse<ClaimDto>.Fail("Nhập kết quả xử lý khi đóng phiếu"));

        if (dto.Fee.HasValue)
        {
            var fee = Math.Max(0, Math.Round(dto.Fee.Value, 0));
            if (claim.FeePaid && fee != claim.Fee)
                return BadRequest(AppResponse<ClaimDto>.Fail("Đã thu phí — không sửa số tiền (xóa phiếu thu ở Thu chi nếu cần)"));
            claim.Fee = fee;
        }

        var now = DateTime.UtcNow;
        if (next.HasValue) claim.Status = next.Value;
        if (!string.IsNullOrWhiteSpace(dto.Resolution)) claim.Resolution = Clip(dto.Resolution, 1000);
        if (closing) claim.ResolvedDate = now;
        if (dto.Deliver) claim.DeliveredDate = now;
        if (dto.AssignedTo != null) claim.AssignedTo = Clip(dto.AssignedTo, 150);
        if (dto.ExpectedReturnDate.HasValue) claim.ExpectedReturnDate = dto.ExpectedReturnDate;

        var reg = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Include(r => r.Product).Include(r => r.SaleOrder).Include(r => r.Customer)
            .FirstOrDefaultAsync(r => r.Id == claim.RegistrationId);

        if (dto.CollectFee && claim.Fee > 0 && !claim.FeePaid)
        {
            var cash = await PosFinanceSyncHelper.AddWarrantyFeeReceiptAsync(
                dbContext, storeId, reg?.SaleOrder?.BranchId, claim,
                reg?.Product?.Name ?? "máy", reg?.SerialNumber ?? "", dto.PaymentMethod, dto.BankAccountId,
                CurrentUserId);
            if (cash != null)
            {
                claim.FeePaid = true;
                claim.CashTransactionId = cash.Id;
            }
        }

        claim.UpdatedAt = now;
        claim.UpdatedBy = CurrentUserEmail;
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                await dbContext.SaveChangesAsync();
                break;
            }
            catch (DbUpdateException) when (attempt < 2 && claim.CashTransactionId != null)
            {
                // Hai máy thu tiền cùng lúc → trùng mã phiếu thu: cấp mã mới rồi lưu lại.
                await PosFinanceSyncHelper.RegenerateDuplicateCodesAsync(dbContext, storeId);
            }
        }
        return Ok(AppResponse<ClaimDto>.Success(MapClaim(claim, reg)));
    }

    public record ReplaceDto(string? NewSerial, string? NewImei, string? Description, bool? FromStock = null);

    /// <summary>
    /// Đổi máy bảo hành: seri cũ → «Replaced», seri mới thừa hưởng thời hạn bảo hành còn lại của máy cũ
    /// (không gia hạn). Chỉ đổi khi máy còn hạn bảo hành.
    /// Máy mới lấy từ kho cửa hàng (mặc định) → lập phiếu xuất kho 1 máy để tồn kho khớp sổ seri;
    /// máy hãng gửi về (<c>FromStock = false</c>) → không trừ kho. Máy cũ thu hồi, ghi chú «chờ trả NCC / gửi hãng».
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
        var fromStock = dto.FromStock ?? true;

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

        var product = await dbContext.PosProducts.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == old.ProductId && p.StoreId == storeId);
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.Id == old.SaleOrderId)
            .Select(o => new { o.BranchId, o.OrderNo, o.CustomerName })
            .FirstOrDefaultAsync();
        var freshRow = await dbContext.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.SerialNumber == newSerial)
            .OrderBy(x => x.Status)
            .Select(x => new { x.ProductId, x.Status })
            .FirstOrDefaultAsync();
        if (freshRow != null && freshRow.ProductId != old.ProductId)
            return BadRequest(AppResponse<object>.Fail($"Seri {newSerial} thuộc mặt hàng khác"));
        if (freshRow is { Status: PosSerialStatus.Sold })
            return BadRequest(AppResponse<object>.Fail($"Seri {newSerial} đã bán cho khách khác"));

        string? issueNo = null;
        if (!fromStock && freshRow is { Status: PosSerialStatus.InStock })
            return BadRequest(AppResponse<object>.Fail($"Seri {newSerial} đang trong kho cửa hàng — chọn «Lấy máy trong kho» để trừ tồn"));
        if (fromStock && product != null && PosProductTypeRules.TracksInventory(product.ProductType))
        {
            var tracked = product.RequiresSerial &&
                          await PosSerialRegistry.IsTrackedAsync(dbContext, storeId, product.Id);
            if (tracked && freshRow is not { Status: PosSerialStatus.InStock })
                return BadRequest(AppResponse<object>.Fail(
                    $"Seri {newSerial} không có trong kho — kiểm tra lại seri, hoặc chọn «Máy hãng gửi về» nếu máy mới không lấy từ kho"));

            issueNo = "XK" + VnTimeHelper.NowVn().ToString("yyMMdd") + Random.Shared.Next(1000, 9999);
            var reason = $"Đổi máy bảo hành — seri {old.SerialNumber} → {newSerial}" +
                         (order == null ? "" : $" (đơn {order.OrderNo})");
            var issue = new PosStockIssue
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                BranchId = order?.BranchId,
                IssueNo = issueNo,
                Reason = reason,
                Note = dto.Description.Trim(),
                Kind = PosStockIssueKind.Generic,
                Status = PosStockIssueStatus.Completed,
                CompletedAt = now,
                IssuedAt = now,
                IssuedBy = CurrentUserEmail,
                RecipientName = order?.CustomerName,
                TotalQty = 1,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            var line = new PosStockIssueLine
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                IssueId = issue.Id,
                ProductId = product.Id,
                VariantId = old.VariantId,
                ProductName = product.Name,
                ProductCode = product.ProductCode,
                Qty = 1,
                SerialNumbersText = tracked ? newSerial : null,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            try
            {
                await PosPurchaseStockHelper.ApplyIssueStockAsync(
                    dbContext, storeId, issue, [line], CurrentUserEmail, reason);
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(AppResponse<object>.Fail(ex.Message));
            }
            dbContext.PosStockIssues.Add(issue);
            dbContext.PosStockIssueLines.Add(line);
        }

        // Máy mới vừa xuất kho đang «Removed» trong bộ nhớ → ReplaceAsync chuyển thành «Sold» cho đơn của khách.
        var serialErr = await PosSerialRegistry.ReplaceAsync(
            dbContext, storeId, old.SaleOrderId, old.ProductId, old.SerialNumber, newSerial, CurrentUserEmail);
        if (serialErr != null)
            return BadRequest(AppResponse<object>.Fail(serialErr));
        var oldSerialRow = dbContext.ChangeTracker.Entries<PosProductSerial>()
            .Select(e => e.Entity)
            .FirstOrDefault(x => x.SerialNumber == PosSaleWarrantyHelper.NormalizeSerial(old.SerialNumber) &&
                                 x.Status == PosSerialStatus.Removed);
        if (oldSerialRow != null)
            oldSerialRow.Note = $"Máy lỗi thu hồi (đổi BH sang {newSerial}) — chờ trả NCC / gửi hãng";

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
            DeliveredDate = now,
            InWarranty = true,
            Description = dto.Description.Trim(),
            Resolution = $"Đổi sang seri {newSerial}" +
                         (issueNo != null ? $" — xuất kho {issueNo}" : fromStock ? "" : " — máy hãng gửi về"),
            NewRegistrationId = fresh.Id,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        });

        // Phiếu sửa đang mở của máy cũ: máy đã đổi → đóng luôn (không treo «đang ở cửa hàng»).
        var openOld = await dbContext.PosWarrantyClaims.AsTracking()
            .Where(InShop)
            .Where(c => c.StoreId == storeId && c.RegistrationId == old.Id)
            .ToListAsync();
        foreach (var c in openOld)
        {
            if (c.Status is PosWarrantyClaimStatus.Received or PosWarrantyClaimStatus.Processing)
                c.Status = PosWarrantyClaimStatus.Done;
            c.ResolvedDate ??= now;
            c.DeliveredDate = now;
            c.Resolution ??= $"Đổi máy mới seri {newSerial}";
            c.UpdatedAt = now;
            c.UpdatedBy = CurrentUserEmail;
        }

        await dbContext.SaveChangesAsync();
        await tx.CommitAsync();
        return Ok(AppResponse<object>.Success(new { newRegistrationId = fresh.Id, serial = newSerial, issueNo }));
    }

    /// <summary>
    /// Danh sách phiếu bảo hành. <paramref name="status"/>: «InShop» (máy đang ở cửa hàng, mặc định),
    /// «Overdue» (quá ngày hẹn trả), «All», hoặc tên trạng thái.
    /// </summary>
    [HttpGet("claims")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListClaims(
        [FromQuery] string? status,
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);
        var now = DateTime.UtcNow;
        var q = Claims(storeId).Where(c => c.ClaimType != PosWarrantyClaimType.Note);

        switch (status ?? "InShop")
        {
            case "InShop":
                q = q.Where(InShop);
                break;
            case "Overdue":
                q = q.Where(InShop).Where(c => c.ExpectedReturnDate != null && c.ExpectedReturnDate < now);
                break;
            case "Ready":
                // Sửa xong / từ chối, chờ khách đến lấy.
                q = q.Where(InShop).Where(c => c.Status == PosWarrantyClaimStatus.Done ||
                                               c.Status == PosWarrantyClaimStatus.Rejected);
                break;
            case "Delivered":
                q = q.Where(c => c.DeliveredDate != null);
                break;
            case "All":
                break;
            default:
                if (Enum.TryParse<PosWarrantyClaimStatus>(status, true, out var st))
                    q = q.Where(c => c.Status == st);
                break;
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search);
            var digits = new string(search.Where(char.IsDigit).ToArray());
            q = q.Where(c =>
                (c.ClaimNo != null && VnSearch.Has(c.ClaimNo, s)) ||
                (c.Registration != null && (VnSearch.Has(c.Registration.SerialNumber, s) ||
                    (c.Registration.Product != null && VnSearch.Has(c.Registration.Product.Name, s)) ||
                    (c.Registration.Customer != null && VnSearch.Has(c.Registration.Customer.Name, s)))) ||
                (c.ContactName != null && VnSearch.Has(c.ContactName, s)) ||
                (digits.Length >= 3 && c.ContactPhone != null && c.ContactPhone.Contains(digits)));
        }

        var total = await q.CountAsync();
        // Đang ở cửa hàng: lâu nhất lên đầu (nhắc trả máy); còn lại mới nhất lên đầu.
        var ordered = status is null or "InShop" or "Overdue" or "Ready"
            ? q.OrderBy(c => c.ReceivedDate)
            : q.OrderByDescending(c => c.ReceivedDate);
        var rows = await ordered.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            items = rows.Select(c => MapClaim(c)).ToList(),
            total,
            page,
            pageSize,
        }));
    }

    /// <summary>Phiếu bảo hành máy đang ở cửa hàng (chưa trả khách). Giữ dạng cũ cho app bản trước.</summary>
    [HttpGet("claims/open")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> OpenClaims()
    {
        var storeId = RequiredStoreId;
        var rows = await Claims(storeId)
            .Where(InShop)
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

    /// <summary>
    /// Báo cáo bảo hành trong kỳ (theo ngày tiếp nhận, giờ VN): số phiếu, đổi máy, từ chối, thời gian xử lý,
    /// phí đã thu, theo tháng, mặt hàng hay lỗi nhất (tỉ lệ = lần bảo hành / máy đã bán có bảo hành).
    /// </summary>
    [HttpGet("report")]
    [RequireModulePermission("PosWarranty", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Report([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        var nowVn = VnTimeHelper.NowVn();
        var fromVn = (from?.Date ?? new DateTime(nowVn.Year, nowVn.Month, 1).AddMonths(-5));
        var toVn = (to?.Date ?? nowVn.Date).AddDays(1);
        var fromUtc = fromVn.AddHours(-VnTimeHelper.OffsetHours);
        var toUtc = toVn.AddHours(-VnTimeHelper.OffsetHours);
        var now = DateTime.UtcNow;

        var claims = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.ClaimType != PosWarrantyClaimType.Note &&
                        c.ReceivedDate >= fromUtc && c.ReceivedDate < toUtc)
            .Select(c => new
            {
                c.ClaimType, c.Status, c.ReceivedDate, c.ResolvedDate, c.InWarranty, c.Fee, c.FeePaid,
                ProductId = c.Registration!.ProductId,
                ProductName = c.Registration!.Product!.Name,
            })
            .ToListAsync();

        var inShop = await dbContext.PosWarrantyClaims.AsNoTracking()
            .Where(InShop)
            .Where(c => c.StoreId == storeId)
            .Select(c => new { c.ExpectedReturnDate, c.Status })
            .ToListAsync();

        var regStats = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status != PosWarrantyStatus.Voided)
            .GroupBy(r => r.ProductId)
            .Select(g => new { ProductId = g.Key, Sold = g.Count() })
            .ToDictionaryAsync(x => x.ProductId, x => x.Sold);
        var active = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .CountAsync(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosWarrantyStatus.Active &&
                             r.WarrantyMonths > 0 && r.WarrantyExpiry >= now);
        var expiring30 = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .CountAsync(r => r.StoreId == storeId && r.Deleted == null && r.Status == PosWarrantyStatus.Active &&
                             r.WarrantyMonths > 0 && r.WarrantyExpiry >= now && r.WarrantyExpiry <= now.AddDays(30));

        var resolved = claims
            .Where(c => c.ClaimType == PosWarrantyClaimType.Repair && c.ResolvedDate != null)
            .Select(c => (c.ResolvedDate!.Value - c.ReceivedDate).TotalDays)
            .ToList();

        var byMonth = claims
            .GroupBy(c => VnTimeHelper.UtcToVn(c.ReceivedDate).ToString("yyyy-MM"))
            .OrderBy(g => g.Key)
            .Select(g => new
            {
                month = g.Key,
                claims = g.Count(),
                repairs = g.Count(x => x.ClaimType == PosWarrantyClaimType.Repair),
                replaces = g.Count(x => x.ClaimType == PosWarrantyClaimType.Replace),
                fee = g.Where(x => x.FeePaid).Sum(x => x.Fee),
            })
            .ToList();

        var byProduct = claims
            .GroupBy(c => new { c.ProductId, c.ProductName })
            .Select(g =>
            {
                var sold = regStats.GetValueOrDefault(g.Key.ProductId);
                return new
                {
                    productId = g.Key.ProductId,
                    productName = g.Key.ProductName,
                    claims = g.Count(),
                    replaces = g.Count(x => x.ClaimType == PosWarrantyClaimType.Replace),
                    sold,
                    ratePercent = sold > 0 ? Math.Round(g.Count() * 100.0 / sold, 1) : 0,
                };
            })
            .OrderByDescending(x => x.claims).ThenByDescending(x => x.ratePercent)
            .Take(15)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn,
            to = toVn.AddDays(-1),
            totalClaims = claims.Count,
            repairs = claims.Count(c => c.ClaimType == PosWarrantyClaimType.Repair),
            replaces = claims.Count(c => c.ClaimType == PosWarrantyClaimType.Replace),
            rejected = claims.Count(c => c.Status == PosWarrantyClaimStatus.Rejected),
            outOfWarranty = claims.Count(c => !c.InWarranty),
            feeCollected = claims.Where(c => c.FeePaid).Sum(c => c.Fee),
            feeUnpaid = claims.Where(c => !c.FeePaid).Sum(c => c.Fee),
            avgDays = resolved.Count == 0 ? 0 : Math.Round(resolved.Average(), 1),
            inShopNow = inShop.Count,
            overdueNow = inShop.Count(c => c.ExpectedReturnDate != null && c.ExpectedReturnDate < now),
            readyToReturn = inShop.Count(c => c.Status is PosWarrantyClaimStatus.Done or PosWarrantyClaimStatus.Rejected),
            activeWarranties = active,
            expiring30,
            byMonth,
            byProduct,
        }));
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
