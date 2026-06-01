using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Transactions;
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
    [RequireModulePermission("BankAccount", ModulePermissionAction.View)]
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
    [RequireModulePermission("BankAccount", ModulePermissionAction.View)]
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
            return NotFound(AppResponse<BankAccountDto>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n ngÃ¢n hÃ ng"));

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
    [RequireModulePermission("BankAccount", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BankAccountDto>>> UpdateBankAccount(Guid id, [FromBody] UpdateBankAccountDto request)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (bankAccount == null)
            return NotFound(AppResponse<BankAccountDto>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n ngÃ¢n hÃ ng"));

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
            return NotFound(AppResponse<BankAccountDto>.Error("KhÃ´ng tÃ¬m tháº¥y tÃ i khoáº£n ngÃ¢n hÃ ng"));

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
    [RequireModulePermission("BankAccount", ModulePermissionAction.Delete)]
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
    [RequireModulePermission("BankAccount", ModulePermissionAction.View)]
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

        return Ok(AppResponse<List<TransactionCategoryDto>>.Success(categories));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch danh má»¥c dáº¡ng pháº³ng (flat list)
    /// </summary>
    [HttpGet("flat")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.View)]
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

        return Ok(AppResponse<List<TransactionCategoryDto>>.Success(categories!));
    }

    /// <summary>
    /// Táº¡o danh má»¥c má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> CreateCategory([FromBody] CreateTransactionCategoryDto request)
    {
        var storeId = RequiredStoreId;
        
        // Validate parent category
        if (request.ParentCategoryId.HasValue)
        {
            var parent = await context.TransactionCategories.FirstOrDefaultAsync(x => x.Id == request.ParentCategoryId.Value && x.StoreId == storeId);
            if (parent == null)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh má»¥c cha khÃ´ng tá»“n táº¡i"));
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
    [RequireModulePermission("BankAccount", ModulePermissionAction.View)]
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
            return NotFound(AppResponse<TransactionCategoryDto>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        return Ok(AppResponse<TransactionCategoryDto>.Success(category));
    }

    /// <summary>
    /// Cáº­p nháº­t danh má»¥c
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> UpdateCategory(Guid id, [FromBody] UpdateTransactionCategoryDto request)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<TransactionCategoryDto>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        if (category.IsSystem)
            return BadRequest(AppResponse<TransactionCategoryDto>.Error("KhÃ´ng thá»ƒ sá»­a danh má»¥c há»‡ thá»‘ng"));

        // Validate parent category
        if (request.ParentCategoryId.HasValue && request.ParentCategoryId.Value != id)
        {
            var parent = await context.TransactionCategories.FirstOrDefaultAsync(x => x.Id == request.ParentCategoryId.Value && x.StoreId == storeId);
            if (parent == null)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh má»¥c cha khÃ´ng tá»“n táº¡i"));
            if (parent.Type != category.Type)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh má»¥c cha khÃ´ng cÃ¹ng loáº¡i"));
        }

        category.Name = request.Name;
        category.Description = request.Description;
        category.Icon = request.Icon;
        category.Color = request.Color;
        category.SortOrder = request.SortOrder;
        category.ParentCategoryId = request.ParentCategoryId;
        category.IsActive = request.IsActive;
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
    [RequireModulePermission("BankAccount", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCategory(Guid id)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y danh má»¥c"));

        if (category.IsSystem)
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ xÃ³a danh má»¥c há»‡ thá»‘ng"));

        // Check if used
        var usedCount = await context.CashTransactions.CountAsync(x => x.CategoryId == id && x.IsActive);
        if (usedCount > 0)
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
    /// Khá»Ÿi táº¡o danh má»¥c máº·c Ä‘á»‹nh
    /// </summary>
    [HttpPost("init-default")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("BankAccount", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> InitDefaultCategories()
    {
        var storeId = RequiredStoreId;
        
        // Check if already initialized
        var existingCount = await context.TransactionCategories.CountAsync(x => x.StoreId == storeId && x.IsSystem);
        if (existingCount > 0)
            return Ok(AppResponse<bool>.Success(true));

        var defaultCategories = new List<TransactionCategory>
        {
            // === THU (Income) ===
            new() { Id = Guid.NewGuid(), Name = "BÃ¡n hÃ ng", Type = CashTransactionType.Income, Icon = "shopping_cart", Color = "#22C55E", IsSystem = true, IsActive = true, SortOrder = 1, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Dá»‹ch vá»¥", Type = CashTransactionType.Income, Icon = "build", Color = "#10B981", IsSystem = true, IsActive = true, SortOrder = 2, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "LÃ£i vay/Ä‘áº§u tÆ°", Type = CashTransactionType.Income, Icon = "trending_up", Color = "#14B8A6", IsSystem = true, IsActive = true, SortOrder = 3, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Cho thuÃª", Type = CashTransactionType.Income, Icon = "home", Color = "#06B6D4", IsSystem = true, IsActive = true, SortOrder = 4, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "HoÃ n tiá»n", Type = CashTransactionType.Income, Icon = "replay", Color = "#0EA5E9", IsSystem = true, IsActive = true, SortOrder = 5, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Thu khÃ¡c", Type = CashTransactionType.Income, Icon = "add_circle", Color = "#3B82F6", IsSystem = true, IsActive = true, SortOrder = 99, StoreId = storeId },
            
            // === CHI (Expense) ===
            new() { Id = Guid.NewGuid(), Name = "Nháº­p hÃ ng", Type = CashTransactionType.Expense, Icon = "inventory", Color = "#EF4444", IsSystem = true, IsActive = true, SortOrder = 1, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "LÆ°Æ¡ng nhÃ¢n viÃªn", Type = CashTransactionType.Expense, Icon = "people", Color = "#F97316", IsSystem = true, IsActive = true, SortOrder = 2, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Äiá»‡n/NÆ°á»›c/Internet", Type = CashTransactionType.Expense, Icon = "bolt", Color = "#F59E0B", IsSystem = true, IsActive = true, SortOrder = 3, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "ThuÃª máº·t báº±ng", Type = CashTransactionType.Expense, Icon = "storefront", Color = "#EAB308", IsSystem = true, IsActive = true, SortOrder = 4, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Váº­n chuyá»ƒn", Type = CashTransactionType.Expense, Icon = "local_shipping", Color = "#84CC16", IsSystem = true, IsActive = true, SortOrder = 5, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Marketing", Type = CashTransactionType.Expense, Icon = "campaign", Color = "#EC4899", IsSystem = true, IsActive = true, SortOrder = 6, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "VÄƒn phÃ²ng pháº©m", Type = CashTransactionType.Expense, Icon = "edit_note", Color = "#8B5CF6", IsSystem = true, IsActive = true, SortOrder = 7, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Báº£o trÃ¬/Sá»­a chá»¯a", Type = CashTransactionType.Expense, Icon = "handyman", Color = "#6366F1", IsSystem = true, IsActive = true, SortOrder = 8, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Thuáº¿/PhÃ­", Type = CashTransactionType.Expense, Icon = "receipt_long", Color = "#A855F7", IsSystem = true, IsActive = true, SortOrder = 9, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Chi khÃ¡c", Type = CashTransactionType.Expense, Icon = "remove_circle", Color = "#6B7280", IsSystem = true, IsActive = true, SortOrder = 99, StoreId = storeId },
        };

        context.TransactionCategories.AddRange(defaultCategories);
        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }
}

