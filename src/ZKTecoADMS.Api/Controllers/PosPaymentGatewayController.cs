using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Api.Services.PaymentGateway;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/payment-gateway")]
[Authorize]
public class PosPaymentGatewayController(
    ZKTecoDbContext db,
    IPosPaymentGatewayService gateway,
    IPosNotificationCreditService creditService,
    IPosPlatformNotificationCreditService platformCreditService,
    IPosPlatformTingeeSettingService platformTingeeService,
    ITingeeMerchantProvisioningService tingeeProvision) : AuthenticatedControllerBase
{
    private bool TryGetStoreId(out Guid storeId)
    {
        storeId = Guid.Empty;
        if (CurrentStoreId is { } sid && sid != Guid.Empty)
        {
            storeId = sid;
            return true;
        }
        return false;
    }

    [HttpGet("settings")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PaymentGatewaySettingDto>>> GetSettings(CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<PaymentGatewaySettingDto>.Fail("Thiếu cửa hàng"));
        var dto = await gateway.GetSettingsAsync(storeId, ct);
        if (dto == null)
        {
            dto = new PaymentGatewaySettingDto(
                PosPaymentNotifyProvider.VietQr.ToString(),
                false, null, false, null, null, null, false, false);
        }
        return Ok(AppResponse<PaymentGatewaySettingDto>.Success(dto));
    }

    [HttpPut("settings")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PaymentGatewaySettingDto>>> UpsertSettings(
        [FromBody] PaymentGatewaySettingUpsertRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<PaymentGatewaySettingDto>.Fail("Thiếu cửa hàng"));
        var dto = await gateway.UpsertSettingsAsync(storeId, req, CurrentUserEmail, ct);
        return Ok(AppResponse<PaymentGatewaySettingDto>.Success(dto));
    }

    [HttpGet("credits")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationCreditBalanceDto>>> GetCredits(CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<NotificationCreditBalanceDto>.Fail("Thiếu cửa hàng"));
        var bal = await creditService.GetBalanceAsync(storeId, ct);
        return Ok(AppResponse<NotificationCreditBalanceDto>.Success(bal));
    }

    [HttpGet("credit-packages")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<NotificationCreditPackageDto>>>> ListPublicPackages(
        CancellationToken ct)
    {
        var rows = await db.PosNotificationCreditPackages.AsNoTracking()
            .Where(x => x.IsActive && x.IsPublic && x.Deleted == null)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Price)
            .Select(x => new NotificationCreditPackageDto(
                x.Id, x.Name, x.CreditCount, x.Price, x.Description, x.IsActive, x.IsPublic, x.SortOrder))
            .ToListAsync(ct);
        return Ok(AppResponse<List<NotificationCreditPackageDto>>.Success(rows));
    }

    [HttpGet("credit-ledgers")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<NotificationCreditLedgerDto>>>> ListCreditLedgers(
        [FromQuery] int limit = 50,
        CancellationToken ct = default)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<NotificationCreditLedgerDto>>.Fail("Thiếu cửa hàng"));

        limit = Math.Clamp(limit, 1, 200);
        var rows = await db.PosNotificationCreditLedgers.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .OrderByDescending(x => x.CreatedAt)
            .Take(limit)
            .Select(x => new NotificationCreditLedgerDto(
                x.Id,
                x.Delta,
                x.BalanceAfter,
                x.Source.ToString(),
                x.ProviderTransactionCode,
                x.Note,
                x.CreatedAt))
            .ToListAsync(ct);
        return Ok(AppResponse<List<NotificationCreditLedgerDto>>.Success(rows));
    }

    [HttpPost("credit-purchases")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<NotificationCreditPurchaseDto>>> CreateCreditPurchase(
        [FromBody] CreateCreditPurchaseRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<NotificationCreditPurchaseDto>.Fail("Thiếu cửa hàng"));
        try
        {
            var dto = await gateway.CreateCreditPurchaseAsync(storeId, req, CurrentUserEmail, ct);
            return Ok(AppResponse<NotificationCreditPurchaseDto>.Success(dto));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<NotificationCreditPurchaseDto>.Fail(ex.Message));
        }
    }

    [HttpGet("credit-purchases")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<NotificationCreditPurchaseDto>>>> ListCreditPurchases(
        [FromQuery] string? status,
        [FromQuery] int limit = 20,
        CancellationToken ct = default)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<NotificationCreditPurchaseDto>>.Fail("Thiếu cửa hàng"));
        var rows = await gateway.ListCreditPurchasesAsync(storeId, status, limit, ct);
        return Ok(AppResponse<List<NotificationCreditPurchaseDto>>.Success(rows));
    }

    [HttpGet("credit-purchases/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationCreditPurchaseDto>>> GetCreditPurchase(
        Guid id, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<NotificationCreditPurchaseDto>.Fail("Thiếu cửa hàng"));
        var dto = await gateway.GetCreditPurchaseAsync(storeId, id, ct);
        if (dto == null)
            return NotFound(AppResponse<NotificationCreditPurchaseDto>.Fail("Không tìm thấy đơn mua credit"));
        return Ok(AppResponse<NotificationCreditPurchaseDto>.Success(dto));
    }

    [HttpPost("transfer-intents")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TransferPaymentIntentDto>>> CreateIntent(
        [FromBody] CreateTransferIntentRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TransferPaymentIntentDto>.Fail("Thiếu cửa hàng"));
        try
        {
            var dto = await gateway.CreateTransferIntentAsync(storeId, req, CurrentUserEmail, ct);
            return Ok(AppResponse<TransferPaymentIntentDto>.Success(dto));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<TransferPaymentIntentDto>.Fail(ex.Message));
        }
    }

    [HttpGet("transfer-intents")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TransferPaymentIntentDto>>>> ListIntents(
        [FromQuery] string? status,
        [FromQuery] int limit = 50,
        CancellationToken ct = default)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<TransferPaymentIntentDto>>.Fail("Thiếu cửa hàng"));
        var rows = await gateway.ListTransferIntentsAsync(storeId, status, limit, ct);
        return Ok(AppResponse<List<TransferPaymentIntentDto>>.Success(rows));
    }

    [HttpGet("transfer-intents/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TransferPaymentIntentDto>>> GetIntent(Guid id, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TransferPaymentIntentDto>.Fail("Thiếu cửa hàng"));
        var dto = await gateway.GetTransferIntentAsync(storeId, id, ct);
        if (dto == null)
            return NotFound(AppResponse<TransferPaymentIntentDto>.Fail("Không tìm thấy"));
        return Ok(AppResponse<TransferPaymentIntentDto>.Success(dto));
    }

    [HttpPost("transfer-intents/{id:guid}/complete")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TransferPaymentIntentDto>>> CompleteIntent(
        Guid id, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TransferPaymentIntentDto>.Fail("Thiếu cửa hàng"));
        var row = await db.PosTransferPaymentIntents.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null, ct);
        if (row == null)
            return NotFound(AppResponse<TransferPaymentIntentDto>.Fail("Không tìm thấy"));
        if (row.Status != PosTransferPaymentIntentStatus.Confirmed)
            return BadRequest(AppResponse<TransferPaymentIntentDto>.Fail("Đơn chưa được xác nhận chuyển khoản"));
        row.Status = PosTransferPaymentIntentStatus.Completed;
        row.CompletedAt = DateTime.UtcNow;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);
        var dto = await gateway.GetTransferIntentAsync(storeId, id, ct);
        return Ok(AppResponse<TransferPaymentIntentDto>.Success(dto!));
    }

    // ── SuperAdmin: quản lý gói & cấp credit ────────────────────────────────

    [HttpGet("admin/credit-packages")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<List<NotificationCreditPackageDto>>>> AdminListPackages(
        CancellationToken ct)
    {
        var rows = await db.PosNotificationCreditPackages.AsNoTracking()
            .Where(x => x.Deleted == null)
            .OrderBy(x => x.SortOrder).ThenBy(x => x.Name)
            .Select(x => new NotificationCreditPackageDto(
                x.Id, x.Name, x.CreditCount, x.Price, x.Description, x.IsActive, x.IsPublic, x.SortOrder))
            .ToListAsync(ct);
        return Ok(AppResponse<List<NotificationCreditPackageDto>>.Success(rows));
    }

    public record UpsertCreditPackageRequest(
        string Name, int CreditCount, decimal Price, string? Description,
        bool IsActive = true, bool IsPublic = true, int SortOrder = 0);

    [HttpPost("admin/credit-packages")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<NotificationCreditPackageDto>>> AdminCreatePackage(
        [FromBody] UpsertCreditPackageRequest req, CancellationToken ct)
    {
        var pkg = new PosNotificationCreditPackage
        {
            Id = Guid.NewGuid(),
            Name = req.Name.Trim(),
            CreditCount = Math.Max(1, req.CreditCount),
            Price = Math.Max(0, req.Price),
            Description = req.Description?.Trim(),
            IsActive = req.IsActive,
            IsPublic = req.IsPublic,
            SortOrder = req.SortOrder,
            CreatedBy = CurrentUserEmail,
        };
        db.PosNotificationCreditPackages.Add(pkg);
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<NotificationCreditPackageDto>.Success(new NotificationCreditPackageDto(
            pkg.Id, pkg.Name, pkg.CreditCount, pkg.Price, pkg.Description,
            pkg.IsActive, pkg.IsPublic, pkg.SortOrder)));
    }

    [HttpPut("admin/credit-packages/{id:guid}")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<NotificationCreditPackageDto>>> AdminUpdatePackage(
        Guid id, [FromBody] UpsertCreditPackageRequest req, CancellationToken ct)
    {
        var pkg = await db.PosNotificationCreditPackages.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null, ct);
        if (pkg == null)
            return NotFound(AppResponse<NotificationCreditPackageDto>.Fail("Không tìm thấy gói"));
        pkg.Name = req.Name.Trim();
        pkg.CreditCount = Math.Max(1, req.CreditCount);
        pkg.Price = Math.Max(0, req.Price);
        pkg.Description = req.Description?.Trim();
        pkg.IsActive = req.IsActive;
        pkg.IsPublic = req.IsPublic;
        pkg.SortOrder = req.SortOrder;
        pkg.UpdatedAt = DateTime.UtcNow;
        pkg.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<NotificationCreditPackageDto>.Success(new NotificationCreditPackageDto(
            pkg.Id, pkg.Name, pkg.CreditCount, pkg.Price, pkg.Description,
            pkg.IsActive, pkg.IsPublic, pkg.SortOrder)));
    }

    public record GrantCreditsRequest(Guid StoreId, int CreditCount, string? Note);

    [HttpPost("admin/grant-credits")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<NotificationCreditBalanceDto>>> AdminGrantCredits(
        [FromBody] GrantCreditsRequest req, CancellationToken ct)
    {
        if (req.CreditCount <= 0)
            return BadRequest(AppResponse<NotificationCreditBalanceDto>.Fail("Số lượng phải > 0"));

        var (ok, err) = await platformCreditService.TryAllocateToStoreAsync(
            req.StoreId,
            req.CreditCount,
            PosNotificationCreditLedgerSource.AdminGrant,
            null,
            req.Note,
            CurrentUserEmail,
            ct);
        if (!ok)
            return BadRequest(AppResponse<NotificationCreditBalanceDto>.Fail(err ?? "Không cấp được credit"));

        var bal = await creditService.GetBalanceAsync(req.StoreId, ct);
        return Ok(AppResponse<NotificationCreditBalanceDto>.Success(bal));
    }

    public record PlatformTopUpRequest(int CreditCount, decimal CostPerCredit = 200, string? Note = null);

    [HttpGet("admin/platform-credits")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<PlatformCreditBalanceDto>>> AdminPlatformCredits(CancellationToken ct)
    {
        var bal = await platformCreditService.GetBalanceAsync(ct);
        return Ok(AppResponse<PlatformCreditBalanceDto>.Success(bal));
    }

    [HttpPost("admin/platform-credits/top-up")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<PlatformCreditBalanceDto>>> AdminPlatformTopUp(
        [FromBody] PlatformTopUpRequest req, CancellationToken ct)
    {
        if (req.CreditCount <= 0)
            return BadRequest(AppResponse<PlatformCreditBalanceDto>.Fail("Số lượng phải > 0"));
        await platformCreditService.TopUpAsync(
            req.CreditCount, Math.Max(0, req.CostPerCredit), req.Note, CurrentUserEmail, ct);
        var bal = await platformCreditService.GetBalanceAsync(ct);
        return Ok(AppResponse<PlatformCreditBalanceDto>.Success(bal));
    }

    [HttpGet("admin/platform-credit-ledgers")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<List<PlatformCreditLedgerDto>>>> AdminPlatformLedgers(
        [FromQuery] int limit = 50, CancellationToken ct = default)
    {
        var rows = await platformCreditService.ListLedgersAsync(limit, ct);
        return Ok(AppResponse<List<PlatformCreditLedgerDto>>.Success(rows));
    }

    [HttpGet("admin/platform-tingee-settings")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<PlatformTingeeSettingDto>>> AdminGetPlatformTingee(CancellationToken ct)
    {
        var dto = await platformTingeeService.GetSettingsAsync(ct);
        return Ok(AppResponse<PlatformTingeeSettingDto>.Success(dto));
    }

    [HttpPut("admin/platform-tingee-settings")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<PlatformTingeeSettingDto>>> AdminUpsertPlatformTingee(
        [FromBody] PlatformTingeeSettingUpsertRequest req, CancellationToken ct)
    {
        var dto = await platformTingeeService.UpsertSettingsAsync(req, CurrentUserEmail, ct);
        return Ok(AppResponse<PlatformTingeeSettingDto>.Success(dto));
    }

    [HttpGet("admin/credit-purchases-report")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<CreditPurchasesAdminReportDto>>> AdminCreditPurchasesReport(
        [FromQuery] int limit = 50,
        CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 200);

        var baseQ = db.PosNotificationCreditPurchases.AsNoTracking()
            .Where(x => x.Deleted == null);

        var paidQ = baseQ.Where(x => x.Status == PosNotificationCreditPurchaseStatus.Paid);
        var pendingQ = baseQ.Where(x => x.Status == PosNotificationCreditPurchaseStatus.Pending);

        var totalPaidAmount = await paidQ.SumAsync(x => x.AmountPaid, ct);
        var totalPendingAmount = await pendingQ.SumAsync(x => x.AmountPaid, ct);
        var totalCreditsPaid = await paidQ.SumAsync(x => (int?)x.CreditCount, ct) ?? 0;
        var totalCreditsPending = await pendingQ.SumAsync(x => (int?)x.CreditCount, ct) ?? 0;

        var items = await baseQ
            .OrderByDescending(x => x.CreatedAt)
            .Take(limit)
            .Select(x => new NotificationCreditPurchaseAdminDto(
                x.Id,
                x.StoreId,
                x.Store!.Name,
                x.PackageId,
                x.Package != null ? x.Package.Name : "Gói credit",
                x.CreditCount,
                x.AmountPaid,
                x.Status.ToString(),
                x.ExternalPaymentRef,
                x.PaidAt,
                x.Note,
                x.CreatedAt))
            .ToListAsync(ct);

        return Ok(AppResponse<CreditPurchasesAdminReportDto>.Success(
            new CreditPurchasesAdminReportDto(
                totalPaidAmount,
                totalPendingAmount,
                totalCreditsPaid,
                totalCreditsPending,
                items)));
    }

    public record AdminTingeeStoreRequest(Guid StoreId);
    public record AdminTingeeProvisionBody(Guid StoreId, string? Name, string? Phone, string? Email);
    public record AdminTingeeLinkBankBody(
        Guid StoreId,
        string BankBin,
        string AccountNumber,
        string AccountName,
        string? Identity,
        string? Mobile,
        string? AccountType,
        bool IsNotifyAccountNumber = true);
    public record AdminTingeeConfirmVaBody(Guid StoreId, string BankBin, string ConfirmId, string? OtpNumber);
    public record AdminTingeeApplyVaBody(Guid StoreId, string VaAccountNumber);
    public record StoreTingeeLinkBankBody(
        string BankBin,
        string AccountNumber,
        string AccountName,
        string? Identity,
        string? Mobile,
        string? AccountType,
        bool IsNotifyAccountNumber = true);
    public record StoreTingeeConfirmVaBody(string BankBin, string ConfirmId, string? OtpNumber);
    public record StoreTingeeApplyVaBody(string VaAccountNumber);

    [HttpGet("admin/tingee-store")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeStore(
        [FromQuery] Guid storeId, CancellationToken ct)
    {
        if (storeId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.GetStatusAsync(storeId, ct));
    }

    [HttpPost("admin/tingee-provision")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeProvision(
        [FromBody] AdminTingeeProvisionBody req, CancellationToken ct)
    {
        if (req.StoreId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.ProvisionAsync(
            req.StoreId, new TingeeProvisionRequest(req.Name, req.Phone, req.Email), CurrentUserEmail, ct));
    }

    [HttpPost("admin/tingee-link-bank")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeLinkBank(
        [FromBody] AdminTingeeLinkBankBody req, CancellationToken ct)
    {
        if (req.StoreId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.LinkBankAsync(
            req.StoreId,
            new TingeeLinkBankRequest(
                req.BankBin, req.AccountNumber, req.AccountName, req.Identity, req.Mobile,
                req.AccountType ?? "personal-account", req.IsNotifyAccountNumber),
            CurrentUserEmail, ct));
    }

    [HttpPost("admin/tingee-confirm-va")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeConfirmVa(
        [FromBody] AdminTingeeConfirmVaBody req, CancellationToken ct)
    {
        if (req.StoreId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.ConfirmVaAsync(
            req.StoreId, new TingeeConfirmVaRequest(req.BankBin, req.ConfirmId, req.OtpNumber),
            CurrentUserEmail, ct));
    }

    [HttpPost("admin/tingee-bank-link-session")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeBankLinkSession(
        [FromBody] AdminTingeeStoreRequest req, CancellationToken ct)
    {
        if (req.StoreId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.CreateBankLinkSessionAsync(req.StoreId, ct));
    }

    [HttpPost("admin/tingee-apply-va")]
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> AdminTingeeApplyVa(
        [FromBody] AdminTingeeApplyVaBody req, CancellationToken ct)
    {
        if (req.StoreId == Guid.Empty)
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.ApplyVaAsync(
            req.StoreId, req.VaAccountNumber, CurrentUserEmail, ct));
    }

    [HttpGet("tingee/status")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> StoreTingeeStatus(CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.GetStatusAsync(storeId, ct));
    }

    [HttpPost("tingee/link-bank")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> StoreTingeeLinkBank(
        [FromBody] StoreTingeeLinkBankBody req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.LinkBankAsync(
            storeId,
            new TingeeLinkBankRequest(
                req.BankBin, req.AccountNumber, req.AccountName, req.Identity, req.Mobile,
                req.AccountType ?? "personal-account", req.IsNotifyAccountNumber),
            CurrentUserEmail, ct));
    }

    [HttpPost("tingee/confirm-va")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> StoreTingeeConfirmVa(
        [FromBody] StoreTingeeConfirmVaBody req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.ConfirmVaAsync(
            storeId, new TingeeConfirmVaRequest(req.BankBin, req.ConfirmId, req.OtpNumber),
            CurrentUserEmail, ct));
    }

    [HttpPost("tingee/bank-link-session")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> StoreTingeeBankLinkSession(
        CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.CreateBankLinkSessionAsync(storeId, ct));
    }

    [HttpPost("tingee/apply-va")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> StoreTingeeApplyVa(
        [FromBody] StoreTingeeApplyVaBody req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail("Thiếu cửa hàng"));
        return await TryTingee(() => tingeeProvision.ApplyVaAsync(
            storeId, req.VaAccountNumber, CurrentUserEmail, ct));
    }

    async Task<ActionResult<AppResponse<TingeeStoreProvisionDto>>> TryTingee(
        Func<Task<TingeeStoreProvisionDto>> run)
    {
        try
        {
            var dto = await run();
            return Ok(AppResponse<TingeeStoreProvisionDto>.Success(dto));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<TingeeStoreProvisionDto>.Fail(ex.Message));
        }
    }
}
