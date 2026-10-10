using ZKTecoADMS.Application.Helpers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/customers")]
[Authorize]
public partial class PosCustomersController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record CustomerDto(
        Guid Id, string CustomerCode, string Name, string? Phone, string? Email,
        string? Address, string? Province, string? Ward,
        string? CompanyName, string? TaxCode,
        string? LegalRepresentative, string? LegalTitle, string? Note,
        DateTime? Birthday, string? DeliveryAddress,
        decimal TotalPurchase, decimal CurrentDebt, decimal PointBalance, bool IsActive,
        DateTime CreatedAt, string? CreatedBy);

    public record CustomerSaveDto(
        string Name, string? Phone, string? Email, string? Address,
        string? Province, string? Ward, string? CompanyName, string? TaxCode,
        string? LegalRepresentative, string? LegalTitle, string? Note,
        DateTime? Birthday, string? DeliveryAddress);

    [HttpGet]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] decimal? purchaseFrom,
        [FromQuery] decimal? purchaseTo,
        [FromQuery] bool? hasDebt,
        [FromQuery] bool? activeOnly,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        // today | week | month | next30 — sinh nhật theo ngày / tháng (giờ VN)
        [FromQuery] string? birthday = null,
        // Đã từng mua nhưng không mua trong N ngày gần đây (chăm sóc khách cũ)
        [FromQuery] int? inactiveDays = null,
        // active (mặc định) | inactive | all
        [FromQuery] string? status = null,
        // debt (mặc định) | purchase | points | name | recent | newest | birthday
        [FromQuery] string? sort = null)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null);
        var st = (status ?? (activeOnly == false ? "all" : "active")).Trim().ToLowerInvariant();
        if (st == "active") query = query.Where(c => c.IsActive);
        else if (st == "inactive") query = query.Where(c => !c.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = VnSearch.FoldText(search); // không dấu: «binh» khớp «Bình»
            query = query.Where(c =>
                VnSearch.Has(c.Name, s) ||
                VnSearch.Has(c.CustomerCode, s) ||
                (c.Phone != null && c.Phone.Contains(s)) ||
                (c.TaxCode != null && VnSearch.Has(c.TaxCode, s)));
        }
        if (debtFrom.HasValue) query = query.Where(c => c.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) query = query.Where(c => c.CurrentDebt <= debtTo);
        if (purchaseFrom.HasValue) query = query.Where(c => c.TotalPurchase >= purchaseFrom);
        if (purchaseTo.HasValue) query = query.Where(c => c.TotalPurchase <= purchaseTo);
        if (hasDebt == true) query = query.Where(c => c.CurrentDebt > 0);

        var todayVn = VnTimeHelper.NowVn().Date;
        var bdKeys = BirthdayKeys(birthday, todayVn);
        if (bdKeys != null)
            query = query.Where(c => c.Birthday != null && bdKeys.Contains(c.Birthday.Value.Month * 100 + c.Birthday.Value.Day));

        // Đơn hoàn tất của khách (lần mua gần nhất / lâu không mua)
        var done = dbContext.PosSaleOrders.Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                                                       && o.Status == PosSaleOrderStatus.Completed);
        if (inactiveDays is > 0)
        {
            var cutoff = DateTime.UtcNow.AddDays(-inactiveDays.Value);
            query = query.Where(c => done.Any(o => o.CustomerId == c.Id)
                                     && !done.Any(o => o.CustomerId == c.Id && (o.SaleDate ?? o.CreatedAt) >= cutoff));
        }

        var total = await query.CountAsync();
        var sumDebt = await query.SumAsync(c => c.CurrentDebt);
        var sumPurchase = await query.SumAsync(c => c.TotalPurchase);
        var sumPoints = await query.SumAsync(c => c.PointBalance);
        var monthKeys = BirthdayKeys("month", todayVn)!;
        var birthdaysThisMonth = await query.CountAsync(c => c.Birthday != null
            && monthKeys.Contains(c.Birthday.Value.Month * 100 + c.Birthday.Value.Day));

        // Sắp xếp ở máy chủ (trước đây luôn theo công nợ; bấm cột chỉ sắp trong trang đang xem).
        var todayKey = todayVn.Month * 100 + todayVn.Day;
        IOrderedQueryable<PosCustomer> ordered = (sort ?? "debt").Trim().ToLowerInvariant() switch
        {
            "purchase" => query.OrderByDescending(c => c.TotalPurchase),
            "points" => query.OrderByDescending(c => c.PointBalance),
            "name" => query.OrderBy(c => c.Name),
            "newest" => query.OrderByDescending(c => c.CreatedAt),
            "recent" => query.OrderByDescending(c => done.Where(o => o.CustomerId == c.Id)
                .Max(o => (DateTime?)(o.SaleDate ?? o.CreatedAt))),
            // Sinh nhật sắp tới: ngày ≥ hôm nay trước, rồi đến đầu năm sau.
            "birthday" => query.OrderBy(c => c.Birthday == null ? 1 : 0)
                .ThenBy(c => c.Birthday == null ? 9999
                    : (c.Birthday.Value.Month * 100 + c.Birthday.Value.Day) >= todayKey
                        ? c.Birthday.Value.Month * 100 + c.Birthday.Value.Day
                        : c.Birthday.Value.Month * 100 + c.Birthday.Value.Day + 1300),
            _ => query.OrderByDescending(c => c.CurrentDebt),
        };
        var rows = await ordered.ThenBy(c => c.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(c => new
            {
                Customer = c,
                LastPurchaseAt = done.Where(o => o.CustomerId == c.Id).Max(o => (DateTime?)(o.SaleDate ?? o.CreatedAt)),
                OrderCount = done.Count(o => o.CustomerId == c.Id),
            })
            .ToListAsync();
        var items = rows.Select(r => new CustomerListItemDto(MapCustomer(r.Customer), r.LastPurchaseAt, r.OrderCount)).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            total, page, pageSize, sumDebt, sumPurchase, sumPoints, birthdaysThisMonth, items,
        }));
    }

    /// <summary>Khách trong danh sách + lần mua gần nhất (UTC) + số đơn hoàn tất. JSON phẳng như CustomerDto.</summary>
    public sealed record CustomerListItemDto(
        [property: System.Text.Json.Serialization.JsonIgnore] CustomerDto C, DateTime? LastPurchaseAt, int OrderCount)
    {
        public Guid Id => C.Id;
        public string CustomerCode => C.CustomerCode;
        public string Name => C.Name;
        public string? Phone => C.Phone;
        public string? Email => C.Email;
        public string? Address => C.Address;
        public string? Province => C.Province;
        public string? Ward => C.Ward;
        public string? CompanyName => C.CompanyName;
        public string? TaxCode => C.TaxCode;
        public string? LegalRepresentative => C.LegalRepresentative;
        public string? LegalTitle => C.LegalTitle;
        public string? Note => C.Note;
        public DateTime? Birthday => C.Birthday;
        public string? DeliveryAddress => C.DeliveryAddress;
        public decimal TotalPurchase => C.TotalPurchase;
        public decimal CurrentDebt => C.CurrentDebt;
        public decimal PointBalance => C.PointBalance;
        public bool IsActive => C.IsActive;
        public DateTime CreatedAt => C.CreatedAt;
        public string? CreatedBy => C.CreatedBy;
    }

    /// <summary>Tập (tháng × 100 + ngày) cho bộ lọc sinh nhật; null = không lọc.</summary>
    internal static List<int>? BirthdayKeys(string? filter, DateTime todayVn)
    {
        int days = (filter ?? "").Trim().ToLowerInvariant() switch
        {
            "today" => 1,
            "week" => 7,
            "next30" => 30,
            "month" => -1,
            _ => 0,
        };
        if (days == 0) return null;
        if (days < 0)
            return Enumerable.Range(1, DateTime.DaysInMonth(todayVn.Year, todayVn.Month))
                .Select(d => todayVn.Month * 100 + d).ToList();
        // 29/2: năm không nhuận vẫn chúc vào 28/2 → thêm 229 khi khoảng có 28/2.
        var keys = Enumerable.Range(0, days).Select(i => todayVn.AddDays(i)).Select(d => d.Month * 100 + d.Day).ToList();
        if (keys.Contains(228) && !DateTime.IsLeapYear(todayVn.Year)) keys.Add(229);
        return keys;
    }

    /// <summary>Số điện thoại chuẩn để so trùng: chỉ chữ số, bỏ 84 / 0 đầu.</summary>
    internal static string NormalizePhone(string? phone)
    {
        var d = new string((phone ?? "").Where(char.IsDigit).ToArray());
        if (d.StartsWith("84") && d.Length >= 11) d = d[2..];
        return d.TrimStart('0');
    }

    /// <summary>Khách khác (đang hoạt động) đã dùng số điện thoại này — null = không trùng.</summary>
    async Task<PosCustomer?> FindPhoneDuplicateAsync(Guid storeId, string? phone, Guid? exceptId)
    {
        var norm = NormalizePhone(phone);
        if (norm.Length < 8) return null;
        // Lọc sơ bộ bằng 3 số cuối (số lưu có thể có khoảng trắng / dấu chấm), so chính xác sau khi chuẩn hóa.
        var tail = norm[^3..];
        var candidates = await dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive && c.Phone != null
                        && c.Phone.Contains(tail) && (exceptId == null || c.Id != exceptId))
            .ToListAsync();
        return candidates.FirstOrDefault(c => NormalizePhone(c.Phone) == norm);
    }

    /// <summary>Ngừng hoạt động (khách đã có đơn không xóa được) — ẩn khỏi danh sách / màn bán, giữ lịch sử.</summary>
    [HttpPost("{id:guid}/deactivate")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public Task<ActionResult<AppResponse<CustomerDto>>> Deactivate(Guid id) => SetActiveAsync(id, false);

    [HttpPost("{id:guid}/activate")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public Task<ActionResult<AppResponse<CustomerDto>>> Activate(Guid id) => SetActiveAsync(id, true);

    async Task<ActionResult<AppResponse<CustomerDto>>> SetActiveAsync(Guid id, bool active)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<CustomerDto>.Fail("Không tìm thấy khách hàng"));
        if (active && await FindPhoneDuplicateAsync(storeId, c.Phone, c.Id) is { } dup)
            return BadRequest(AppResponse<CustomerDto>.Fail($"Số điện thoại đang thuộc khách «{dup.Name}» ({dup.CustomerCode})"));
        c.IsActive = active;
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    /// Tra cứu MST (CQT qua VietQR) — điền tên đơn vị / địa chỉ xuất HĐĐT.
    [HttpGet("tax-lookup")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> LookupTax([FromQuery] string? taxCode)
    {
        var found = await VietQrBusinessLookup.LookupAsync(taxCode);
        if (!found.Ok)
            return Ok(AppResponse<object>.Fail(found.Message ?? "Không tra cứu được mã số thuế"));
        return Ok(AppResponse<object>.Success(VietQrBusinessLookup.ToDto(found)));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<CustomerDto>.Fail("Không tìm thấy khách hàng"));
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpPost]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Create([FromBody] CustomerSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CustomerDto>.Fail("Tên khách hàng không được trống"));

        // Một số điện thoại = một khách (trùng thì công nợ / điểm / lịch sử bị tách đôi).
        if (await FindPhoneDuplicateAsync(storeId, dto.Phone, null) is { } dupNew)
            return BadRequest(AppResponse<CustomerDto>.Fail($"Số điện thoại đã có ở khách «{dupNew.Name}» ({dupNew.CustomerCode})"));

        var code = await PosSaleStockHelper.NextCustomerCodeAsync(dbContext, storeId);
        var c = new PosCustomer
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            CustomerCode = code,
            Name = name,
            Phone = dto.Phone?.Trim(),
            Email = dto.Email?.Trim(),
            Address = dto.Address?.Trim(),
            Province = dto.Province?.Trim(),
            Ward = dto.Ward?.Trim(),
            CompanyName = dto.CompanyName?.Trim(),
            TaxCode = dto.TaxCode?.Trim(),
            LegalRepresentative = dto.LegalRepresentative?.Trim(),
            LegalTitle = dto.LegalTitle?.Trim(),
            Birthday = dto.Birthday?.Date,
            DeliveryAddress = dto.DeliveryAddress?.Trim(),
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        dbContext.PosCustomers.Add(c);
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CustomerDto>>> Update(Guid id, [FromBody] CustomerSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<CustomerDto>.Fail("Không tìm thấy khách hàng"));
        var name = dto.Name?.Trim() ?? "";
        if (string.IsNullOrEmpty(name))
            return BadRequest(AppResponse<CustomerDto>.Fail("Tên khách hàng không được trống"));

        if (await FindPhoneDuplicateAsync(storeId, dto.Phone, c.Id) is { } dupUpd)
            return BadRequest(AppResponse<CustomerDto>.Fail($"Số điện thoại đã có ở khách «{dupUpd.Name}» ({dupUpd.CustomerCode})"));

        c.Name = name;
        c.Phone = dto.Phone?.Trim();
        c.Email = dto.Email?.Trim();
        c.Address = dto.Address?.Trim();
        c.Province = dto.Province?.Trim();
        c.Ward = dto.Ward?.Trim();
        c.CompanyName = dto.CompanyName?.Trim();
        c.TaxCode = dto.TaxCode?.Trim();
        c.LegalRepresentative = dto.LegalRepresentative?.Trim();
        c.LegalTitle = dto.LegalTitle?.Trim();
        c.Birthday = dto.Birthday?.Date;
        c.DeliveryAddress = dto.DeliveryAddress?.Trim();
        c.Note = dto.Note?.Trim();
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpDelete("{id:guid}")]
    [RequireAnyActionOnModule("PosCustomers", ModulePermissionAction.Delete, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var c = await dbContext.PosCustomers
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (c == null) return NotFound(AppResponse<bool>.Fail("Không tìm thấy khách hàng"));
        if (await dbContext.PosSaleOrders.AnyAsync(o => o.CustomerId == id && o.Deleted == null))
            return BadRequest(AppResponse<bool>.Fail("Khách hàng đã có đơn hàng — ngừng hoạt động thay vì xóa"));
        c.Deleted = DateTime.UtcNow;
        c.DeletedBy = CurrentUserEmail;
        c.IsActive = false;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private static CustomerDto MapCustomer(PosCustomer c) => new(
        c.Id, c.CustomerCode, c.Name, c.Phone, c.Email, c.Address, c.Province, c.Ward,
        c.CompanyName, c.TaxCode, c.LegalRepresentative, c.LegalTitle, c.Note,
        c.Birthday, c.DeliveryAddress,
        c.TotalPurchase, c.CurrentDebt, c.PointBalance, c.IsActive,
        c.CreatedAt, c.CreatedBy);
}
