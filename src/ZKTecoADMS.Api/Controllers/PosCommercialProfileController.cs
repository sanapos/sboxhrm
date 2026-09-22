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
        string? LegalTitle);

    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SettingsHub", "PosQuotes", "PosSell")]
    public async Task<ActionResult<AppResponse<CommercialProfileDto>>> Get()
    {
        var storeId = RequiredStoreId;
        var p = await dbContext.PosStoreCommercialProfiles.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
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
        var p = await dbContext.PosStoreCommercialProfiles
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
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
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<CommercialProfileDto>.Success(Map(p)));
    }

    static CommercialProfileDto Map(PosStoreCommercialProfile p) => new(
        p.CompanyName, p.TaxCode, p.Address, p.Phone, p.Email,
        p.BankAccountNumber, p.BankName, p.BankAccountHolder,
        p.LegalRepresentative, p.LegalTitle);
}
