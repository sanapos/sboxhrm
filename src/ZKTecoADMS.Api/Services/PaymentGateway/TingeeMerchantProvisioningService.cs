using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public sealed record TingeeProvisionRequest(string? Name, string? Phone, string? Email);

public sealed record TingeeLinkBankRequest(
    string BankBin,
    string AccountNumber,
    string AccountName,
    string? Identity,
    string? Mobile,
    string AccountType = "personal-account",
    bool IsNotifyAccountNumber = true);

public sealed record TingeeConfirmVaRequest(string BankBin, string ConfirmId, string? OtpNumber);

public sealed record TingeeSupportedBankDto(
    string Bin,
    string Code,
    string Name,
    string ShortName,
    string? LogoUrl);

public sealed record TingeeVaAccountDto(
    string? BankBin,
    string? AccountName,
    string? AccountNumber,
    string? VaAccountNumber,
    string? Status,
    string? ShopId,
    string? AccountType);

public sealed record TingeeStoreProvisionDto(
    string? TingeeMerchantId,
    string? TingeeShopId,
    string? TingeeVaAccountNumber,
    bool TingeeEnabled,
    string? ConfirmId,
    string? AuthorizeLink,
    string? BankLinkUrl,
    string? Message,
    List<TingeeVaAccountDto> Accounts,
    string? DeepLink = null);

public interface ITingeeMerchantProvisioningService
{
    Task<TingeeStoreProvisionDto> GetStatusAsync(Guid storeId, CancellationToken ct = default);
    Task<TingeeStoreProvisionDto> ProvisionAsync(
        Guid storeId, TingeeProvisionRequest req, string? actor, CancellationToken ct = default);
    Task<TingeeStoreProvisionDto> LinkBankAsync(
        Guid storeId, TingeeLinkBankRequest req, string? actor, CancellationToken ct = default);
    Task<TingeeStoreProvisionDto> ConfirmVaAsync(
        Guid storeId, TingeeConfirmVaRequest req, string? actor, CancellationToken ct = default);
    Task<TingeeStoreProvisionDto> CreateBankLinkSessionAsync(
        Guid storeId, CancellationToken ct = default);
    Task<List<TingeeVaAccountDto>> ListVaAccountsAsync(Guid storeId, CancellationToken ct = default);
    Task<TingeeStoreProvisionDto> ApplyVaAsync(
        Guid storeId, string vaAccountNumber, string? actor, CancellationToken ct = default);
    Task<List<TingeeSupportedBankDto>> ListSupportedBanksAsync(CancellationToken ct = default);
    /// QR + webhook Tingee theo VA (TGE…) khi khác STK settlement.
    Task SyncVaQrDestinationAsync(Guid storeId, CancellationToken ct = default);
}

public sealed class TingeeMerchantProvisioningService(
    ZKTecoDbContext db,
    ITingeeOpenApiClient tingee) : ITingeeMerchantProvisioningService
{
    const string WebhookUrl = "https://sboxhrm.com/api/webhooks/payment/tingee";
    const string RedirectUrl = "https://sboxhrm.com";

    public async Task<TingeeStoreProvisionDto> GetStatusAsync(Guid storeId, CancellationToken ct = default)
    {
        await SyncVaQrDestinationAsync(storeId, ct);
        var row = await GetSettingsAsync(storeId, ct);
        var accounts = await TryListVaAsync(row, ct);
        return Map(row, accounts, message: null);
    }

    public async Task<TingeeStoreProvisionDto> ProvisionAsync(
        Guid storeId, TingeeProvisionRequest req, string? actor, CancellationToken ct = default)
    {
        var store = await db.Stores.AsNoTracking().FirstOrDefaultAsync(x => x.Id == storeId, ct)
            ?? throw new InvalidOperationException("Không tìm thấy cửa hàng");

        var row = await GetOrCreateSettingsAsync(storeId, actor, ct);
        var name = FirstNonEmpty(req.Name, store.Name, store.Code) ?? "SBOX store";
        var phone = NormalizePhone(FirstNonEmpty(req.Phone, store.Phone));
        if (phone.Length < 9)
            throw new InvalidOperationException("Cần số điện thoại cửa hàng để tạo merchant Tingee.");
        var email = FirstNonEmpty(req.Email, $"{store.Code}@sboxhrm.com") ?? "store@sboxhrm.com";
        var code = (store.Code ?? "").Trim();
        if (code.Length == 0) code = storeId.ToString("N")[..8];

        long merchantId;
        if (TryParseId(row.TingeeMerchantId, out merchantId))
        {
            // already provisioned — still ensure shop
        }
        else
        {
            merchantId = await CreateOrFindMerchantAsync(name, phone, email, code, ct);
            row.TingeeMerchantId = merchantId.ToString();
        }

        long shopId;
        if (TryParseId(row.TingeeShopId, out shopId))
        {
            await UpsertShopAsync(merchantId, shopId, name, store.Address, ct);
        }
        else
        {
            shopId = await UpsertShopAsync(merchantId, null, name, store.Address, ct);
            row.TingeeShopId = shopId.ToString();
        }

        row.TingeeEnabled = true;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);

        var accounts = await TryListVaAsync(row, ct);
        return Map(row, accounts, "Đã tạo merchant + shop Tingee cho cửa hàng.");
    }

    public async Task<TingeeStoreProvisionDto> LinkBankAsync(
        Guid storeId, TingeeLinkBankRequest req, string? actor, CancellationToken ct = default)
    {
        var row = await RequireProvisionedAsync(storeId, ct);
        if (!TryParseId(row.TingeeMerchantId, out var merchantId))
            throw new InvalidOperationException("Cửa hàng chưa có Merchant ID Tingee.");

        var bankBin = (req.BankBin ?? "").Trim();
        var accountNumber = (req.AccountNumber ?? "").Trim();
        var accountName = (req.AccountName ?? "").Trim();
        if (bankBin.Length == 0 || accountNumber.Length == 0 || accountName.Length == 0)
            throw new InvalidOperationException("Cần BIN ngân hàng, số tài khoản và tên chủ TK.");

        var body = new JsonObject
        {
            ["merchantId"] = merchantId,
            ["accountType"] = string.IsNullOrWhiteSpace(req.AccountType) ? "personal-account" : req.AccountType.Trim(),
            ["bankBin"] = bankBin,
            ["bankName"] = BankNameForBin(bankBin) ?? bankBin,
            ["accountNumber"] = accountNumber,
            ["accountName"] = accountName,
            ["isNotifyAccountNumber"] = req.IsNotifyAccountNumber,
            ["webhookUrl"] = WebhookUrl,
            ["redirectUrl"] = RedirectUrl,
            ["appType"] = "baas",
        };
        if (TryParseId(row.TingeeShopId, out var shopId))
            body["shopId"] = shopId;
        if (!string.IsNullOrWhiteSpace(req.Identity))
            body["identity"] = req.Identity.Trim();
        if (!string.IsNullOrWhiteSpace(req.Mobile))
            body["mobile"] = NormalizePhone(req.Mobile);

        var result = await tingee.PostAsync(body, "create-va", ct);
        if (result.Code != "00")
            throw new InvalidOperationException(TingeeError(result));

        var confirmId = ReadString(result.Data, "confirmId");
        var authorizeLink = ReadString(result.Data, "authorizeLink");
        var deepLink = ReadString(result.Data, "deepLink");
        // Một số ngân hàng (VCB) chỉ trả deepLink -> map vào authorizeLink field để UI cũ vẫn mở được.
        if (string.IsNullOrWhiteSpace(authorizeLink) && !string.IsNullOrWhiteSpace(deepLink))
            authorizeLink = deepLink;
        // QR + webhook theo VA Tingee (TGE…) nếu create-va trả về; không thì STK.
        var returnedVa = ReadString(result.Data, "vaAccountNumber");
        row.TingeeVaAccountNumber = FirstNonEmpty(returnedVa, accountNumber);

        var returnedShop = ReadString(result.Data, "shopId");
        if (!string.IsNullOrWhiteSpace(returnedShop) && string.IsNullOrWhiteSpace(row.TingeeShopId))
            row.TingeeShopId = returnedShop.Trim();

        row.TingeeEnabled = true;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        await EnsureStoreBankAccountAsync(storeId, bankBin, accountNumber, accountName, actor, ct, setAsReceive: true);
        if (!string.IsNullOrWhiteSpace(returnedVa) &&
            !string.Equals(returnedVa.Trim(), accountNumber, StringComparison.OrdinalIgnoreCase))
        {
            await EnsureStoreBankAccountAsync(
                storeId, bankBin, returnedVa.Trim(), accountName, actor, ct, setAsReceive: false);
        }
        await SyncVaQrDestinationAsync(storeId, ct);

        var accounts = await TryListVaAsync(row, ct);
        var msg = !string.IsNullOrWhiteSpace(confirmId)
            ? "Tingee yêu cầu OTP — nhập mã rồi bấm Xác nhận VA."
            : !string.IsNullOrWhiteSpace(deepLink)
                ? "Mở app ngân hàng để duyệt liên kết (deep link hết hạn sau ~5 phút)."
                : !string.IsNullOrWhiteSpace(authorizeLink)
                    ? "Mở link ngân hàng để hoàn tất liên kết."
                    : "Đã gửi yêu cầu gắn STK.";
        return Map(row, accounts, msg, confirmId, authorizeLink, deepLink: deepLink);
    }

    public async Task<TingeeStoreProvisionDto> ConfirmVaAsync(
        Guid storeId, TingeeConfirmVaRequest req, string? actor, CancellationToken ct = default)
    {
        var row = await RequireProvisionedAsync(storeId, ct);
        if (!TryParseId(row.TingeeMerchantId, out var merchantId))
            throw new InvalidOperationException("Cửa hàng chưa có Merchant ID Tingee.");

        var body = new JsonObject
        {
            ["merchantId"] = merchantId,
            ["bankBin"] = (req.BankBin ?? "").Trim(),
            ["confirmId"] = (req.ConfirmId ?? "").Trim(),
        };
        if (!string.IsNullOrWhiteSpace(req.OtpNumber))
            body["otpNumber"] = req.OtpNumber.Trim();

        var result = await tingee.PostAsync(body, "confirm-va", ct);
        if (result.Code != "00")
            throw new InvalidOperationException(TingeeError(result));

        var va = ReadString(result.Data, "vaAccountNumber")
            ?? ReadString(result.Data, "accountNumber");
        if (!string.IsNullOrWhiteSpace(va))
            row.TingeeVaAccountNumber = va.Trim();
        row.TingeeEnabled = true;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        await SyncVaQrDestinationAsync(storeId, ct);

        var accounts = await TryListVaAsync(row, ct);
        return Map(row, accounts, "Đã xác nhận liên kết tài khoản.");
    }

    public async Task<TingeeStoreProvisionDto> CreateBankLinkSessionAsync(
        Guid storeId, CancellationToken ct = default)
    {
        var row = await RequireProvisionedAsync(storeId, ct);
        if (!TryParseId(row.TingeeMerchantId, out var merchantId))
            throw new InvalidOperationException("Cửa hàng chưa có Merchant ID Tingee.");

        var body = new JsonObject
        {
            ["merchantId"] = merchantId,
            ["type"] = "bank-link",
            ["redirectUrl"] = RedirectUrl,
        };
        if (TryParseId(row.TingeeShopId, out var shopId))
            body["shopId"] = shopId;

        var result = await tingee.PostAsync(body, "create-bank-link-session", ct);
        if (result.Code != "00")
            throw new InvalidOperationException(TingeeError(result));

        var url = result.Data.ValueKind == JsonValueKind.String
            ? result.Data.GetString()
            : ReadString(result.Data, "url") ?? ReadString(result.Data, "data");
        if (string.IsNullOrWhiteSpace(url))
            throw new InvalidOperationException("Tingee không trả URL liên kết ngân hàng.");

        var accounts = await TryListVaAsync(row, ct);
        return Map(row, accounts, "Mở URL để khách chọn ngân hàng và nhập STK.", bankLinkUrl: url);
    }

    public async Task<TingeeStoreProvisionDto> ApplyVaAsync(
        Guid storeId, string vaAccountNumber, string? actor, CancellationToken ct = default)
    {
        var row = await RequireProvisionedAsync(storeId, ct);
        var va = (vaAccountNumber ?? "").Trim();
        if (va.Length == 0)
            throw new InvalidOperationException("Thiếu số VA / STK.");
        row.TingeeVaAccountNumber = va;
        row.TingeeEnabled = true;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);
        await SyncVaQrDestinationAsync(storeId, ct);
        var accounts = await TryListVaAsync(row, ct);
        var bin = accounts.FirstOrDefault(a => !string.IsNullOrWhiteSpace(a.BankBin))?.BankBin
            ?? "970418";
        var name = accounts.FirstOrDefault()?.AccountName ?? "Tingee";
        await EnsureStoreBankAccountAsync(storeId, bin, va, name, actor, ct, setAsReceive: false);
        return Map(row, accounts, "Đã lưu số VA vào cửa hàng.");
    }

    static readonly List<TingeeSupportedBankDto> FallbackBanks =
    [
        new("970418", "BIDV", "Ngân hàng TMCP Đầu tư và Phát triển Việt Nam", "BIDV", null),
        new("970436", "VCB", "Ngân hàng TMCP Ngoại thương Việt Nam", "Vietcombank", null),
        new("970415", "CTG", "Ngân hàng TMCP Công Thương Việt Nam", "VietinBank", null),
        new("970422", "MBB", "Ngân hàng TMCP Quân đội", "MB Bank", null),
        new("970416", "ACB", "Ngân hàng TMCP Á Châu", "ACB", null),
        new("970432", "VPB", "Ngân hàng TMCP Việt Nam Thịnh Vượng", "VPBank", null),
        new("970403", "STB", "Ngân hàng TMCP Sài Gòn Thương Tín", "Sacombank", null),
        new("970448", "OCB", "Ngân hàng TMCP Phương Đông", "OCB", null),
        new("970430", "PGB", "Ngân hàng TMCP Xăng dầu Petrolimex", "PGBank", null),
        new("970441", "VIB", "Ngân hàng TMCP Quốc tế Việt Nam", "VIB", null),
        new("970423", "TPB", "Ngân hàng TMCP Tiên Phong", "TPBank", null),
        new("970426", "MSB", "Ngân hàng TMCP Hàng Hải Việt Nam", "MSB", null),
        new("970407", "TCB", "Ngân hàng TMCP Kỹ Thương Việt Nam", "Techcombank", null),
        new("970437", "HDB", "Ngân hàng TMCP Phát triển TP.HCM", "HDBank", null),
    ];

    static List<TingeeSupportedBankDto>? _banksCache;
    static DateTime _banksCacheAt;

    public async Task<List<TingeeSupportedBankDto>> ListSupportedBanksAsync(CancellationToken ct = default)
    {
        if (_banksCache is { Count: > 0 } && DateTime.UtcNow - _banksCacheAt < TimeSpan.FromHours(6))
            return _banksCache;

        try
        {
            var result = await tingee.GetAsync("get-banks", ct);
            if (result.Code == "00" && result.Data.ValueKind == JsonValueKind.Array)
            {
                var list = new List<TingeeSupportedBankDto>();
                foreach (var item in result.Data.EnumerateArray())
                {
                    var bin = ReadString(item, "bin", "bankBin") ?? "";
                    if (bin.Length == 0) continue;
                    var code = ReadString(item, "code", "shortName") ?? BankNameForBin(bin) ?? bin;
                    var name = ReadString(item, "name") ?? code;
                    var shortName = ReadString(item, "shortName") ?? code;
                    var logo = ReadString(item, "urlLogo", "logoUrl");
                    list.Add(new TingeeSupportedBankDto(bin, code, name, shortName, logo));
                }
                if (list.Count > 0)
                {
                    _banksCache = list;
                    _banksCacheAt = DateTime.UtcNow;
                    return list;
                }
            }
        }
        catch
        {
            // fallback
        }

        _banksCache = FallbackBanks;
        _banksCacheAt = DateTime.UtcNow;
        return FallbackBanks;
    }

    public async Task<List<TingeeVaAccountDto>> ListVaAccountsAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await GetSettingsAsync(storeId, ct);
        return await TryListVaAsync(row, ct);
    }

    public async Task SyncVaQrDestinationAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await GetSettingsAsync(storeId, ct);
        if (row == null || string.IsNullOrWhiteSpace(row.TingeeMerchantId))
            return;

        var accounts = await TryListVaAsync(row, ct);
        var active = accounts.FirstOrDefault(a =>
            string.Equals(a.Status, "active", StringComparison.OrdinalIgnoreCase));
        active ??= accounts.FirstOrDefault();
        if (active == null) return;

        var qrNumber = FirstNonEmpty(active.VaAccountNumber, active.AccountNumber);
        if (string.IsNullOrWhiteSpace(qrNumber)) return;

        var bin = (active.BankBin ?? "").Trim();
        var name = FirstNonEmpty(active.AccountName, "Tingee");
        if (!string.Equals(row.TingeeVaAccountNumber?.Trim(), qrNumber, StringComparison.OrdinalIgnoreCase))
        {
            row.TingeeVaAccountNumber = qrNumber;
            row.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        await EnsureStoreBankAccountAsync(storeId, bin, qrNumber, name, "tingee-sync", ct, setAsReceive: false);
        var settlement = (active.AccountNumber ?? "").Trim();
        if (settlement.Length > 0 &&
            !string.Equals(settlement, qrNumber, StringComparison.OrdinalIgnoreCase))
        {
            await EnsureStoreBankAccountAsync(storeId, bin, settlement, name, "tingee-sync", ct, setAsReceive: false);
        }
    }

    async Task EnsureStoreBankAccountAsync(
        Guid storeId, string? bankBin, string accountNumber, string? accountName, string? actor,
        CancellationToken ct, bool setAsReceive = false)
    {
        var number = (accountNumber ?? "").Trim();
        var bin = (bankBin ?? "").Trim();
        if (number.Length < 6 || bin.Length == 0)
            return;

        var existing = await db.BankAccounts.FirstOrDefaultAsync(
            x => x.StoreId == storeId && x.AccountNumber == number && x.Deleted == null, ct);
        var meta = VietQRBanks.FindByBin(bin);
        var name = FirstNonEmpty(accountName, meta?.Name, "Tingee")!;
        if (existing == null)
        {
            var hasDefault = await db.BankAccounts.AnyAsync(
                x => x.StoreId == storeId && x.IsDefault && x.Deleted == null, ct);
            db.BankAccounts.Add(new BankAccount
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                AccountNumber = number,
                AccountName = name,
                BankCode = bin,
                BankName = meta?.Name ?? name,
                BankShortName = meta?.ShortName ?? BankNameForBin(bin),
                BankLogoUrl = meta?.Logo,
                IsDefault = !hasDefault,
                IsActive = true,
                Note = number.Any(char.IsLetter) ? "Tingee VA" : "Tingee",
                CreatedBy = actor,
            });
        }
        else
        {
            existing.BankCode = bin;
            if (!string.IsNullOrWhiteSpace(accountName))
                existing.AccountName = accountName.Trim();
            if (meta != null)
            {
                existing.BankName = meta.Value.Name;
                existing.BankShortName = meta.Value.ShortName;
                existing.BankLogoUrl = meta.Value.Logo;
            }
            existing.IsActive = true;
            existing.UpdatedAt = DateTime.UtcNow;
            existing.UpdatedBy = actor;
        }
        if (setAsReceive)
        {
            var others = await db.BankAccounts.AsTracking()
                .Where(x => x.StoreId == storeId && x.Deleted == null && x.AccountNumber != number)
                .ToListAsync(ct);
            foreach (var other in others)
                other.IsDefault = false;
            var receive = await db.BankAccounts.AsTracking()
                .FirstOrDefaultAsync(x => x.StoreId == storeId && x.AccountNumber == number && x.Deleted == null, ct);
            if (receive != null)
                receive.IsDefault = true;
        }
        await db.SaveChangesAsync(ct);
    }

    static string? BankNameForBin(string? bin) => (bin ?? "").Trim() switch
    {
        "970418" => "BIDV",
        "970436" => "VCB",
        "970415" => "CTG",
        "970422" => "MBB",
        "970416" => "ACB",
        "970432" => "VPB",
        "970403" => "STB",
        "970448" => "OCB",
        "970430" => "PGB",
        "970441" => "VIB",
        "970423" => "TPB",
        "970426" => "MSB",
        "970407" => "TCB",
        "970437" => "HDB",
        _ => null,
    };

    async Task<long> CreateOrFindMerchantAsync(
        string name, string phone, string email, string code, CancellationToken ct)
    {
        var body = new JsonObject
        {
            ["name"] = name,
            ["phoneNumber"] = phone,
            ["email"] = email,
            ["code"] = code,
            ["website"] = RedirectUrl,
        };
        var created = await tingee.PostAsync(body, "merchant/create", ct);
        if (created.Code == "00")
        {
            var id = ReadString(created.Data, "merchantId");
            if (TryParseId(id, out var merchantId)) return merchantId;
        }

        var found = await FindMerchantIdByPhoneAsync(phone, ct);
        if (found.HasValue) return found.Value;

        throw new InvalidOperationException(TingeeError(created));
    }

    async Task<long?> FindMerchantIdByPhoneAsync(string phone, CancellationToken ct)
    {
        var body = new JsonObject
        {
            ["skipCount"] = 0,
            ["maxResultCount"] = 50,
            ["filter"] = phone,
        };
        var result = await tingee.PostAsync(body, "merchant/get-paging", ct);
        if (result.Code != "00" || result.Data.ValueKind != JsonValueKind.Object)
            return null;
        if (!result.Data.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var item in items.EnumerateArray())
        {
            var p = ReadString(item, "phoneNumber") ?? ReadString(item, "phone");
            if (!string.Equals(NormalizePhone(p), phone, StringComparison.Ordinal))
                continue;
            if (TryParseId(ReadString(item, "id") ?? ReadString(item, "merchantId"), out var id))
                return id;
        }
        return null;
    }

    async Task<long> UpsertShopAsync(
        long merchantId, long? shopId, string name, string? address, CancellationToken ct)
    {
        var body = new JsonObject
        {
            ["merchantId"] = merchantId,
            ["name"] = name,
            ["isActive"] = true,
        };
        if (shopId.HasValue) body["id"] = shopId.Value;
        if (!string.IsNullOrWhiteSpace(address)) body["address"] = address.Trim();

        var result = await tingee.PostAsync(body, "shop/create-or-update", ct);
        if (result.Code != "00")
            throw new InvalidOperationException(TingeeError(result));
        var id = ReadString(result.Data, "shopId") ?? ReadString(result.Data, "id");
        if (!TryParseId(id, out var parsed))
            throw new InvalidOperationException("Tingee không trả shopId.");
        return parsed;
    }

    async Task<List<TingeeVaAccountDto>> TryListVaAsync(PosPaymentGatewaySetting? row, CancellationToken ct)
    {
        if (row == null || !TryParseId(row.TingeeMerchantId, out var merchantId))
            return [];
        try
        {
            var body = new JsonObject
            {
                ["filter"] = "",
                ["skipCount"] = 0,
                ["maxResultCount"] = 20,
                ["merchantId"] = merchantId,
            };
            var result = await tingee.PostAsync(body, "get-va-paging", ct);
            if (result.Code != "00" || result.Data.ValueKind != JsonValueKind.Object)
                return [];
            if (!result.Data.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
                return [];
            var list = new List<TingeeVaAccountDto>();
            foreach (var item in items.EnumerateArray())
            {
                list.Add(new TingeeVaAccountDto(
                    ReadString(item, "bankBin"),
                    ReadString(item, "accountName"),
                    ReadString(item, "accountNumber"),
                    ReadString(item, "vaAccountNumber"),
                    ReadString(item, "status"),
                    ReadString(item, "shopId"),
                    ReadString(item, "accountType")));
            }
            return list;
        }
        catch
        {
            return [];
        }
    }

    async Task<PosPaymentGatewaySetting> RequireProvisionedAsync(Guid storeId, CancellationToken ct)
    {
        var row = await db.PosPaymentGatewaySettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);
        if (row == null || string.IsNullOrWhiteSpace(row.TingeeMerchantId))
            throw new InvalidOperationException("Chưa tạo merchant Tingee cho cửa hàng. SuperAdmin hãy bấm Tạo cửa hàng Tingee trước.");
        return row;
    }

    async Task<PosPaymentGatewaySetting?> GetSettingsAsync(Guid storeId, CancellationToken ct) =>
        await db.PosPaymentGatewaySettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null, ct);

    async Task<PosPaymentGatewaySetting> GetOrCreateSettingsAsync(Guid storeId, string? actor, CancellationToken ct)
    {
        var row = await GetSettingsAsync(storeId, ct);
        if (row != null) return row;
        row = new PosPaymentGatewaySetting
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            IsActive = true,
            CreatedBy = actor,
        };
        db.PosPaymentGatewaySettings.Add(row);
        return row;
    }

    static TingeeStoreProvisionDto Map(
        PosPaymentGatewaySetting? row,
        List<TingeeVaAccountDto> accounts,
        string? message,
        string? confirmId = null,
        string? authorizeLink = null,
        string? bankLinkUrl = null,
        string? deepLink = null) => new(
        row?.TingeeMerchantId,
        row?.TingeeShopId,
        row?.TingeeVaAccountNumber,
        row?.TingeeEnabled == true,
        confirmId,
        authorizeLink,
        bankLinkUrl,
        message,
        accounts,
        deepLink);

    static string TingeeError(TingeeOpenApiResult r)
    {
        var msg = (r.Message ?? "").Trim();
        if (msg.Contains("<html", StringComparison.OrdinalIgnoreCase))
            return $"Tingee [{r.Code}] cổng ngân hàng UAT/prod lỗi (404). Thử ngân hàng khác hoặc liên hệ Tingee.";
        return string.IsNullOrEmpty(msg) ? $"Tingee lỗi [{r.Code}]" : $"Tingee [{r.Code}]: {msg}";
    }

    static string? ReadString(JsonElement el, params string[] names)
    {
        if (el.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)
            return null;
        if (el.ValueKind == JsonValueKind.String && names.Length == 0)
            return el.GetString();
        foreach (var name in names)
        {
            if (el.ValueKind != JsonValueKind.Object || !el.TryGetProperty(name, out var p))
                continue;
            if (p.ValueKind == JsonValueKind.String) return p.GetString();
            if (p.ValueKind == JsonValueKind.Number) return p.GetRawText();
            if (p.ValueKind == JsonValueKind.True || p.ValueKind == JsonValueKind.False)
                return p.GetRawText();
        }
        return null;
    }

    static bool TryParseId(string? raw, out long id)
    {
        id = 0;
        var s = (raw ?? "").Trim();
        return s.Length > 0 && long.TryParse(s, out id) && id > 0;
    }

    static string NormalizePhone(string? raw)
    {
        var s = (raw ?? "").Trim();
        if (s.StartsWith("+84", StringComparison.Ordinal)) s = "0" + s[3..];
        var digits = new string(s.Where(char.IsDigit).ToArray());
        return digits;
    }

    static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var v in values)
        {
            if (!string.IsNullOrWhiteSpace(v)) return v.Trim();
        }
        return null;
    }
}
