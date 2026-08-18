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

[ApiController]
[Route("api/pos/customers")]
[Authorize]
public partial class PosCustomersController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record CustomerDto(
        Guid Id, string CustomerCode, string Name, string? Phone, string? Email,
        string? Address, string? Province, string? Ward,
        string? CompanyName, string? TaxCode, string? Note,
        DateTime? Birthday, string? DeliveryAddress,
        decimal TotalPurchase, decimal CurrentDebt, decimal PointBalance, bool IsActive,
        DateTime CreatedAt, string? CreatedBy);

    public record CustomerSaveDto(
        string Name, string? Phone, string? Email, string? Address,
        string? Province, string? Ward, string? CompanyName, string? TaxCode, string? Note,
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
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null);
        if (activeOnly != false) query = query.Where(c => c.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(c =>
                c.Name.ToLower().Contains(s) ||
                c.CustomerCode.ToLower().Contains(s) ||
                (c.Phone != null && c.Phone.Contains(s)) ||
                (c.TaxCode != null && c.TaxCode.ToLower().Contains(s)));
        }
        if (debtFrom.HasValue) query = query.Where(c => c.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) query = query.Where(c => c.CurrentDebt <= debtTo);
        if (purchaseFrom.HasValue) query = query.Where(c => c.TotalPurchase >= purchaseFrom);
        if (purchaseTo.HasValue) query = query.Where(c => c.TotalPurchase <= purchaseTo);
        if (hasDebt == true) query = query.Where(c => c.CurrentDebt > 0);

        var total = await query.CountAsync();
        var sumDebt = await query.SumAsync(c => c.CurrentDebt);
        var sumPurchase = await query.SumAsync(c => c.TotalPurchase);
        var items = await query.OrderByDescending(c => c.CurrentDebt).ThenBy(c => c.Name)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(c => MapCustomer(c))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, sumDebt, sumPurchase, items }));
    }

    /// Tra cứu MST (CQT qua VietQR) — điền tên đơn vị / địa chỉ xuất HĐĐT.
    [HttpGet("tax-lookup")]
    public async Task<ActionResult<AppResponse<object>>> LookupTax([FromQuery] string? taxCode)
    {
        var code = NormalizeTaxCode(taxCode);
        if (code == null)
            return BadRequest(AppResponse<object>.Fail(
                "Mã số thuế không hợp lệ (10 số, hoặc 10-3 chi nhánh)"));
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            http.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json");
            using var resp = await http.GetAsync($"https://api.vietqr.io/v2/business/{code}");
            var raw = await resp.Content.ReadAsStringAsync();
            if (string.IsNullOrWhiteSpace(raw))
                return Ok(AppResponse<object>.Fail("Không tra cứu được mã số thuế"));
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var apiCode = root.TryGetProperty("code", out var cEl) ? cEl.GetString() : null;
            if (apiCode != "00" ||
                !root.TryGetProperty("data", out var data) ||
                data.ValueKind != System.Text.Json.JsonValueKind.Object)
            {
                return Ok(AppResponse<object>.Fail("Không tìm thấy mã số thuế"));
            }

            static string? Read(System.Text.Json.JsonElement obj, string key) =>
                obj.TryGetProperty(key, out var p) && p.ValueKind == System.Text.Json.JsonValueKind.String
                    ? p.GetString()
                    : null;

            return Ok(AppResponse<object>.Success(new
            {
                taxCode = Read(data, "id") ?? code,
                name = Read(data, "name"),
                internationalName = Read(data, "internationalName"),
                shortName = Read(data, "shortName"),
                address = Read(data, "address"),
            }));
        }
        catch
        {
            return Ok(AppResponse<object>.Fail("Không tra cứu được MST — kiểm tra mạng rồi thử lại"));
        }
    }

    static string? NormalizeTaxCode(string? raw)
    {
        var s = (raw ?? "").Trim().Replace(" ", "").Replace(".", "");
        if (s.Length == 10 && s.All(char.IsDigit)) return s;
        if (s.Length == 14 && s[10] == '-' &&
            s[..10].All(char.IsDigit) && s[11..].All(char.IsDigit))
            return s;
        if (s.Length == 13 && s.All(char.IsDigit))
            return $"{s[..10]}-{s[10..]}";
        return null;
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

        c.Name = name;
        c.Phone = dto.Phone?.Trim();
        c.Email = dto.Email?.Trim();
        c.Address = dto.Address?.Trim();
        c.Province = dto.Province?.Trim();
        c.Ward = dto.Ward?.Trim();
        c.CompanyName = dto.CompanyName?.Trim();
        c.TaxCode = dto.TaxCode?.Trim();
        c.Birthday = dto.Birthday?.Date;
        c.DeliveryAddress = dto.DeliveryAddress?.Trim();
        c.Note = dto.Note?.Trim();
        c.UpdatedAt = DateTime.UtcNow;
        c.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CustomerDto>.Success(MapCustomer(c)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosCustomers", ModulePermissionAction.Edit)]
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
        c.CompanyName, c.TaxCode, c.Note, c.Birthday, c.DeliveryAddress,
        c.TotalPurchase, c.CurrentDebt, c.PointBalance, c.IsActive,
        c.CreatedAt, c.CreatedBy);
}
