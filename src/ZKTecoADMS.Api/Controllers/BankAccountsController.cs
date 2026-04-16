using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
    /// Lấy danh sách tài khoản ngân hàng
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<List<BankAccountDto>>>> GetBankAccounts()
    {
        var storeId = RequiredStoreId;
        
        // Lấy danh sách bank accounts liên kết qua transactions
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
    /// Lấy chi tiết tài khoản ngân hàng
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Tạo tài khoản ngân hàng mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Cập nhật tài khoản ngân hàng
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Đặt tài khoản làm mặc định
    /// </summary>
    [HttpPut("{id}/set-default")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Xóa tài khoản ngân hàng (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBankAccount(Guid id)
    {
        var storeId = RequiredStoreId;
        var bankAccount = await context.BankAccounts.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (bankAccount == null)
            return NotFound(AppResponse<bool>.Error("Không tìm thấy tài khoản ngân hàng"));

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
    /// Lấy danh sách ngân hàng hỗ trợ VietQR
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
    /// Lấy danh sách danh mục giao dịch
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Lấy danh sách danh mục dạng phẳng (flat list)
    /// </summary>
    [HttpGet("flat")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Tạo danh mục mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh mục cha không cùng loại"));
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
    /// Lấy chi tiết danh mục
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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

        return Ok(AppResponse<TransactionCategoryDto>.Success(category));
    }

    /// <summary>
    /// Cập nhật danh mục
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<TransactionCategoryDto>>> UpdateCategory(Guid id, [FromBody] UpdateTransactionCategoryDto request)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<TransactionCategoryDto>.Error("Không tìm thấy danh mục"));

        if (category.IsSystem)
            return BadRequest(AppResponse<TransactionCategoryDto>.Error("Không thể sửa danh mục hệ thống"));

        // Validate parent category
        if (request.ParentCategoryId.HasValue && request.ParentCategoryId.Value != id)
        {
            var parent = await context.TransactionCategories.FirstOrDefaultAsync(x => x.Id == request.ParentCategoryId.Value && x.StoreId == storeId);
            if (parent == null)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh mục cha không tồn tại"));
            if (parent.Type != category.Type)
                return BadRequest(AppResponse<TransactionCategoryDto>.Error("Danh mục cha không cùng loại"));
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
    /// Xóa danh mục (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCategory(Guid id)
    {
        var storeId = RequiredStoreId;
        var category = await context.TransactionCategories.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (category == null)
            return NotFound(AppResponse<bool>.Error("Không tìm thấy danh mục"));

        if (category.IsSystem)
            return BadRequest(AppResponse<bool>.Error("Không thể xóa danh mục hệ thống"));

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
    /// Khởi tạo danh mục mặc định
    /// </summary>
    [HttpPost("init-default")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
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
            new() { Id = Guid.NewGuid(), Name = "Bán hàng", Type = CashTransactionType.Income, Icon = "shopping_cart", Color = "#22C55E", IsSystem = true, IsActive = true, SortOrder = 1, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Dịch vụ", Type = CashTransactionType.Income, Icon = "build", Color = "#10B981", IsSystem = true, IsActive = true, SortOrder = 2, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Lãi vay/đầu tư", Type = CashTransactionType.Income, Icon = "trending_up", Color = "#14B8A6", IsSystem = true, IsActive = true, SortOrder = 3, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Cho thuê", Type = CashTransactionType.Income, Icon = "home", Color = "#06B6D4", IsSystem = true, IsActive = true, SortOrder = 4, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Hoàn tiền", Type = CashTransactionType.Income, Icon = "replay", Color = "#0EA5E9", IsSystem = true, IsActive = true, SortOrder = 5, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Thu khác", Type = CashTransactionType.Income, Icon = "add_circle", Color = "#3B82F6", IsSystem = true, IsActive = true, SortOrder = 99, StoreId = storeId },
            
            // === CHI (Expense) ===
            new() { Id = Guid.NewGuid(), Name = "Nhập hàng", Type = CashTransactionType.Expense, Icon = "inventory", Color = "#EF4444", IsSystem = true, IsActive = true, SortOrder = 1, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Lương nhân viên", Type = CashTransactionType.Expense, Icon = "people", Color = "#F97316", IsSystem = true, IsActive = true, SortOrder = 2, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Điện/Nước/Internet", Type = CashTransactionType.Expense, Icon = "bolt", Color = "#F59E0B", IsSystem = true, IsActive = true, SortOrder = 3, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Thuê mặt bằng", Type = CashTransactionType.Expense, Icon = "storefront", Color = "#EAB308", IsSystem = true, IsActive = true, SortOrder = 4, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Vận chuyển", Type = CashTransactionType.Expense, Icon = "local_shipping", Color = "#84CC16", IsSystem = true, IsActive = true, SortOrder = 5, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Marketing", Type = CashTransactionType.Expense, Icon = "campaign", Color = "#EC4899", IsSystem = true, IsActive = true, SortOrder = 6, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Văn phòng phẩm", Type = CashTransactionType.Expense, Icon = "edit_note", Color = "#8B5CF6", IsSystem = true, IsActive = true, SortOrder = 7, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Bảo trì/Sửa chữa", Type = CashTransactionType.Expense, Icon = "handyman", Color = "#6366F1", IsSystem = true, IsActive = true, SortOrder = 8, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Thuế/Phí", Type = CashTransactionType.Expense, Icon = "receipt_long", Color = "#A855F7", IsSystem = true, IsActive = true, SortOrder = 9, StoreId = storeId },
            new() { Id = Guid.NewGuid(), Name = "Chi khác", Type = CashTransactionType.Expense, Icon = "remove_circle", Color = "#6B7280", IsSystem = true, IsActive = true, SortOrder = 99, StoreId = storeId },
        };

        context.TransactionCategories.AddRange(defaultCategories);
        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }
}
