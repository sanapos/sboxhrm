using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Thông tin công ty shop in trên báo giá / hợp đồng A4.</summary>
[ApiController]
[Route("api/pos/commercial-profile")]
[Authorize]
public class PosCommercialProfileController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    public record CommercialProfileDto(
        string? CompanyName,
        string? TaxCode,
        string? Address,
        string? Phone,
        string? Email,
        string? BankAccountNumber,
        string? BankName,
        string? BankAccountHolder,
        string? LegalRepresentative,
        string? LegalTitle,
        string? StampPngBase64 = null,
        string? LogoPngBase64 = null,
        string? DefaultTerms = null,
        string? WarrantyPolicy = null,
        DateTime? UpdatedAt = null);

    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SettingsHub", "PosQuotes", "PosSell")]
    public async Task<ActionResult<AppResponse<CommercialProfileDto>>> Get()
    {
        Response.Headers.CacheControl = "no-store";
        var storeId = RequiredStoreId;
        var p = await dbContext.PosStoreCommercialProfiles.IgnoreQueryFilters().AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .OrderByDescending(x => x.UpdatedAt)
            .FirstOrDefaultAsync();
        if (p == null)
        {
            var store = await dbContext.Stores.AsNoTracking()
                .FirstOrDefaultAsync(s => s.Id == storeId);
            var branch = await dbContext.Branches.AsNoTracking()
                .Where(b => b.StoreId == storeId && (b.IsHeadquarter || b.TaxCode != null))
                .OrderByDescending(b => b.IsHeadquarter)
                .FirstOrDefaultAsync();
            return Ok(AppResponse<CommercialProfileDto>.Success(new CommercialProfileDto(
                null,
                branch?.TaxCode,
                branch?.Address,
                branch?.Phone ?? store?.Phone,
                branch?.Email,
                null, null, null, null, "Giám đốc")));
        }
        return Ok(AppResponse<CommercialProfileDto>.Success(Map(p)));
    }

    [HttpGet("tax-lookup")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SettingsHub", "PosQuotes", "PosSell")]
    public async Task<ActionResult<AppResponse<object>>> LookupTax([FromQuery] string? taxCode)
    {
        var found = await VietQrBusinessLookup.LookupAsync(taxCode);
        if (!found.Ok)
            return Ok(AppResponse<object>.Fail(found.Message ?? "Không tra cứu được mã số thuế"));
        return Ok(AppResponse<object>.Success(VietQrBusinessLookup.ToDto(found)));
    }

    [HttpPut]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "SettingsHub", "PosQuotes", "PosSell")]
    public async Task<ActionResult<AppResponse<CommercialProfileDto>>> Save(
        [FromBody] CommercialProfileDto dto)
    {
        var storeId = RequiredStoreId;
        var p = await dbContext.PosStoreCommercialProfiles.IgnoreQueryFilters()
            .Where(x => x.StoreId == storeId)
            .OrderByDescending(x => x.UpdatedAt)
            .FirstOrDefaultAsync();
        if (p != null && p.Deleted != null)
        {
            p.Deleted = null;
            p.DeletedBy = null;
        }
        if (p == null)
        {
            p = new PosStoreCommercialProfile
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CreatedBy = CurrentUserEmail,
                IsActive = true,
            };
            dbContext.PosStoreCommercialProfiles.Add(p);
        }
        p.CompanyName = dto.CompanyName?.Trim();
        p.TaxCode = dto.TaxCode?.Trim();
        p.Address = dto.Address?.Trim();
        p.Phone = dto.Phone?.Trim();
        p.Email = dto.Email?.Trim();
        p.BankAccountNumber = dto.BankAccountNumber?.Trim();
        p.BankName = dto.BankName?.Trim();
        p.BankAccountHolder = dto.BankAccountHolder?.Trim();
        p.LegalRepresentative = dto.LegalRepresentative?.Trim();
        p.LegalTitle = string.IsNullOrWhiteSpace(dto.LegalTitle)
            ? "Giám đốc"
            : dto.LegalTitle.Trim();
        if (dto.StampPngBase64 != null)
        {
            var stamp = NormalizeStamp(dto.StampPngBase64);
            if (stamp == null)
                return BadRequest(AppResponse<CommercialProfileDto>.Fail(
                    "Ảnh con dấu quá lớn hoặc không đọc được. Dùng PNG dưới 700 KB."));
            p.StampPngBase64 = stamp.Length == 0 ? null : stamp;
        }
        if (dto.LogoPngBase64 != null)
        {
            var logo = NormalizeStamp(dto.LogoPngBase64);
            if (logo == null)
                return BadRequest(AppResponse<CommercialProfileDto>.Fail(
                    "Logo quá lớn hoặc không đọc được. Dùng ảnh dưới 700 KB."));
            p.LogoPngBase64 = logo.Length == 0 ? null : logo;
        }
        if (dto.DefaultTerms != null)
            p.DefaultTerms = string.IsNullOrWhiteSpace(dto.DefaultTerms) ? null : dto.DefaultTerms.Trim();
        if (dto.WarrantyPolicy != null)
            p.WarrantyPolicy = string.IsNullOrWhiteSpace(dto.WarrantyPolicy) ? null : dto.WarrantyPolicy.Trim();
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        p.IsActive = true;
        var entry = dbContext.Entry(p);
        if (entry.State == EntityState.Detached)
            dbContext.PosStoreCommercialProfiles.Attach(p);
        if (entry.State != EntityState.Added)
            entry.State = EntityState.Modified;
        await dbContext.SaveChangesAsync();
        var saved = await dbContext.PosStoreCommercialProfiles.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == p.Id && x.Deleted == null);
        if (saved == null || (saved.CompanyName ?? "") != (p.CompanyName ?? "")
            || (saved.BankAccountNumber ?? "") != (p.BankAccountNumber ?? ""))
            return StatusCode(500, AppResponse<CommercialProfileDto>.Fail(
                "Không ghi được thông tin công ty. Thử lại."));
        return Ok(AppResponse<CommercialProfileDto>.Success(Map(saved)));
    }

    static CommercialProfileDto Map(PosStoreCommercialProfile p) => new(
        p.CompanyName, p.TaxCode, p.Address, p.Phone, p.Email,
        p.BankAccountNumber, p.BankName, p.BankAccountHolder,
        p.LegalRepresentative, p.LegalTitle, p.StampPngBase64, p.LogoPngBase64,
        p.DefaultTerms, p.WarrantyPolicy, p.UpdatedAt);

    /// <summary>Chuỗi rỗng = xóa. Null = ảnh không hợp lệ.</summary>
    static string? NormalizeStamp(string raw)
    {
        var s = raw.Trim();
        if (s.Length == 0) return "";
        var comma = s.IndexOf(',');
        if (s.StartsWith("data:", StringComparison.OrdinalIgnoreCase) && comma > 0)
            s = s[(comma + 1)..].Trim();
        s = s.Replace(" ", "").Replace("\r", "").Replace("\n", "");
        if (s.Length > 1_200_000) return null;
        try
        {
            var bytes = Convert.FromBase64String(s);
            if (bytes.Length < 32 || bytes.Length > 700 * 1024) return null;
            return s;
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
