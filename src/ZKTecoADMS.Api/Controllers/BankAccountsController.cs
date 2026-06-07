using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Transactions;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BankAccountsController(ZKTecoDbContext context) : AuthenticatedControllerBase
{
    /// <summary>
    /// Láº¥y danh sÃ¡ch tÃ i khoáº£n ngÃ¢n hÃ ng
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BankAccountDto>>>> GetBankAccounts()
    {
        var storeId = RequiredStoreId;
        
        // Láº¥y danh sÃ¡ch bank accounts liÃªn káº¿t qua transactions
        var bankAccounts = await context.BankAccounts
            .Where(x => x.StoreId == storeId && x.IsActive)
            .Select(x => new BankAccountDto
            {
                Id = x.Id,
                AccountName = x.AccountName,
                AccountNumber = x.AccountNumber,
                BankCode = x.BankCode,
                BankName = x.BankName,
                BankShortName = x.BankShortName,
                BranchName = x.BranchName,
                BankLogoUrl = x.BankLogoUrl,
                IsDefault = x.IsDefault,
                Note = x.Note,
                VietQRTemplate = x.VietQRTemplate,
                IsActive = x.IsActive,
                TransactionCount = x.Transactions.Count(t => t.IsActive)
            })
            .OrderByDescending(x => x.IsDefault)
            .ThenBy(x => x.BankName)
            .ToListAsync();

        return Ok(AppResponse<List<BankAccountDto>>.Success(bankAccounts));
    }

    /// <summary>
    /// Láº¥y chi tiáº¿t tÃ i khoáº£n ngÃ¢n hÃ ng
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<BankAccountDto>>> GetBankAccount(Guid id)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts
            .Where(x => x.Id == id && x.StoreId == storeId)
            .Select(x => new BankAccountDto
            {
                Id = x.Id,
                AccountName = x.AccountName,
                AccountNumber = x.AccountNumber,
                BankCode = x.BankCode,
                BankName = x.BankName,
                BankShortName = x.BankShortName,
                BranchName = x.BranchName,
                BankLogoUrl = x.BankLogoUrl,
                IsDefault = x.IsDefault,
                Note = x.Note,
                VietQRTemplate = x.VietQRTemplate,
                IsActive = x.IsActive,
                TransactionCount = x.Transactions.Count(t => t.IsActive)
            })
            .FirstOrDefaultAsync();

        if (bankAccount == null)
            return NotFound(AppResponse<BankAccountDto>.Error("Không tìm thấy tài khoản ngân hàng"));

        return Ok(AppResponse<BankAccountDto>.Success(bankAccount));
    }

    /// <summary>
    /// Táº¡o tÃ i khoáº£n ngÃ¢n hÃ ng má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BankAccountDto>>> CreateBankAccount([FromBody] CreateBankAccountDto request)
    {
        var storeId = RequiredStoreId;
        
        // If set as default, remove default from others
        if (request.IsDefault)
        {
            var existingDefaults = await context.BankAccounts.AsTracking().Where(x => x.StoreId == storeId && x.IsDefault).ToListAsync();
            foreach (var ba in existingDefaults)
                ba.IsDefault = false;
        }

        var bankAccount = new BankAccount
        {
            Id = Guid.NewGuid(),
            AccountName = request.AccountName,
            AccountNumber = request.AccountNumber,
            BankCode = request.BankCode,
            BankName = request.BankName,
            BankShortName = request.BankShortName,
            BranchName = request.BranchName,
            BankLogoUrl = request.BankLogoUrl ?? GetBankLogo(request.BankCode),
            IsDefault = request.IsDefault,
            Note = request.Note,
            VietQRTemplate = request.VietQRTemplate,
            IsActive = true,
            StoreId = storeId
        };

        context.BankAccounts.Add(bankAccount);
        await context.SaveChangesAsync();

        return await GetBankAccount(bankAccount.Id);
    }

    /// <summary>
    /// Cáº­p nháº­t tÃ i khoáº£n ngÃ¢n hÃ ng
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BankAccountDto>>> UpdateBankAccount(Guid id, [FromBody] UpdateBankAccountDto request)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (bankAccount == null)
            return NotFound(AppResponse<BankAccountDto>.Error("Không tìm thấy tài khoản ngân hàng"));

        // If set as default, remove default from others
        if (request.IsDefault && !bankAccount.IsDefault)
        {
            var existingDefaults = await context.BankAccounts
                .AsTracking()
                .Where(x => x.StoreId == storeId && x.IsDefault && x.Id != id)
                .ToListAsync();
            foreach (var ba in existingDefaults)
                ba.IsDefault = false;
        }

        bankAccount.AccountName = request.AccountName;
        bankAccount.BranchName = request.BranchName;
        bankAccount.IsDefault = request.IsDefault;
        bankAccount.Note = request.Note;
        bankAccount.VietQRTemplate = request.VietQRTemplate;
        bankAccount.IsActive = request.IsActive;
        bankAccount.LastModified = DateTime.UtcNow;

        await context.SaveChangesAsync();
        return await GetBankAccount(id);
    }

    /// <summary>
    /// Äáº·t tÃ i khoáº£n lÃ m máº·c Ä‘á»‹nh
    /// </summary>
    [HttpPut("{id}/set-default")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BankAccountDto>>> SetDefaultBankAccount(Guid id)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (bankAccount == null)
            return NotFound(AppResponse<BankAccountDto>.Error("Không tìm thấy tài khoản ngân hàng"));

        // Remove default from all others
        var existingDefaults = await context.BankAccounts
            .AsTracking()
            .Where(x => x.StoreId == storeId && x.IsDefault)
            .ToListAsync();
        foreach (var ba in existingDefaults)
            ba.IsDefault = false;

        bankAccount.IsDefault = true;
        bankAccount.LastModified = DateTime.UtcNow;

        await context.SaveChangesAsync();
        return await GetBankAccount(id);
    }

    /// <summary>
    /// XÃ³a tÃ i khoáº£n ngÃ¢n hÃ ng (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBankAccount(Guid id)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (bankAccount == null)
            return NotFound(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n ngÃ¢n hÃ ng"));

        // Check if used in any transaction
        var usedCount = await context.CashTransactions.CountAsync(x => x.BankAccountId == id && x.IsActive);
        if (usedCount > 0)
        {
            // Just deactivate
            bankAccount.IsActive = false;
            bankAccount.LastModified = DateTime.UtcNow;
        }
        else
        {
            context.BankAccounts.Remove(bankAccount);
        }

        await context.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch ngÃ¢n hÃ ng há»— trá»£ VietQR
    /// </summary>
    [HttpGet("vietqr-banks")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public ActionResult<AppResponse<List<object>>> GetVietQRBanks()
    {
        var banks = VietQRBanks.Banks.Select(b => new
        {
            code = b.Key,
            bin = b.Value.BIN,
            name = b.Value.Name,
            shortName = b.Value.ShortName,
            logo = b.Value.Logo
        }).ToList<object>();

        return Ok(AppResponse<List<object>>.Success(banks));
    }

    private string GetBankLogo(string bankCode)
    {
        if (VietQRBanks.Banks.TryGetValue(bankCode, out var bankInfo))
            return bankInfo.Logo;
        return "";
    }
}

[ApiController]
[Route("api/[controller]")]
public class TransactionCategoriesController(ZKTecoDbContext context, ICacheService cacheService) : AuthenticatedControllerBase
{
    /// <summary>
    /// Láº¥y danh sÃ¡ch danh má»¥c giao dá»‹ch
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TransactionCategoryDto>>>> GetCategories(
        [FromQuery] CashTransactionType? type = null,
        [FromQuery] bool includeInactive = false)
    {
        var storeId = RequiredStoreId;
        var query = context.TransactionCategories
            .Include(x => x.ParentCategory)
            .Include(x => x.SubCategories)
            .Where(x => x.StoreId == storeId && x.ParentCategoryId == null)
            .AsQueryable();

        if (!includeInactive)
            query = query.Where(x => x.IsActive);
        
        if (type.HasValue)
            query = query.Where(x => x.Type == type.Value);

        var categories = await query
            .OrderBy(x => x.SortOrder)
            .ThenBy(x => x.Name)
            .Select(x => new TransactionCategoryDto
            {
                Id = x.Id,
                Name = x.Name,
                Description = x.Description,
                Type = x.Type,
                Icon = x.Icon,
                Color = x.Color,
                SortOrder = x.SortOrder,
                ParentCategoryId = x.ParentCategoryId,
                ParentCategoryName = x.ParentCategory != null ? x.ParentCategory.Name : null,
                IsSystem = x.IsSystem,
                IsActive = x.IsActive,
                TransactionCount = x.Transactions.Count(t => t.IsActive),
                SubCategories = x.SubCategories
                    .Where(sc => sc.IsActive)
                    .OrderBy(sc => sc.SortOrder)
                    .Select(sc => new TransactionCategoryDto
                    {
                        Id = sc.Id,
                        Name = sc.Name,
                        Description = sc.Description,
                        Type = sc.Type,
                        Icon = sc.Icon,
                        Color = sc.Color,
                        SortOrder = sc.SortOrder,
                        ParentCategoryId = sc.ParentCategoryId,
                        IsSystem = sc.IsSystem,
                        IsActive = sc.IsActive,
                        TransactionCount = sc.Transactions.Count(t => t.IsActive)
                    })
                    .ToList()
            })
            .ToListAsync();

        categories = categories.Select(FixCategoryDtoEncoding).ToList();

        return Ok(AppResponse<List<TransactionCategoryDto>>.Success(categories));
    }

    /// <summary>
    /// Lấy danh sách danh mục dạng phẳng (flat list)
    /// </summary>
    [HttpGet("flat")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TransactionCategoryDto>>>> GetCategoriesFlat(
        [FromQuery] CashTransactionType? type = null)
    {
        var storeId = RequiredStoreId;
        var cacheKey = $"categories_flat_{storeId}_{type?.ToString() ?? "all"}";
        
        var categories = await cacheService.GetOrCreateAsync(cacheKey, async () =>
        {
            var query = context.TransactionCategories
                .Include(x => x.ParentCategory)
                .Where(x => x.StoreId == storeId && x.IsActive)
                .AsQueryable();
            
            if (type.HasValue)
                query = query.Where(x => x.Type == type.Value);

            return await query
                .OrderBy(x => x.Type)
                .ThenBy(x => x.SortOrder)
                .ThenBy(x => x.Name)
                .Select(x => new TransactionCategoryDto
                {
                    Id = x.Id,
                    Name = x.Name,
                    Description = x.Description,
                    Type = x.Type,
                    Icon = x.Icon,
                    Color = x.Color,
                    SortOrder = x.SortOrder,
                    ParentCategoryId = x.ParentCategoryId,
                    ParentCategoryName = x.ParentCategory != null ? x.ParentCategory.Name : null,
                    IsSystem = x.IsSystem,
                    IsActive = x.IsActive,
                    TransactionCount = x.Transactions.Count(t => t.IsActive)
                })
                .ToListAsync();
        }, TimeSpan.FromMinutes(10));

        var fixedCategories = categories!.Select(FixCategoryDtoEncoding).ToList();
        return Ok(AppResponse<List<TransactionCategoryDto>>.Success(fixedCategories));
    }

    /// <summary>
    /// Táº¡o danh má»¥c má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> CreateCategory([FromBody] CreateTransactionCategoryDto request)
    {
        var storeId = RequiredStoreId;
        
        // Validate parent category
        if (request.ParentCategoryId.HasValue)
        {
            var parent = await context.TransactionCategories.FirstOrDefaultAsync(x => x.Id == request.ParentCategoryId.Value && x.StoreId == storeId);
            if (parent == null)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh mục cha không tồn tại"));
            if (parent.Type != request.Type)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh má»¥c cha khÃ´ng cÃ¹ng loáº¡i"));
        }

        var category = new TransactionCategory
        {
            Id = Guid.NewGuid(),
            Name = request.Name,
            Description = request.Description,
            Type = request.Type,
            Icon = request.Icon,
            Color = request.Color,
            SortOrder = request.SortOrder,
            ParentCategoryId = request.ParentCategoryId,
            IsSystem = false,
            IsActive = true,
            StoreId = storeId
        };

        context.TransactionCategories.Add(category);
        await context.SaveChangesAsync();
        cacheService.RemoveByPrefix("categories_flat_");

        return await GetCategory(category.Id);
    }

    /// <summary>
    /// Láº¥y chi tiáº¿t danh má»¥c
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> GetCategory(Guid id)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories
            .Include(x => x.ParentCategory)
            .Where(x => x.Id == id && x.StoreId == storeId)
            .Select(x => new TransactionCategoryDto
            {
                Id = x.Id,
                Name = x.Name,
                Description = x.Description,
                Type = x.Type,
                Icon = x.Icon,
                Color = x.Color,
                SortOrder = x.SortOrder,
                ParentCategoryId = x.ParentCategoryId,
                ParentCategoryName = x.ParentCategory != null ? x.ParentCategory.Name : null,
                IsSystem = x.IsSystem,
                IsActive = x.IsActive,
                TransactionCount = x.Transactions.Count(t => t.IsActive)
            })
            .FirstOrDefaultAsync();

        if (category == null)
            return NotFound(AppResponse<TransactionCategoryDto>.Error("Không tìm thấy danh mục"));

        return Ok(AppResponse<TransactionCategoryDto>.Success(FixCategoryDtoEncoding(category)));
    }

    /// <summary>
    /// Cáº­p nháº­t danh má»¥c
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> UpdateCategory(Guid id, [FromBody] UpdateTransactionCategoryDto request)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<TransactionCategoryDto>.Error("Không tìm thấy danh mục"));

        // Validate parent category
        if (request.ParentCategoryId.HasValue && request.ParentCategoryId.Value != id)
        {
            var parent = await context.TransactionCategories.FirstOrDefaultAsync(x => x.Id == request.ParentCategoryId.Value && x.StoreId == storeId);
            if (parent == null)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh mục cha không tồn tại"));
            if (parent.Type != category.Type)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh má»¥c cha khÃ´ng cÃ¹ng loáº¡i"));
        }

        category.Name = request.Name;
        category.Description = request.Description;
        category.Icon = request.Icon;
        category.Color = request.Color;
        category.SortOrder = request.SortOrder;
        category.IsActive = request.IsActive;
        if (!category.IsSystem)
            category.ParentCategoryId = request.ParentCategoryId;
        category.LastModified = DateTime.UtcNow;

        await context.SaveChangesAsync();
        cacheService.RemoveByPrefix("categories_flat_");
        return await GetCategory(id);
    }

    /// <summary>
    /// XÃ³a danh má»¥c (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCategory(Guid id)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        var usedCount = await context.CashTransactions.CountAsync(x => x.CategoryId == id && x.IsActive);
        if (category.IsSystem || usedCount > 0)
        {
            category.IsActive = false;
            category.LastModified = DateTime.UtcNow;
        }
        else
        {
            context.TransactionCategories.Remove(category);
        }

        await context.SaveChangesAsync();
        cacheService.RemoveByPrefix("categories_flat_");
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Đồng bộ danh mục hệ thống Thu + Chi (bổ sung thiếu, sửa tên/type, kích hoạt lại).
    /// </summary>
    [HttpPost("init-default")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> InitDefaultCategories()
    {
        var storeId = RequiredStoreId;
        var existing = await context.TransactionCategories
            .Where(x => x.StoreId == storeId)
            .ToListAsync();

        var added = 0;
        var repaired = 0;
        var reactivated = 0;
        var typeFixed = 0;

        foreach (var def in VietnameseEncodingFix.DefaultTransactionCategories())
        {
            // Khớp theo tên (kể cả type sai trong DB)
            var match = existing.FirstOrDefault(c =>
                VietnameseEncodingFix.CategoryNamesMatch(c.Name, def.Name));

            // Khớp theo hệ thống + loại + thứ tự (tên cũ bị lỗi font nặng)
            match ??= existing.FirstOrDefault(c =>
                c.IsSystem && c.Type == def.Type && c.SortOrder == def.SortOrder);

            if (match == null)
            {
                var created = new TransactionCategory
                {
                    Id = Guid.NewGuid(),
                    Name = def.Name,
                    Type = def.Type,
                    Icon = def.Icon,
                    Color = def.Color,
                    IsSystem = true,
                    IsActive = true,
                    SortOrder = def.SortOrder,
                    StoreId = storeId,
                };
                context.TransactionCategories.Add(created);
                existing.Add(created);
                added++;
                continue;
            }

            var changed = false;

            if (!VietnameseEncodingFix.CategoryNamesMatch(match.Name, def.Name))
            {
                match.Name = def.Name;
                repaired++;
                changed = true;
            }

            if (match.Type != def.Type)
            {
                match.Type = def.Type;
                typeFixed++;
                changed = true;
            }

            if (match.Icon != def.Icon)
            {
                match.Icon = def.Icon;
                changed = true;
            }

            if (match.Color != def.Color)
            {
                match.Color = def.Color;
                changed = true;
            }

            if (match.SortOrder != def.SortOrder)
            {
                match.SortOrder = def.SortOrder;
                changed = true;
            }

            if (!match.IsActive)
            {
                match.IsActive = true;
                reactivated++;
                changed = true;
            }

            if (changed)
                match.LastModified = DateTime.UtcNow;
        }

        if (context.ChangeTracker.HasChanges())
        {
            await context.SaveChangesAsync();
            cacheService.RemoveByPrefix("categories_flat_");
        }

        var incomeCount = existing.Count(c =>
            c.IsActive && c.Type == CashTransactionType.Income && c.IsSystem);
        var expenseCount = existing.Count(c =>
            c.IsActive && c.Type == CashTransactionType.Expense && c.IsSystem);

        return Ok(AppResponse<object>.Success(new
        {
            added,
            repaired,
            reactivated,
            typeFixed,
            systemIncome = incomeCount,
            systemExpense = expenseCount,
        }));
    }

    /// <summary>
    /// Sửa tên danh mục bị lỗi font (mojibake) trong DB.
    /// </summary>
    [HttpPost("repair-encoding")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RepairCategoryEncoding()
    {
        var storeId = RequiredStoreId;
        var categories = await context.TransactionCategories
            .Where(x => x.StoreId == storeId)
            .ToListAsync();

        var updated = 0;
        foreach (var cat in categories)
        {
            var fixedName = VietnameseEncodingFix.TryFix(cat.Name);
            var fixedDesc = cat.Description != null ? VietnameseEncodingFix.TryFix(cat.Description) : null;
            if (fixedName != cat.Name || fixedDesc != cat.Description)
            {
                cat.Name = fixedName;
                if (fixedDesc != null) cat.Description = fixedDesc;
                cat.LastModified = DateTime.UtcNow;
                updated++;
            }
        }

        if (updated > 0)
        {
            await context.SaveChangesAsync();
            cacheService.RemoveByPrefix("categories_flat_");
        }

        return Ok(AppResponse<object>.Success(new { updated, total = categories.Count }));
    }

    private static TransactionCategoryDto FixCategoryDtoEncoding(TransactionCategoryDto dto)
        => dto with
        {
            Name = VietnameseEncodingFix.TryFix(dto.Name),
            Description = dto.Description != null
                ? VietnameseEncodingFix.TryFix(dto.Description)
                : null,
            ParentCategoryName = dto.ParentCategoryName != null
                ? VietnameseEncodingFix.TryFix(dto.ParentCategoryName)
                : null,
            SubCategories = dto.SubCategories.Select(FixCategoryDtoEncoding).ToList()
        };
}

