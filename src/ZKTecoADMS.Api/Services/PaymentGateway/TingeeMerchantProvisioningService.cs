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
    List<TingeeVaAccountDto> Accounts);

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
}

public sealed class TingeeMerchantProvisioningService(
    ZKTecoDbContext db,
    ITingeeOpenApiClient tingee) : ITingeeMerchantProvisioningService
{
    const string WebhookUrl = "https://sboxhrm.com/api/webhooks/payment/tingee";
    const string RedirectUrl = "https://sboxhrm.com";

    public async Task<TingeeStoreProvisionDto> GetStatusAsync(Guid storeId, CancellationToken ct = default)
    {
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
        var va = ReadString(result.Data, "vaAccountNumber") ?? ReadString(result.Data, "accountNumber");
        if (!string.IsNullOrWhiteSpace(va))
            row.TingeeVaAccountNumber = va.Trim();
        else if (string.IsNullOrWhiteSpace(row.TingeeVaAccountNumber))
            row.TingeeVaAccountNumber = accountNumber;

        var returnedShop = ReadString(result.Data, "shopId");
        if (!string.IsNullOrWhiteSpace(returnedShop) && string.IsNullOrWhiteSpace(row.TingeeShopId))
            row.TingeeShopId = returnedShop.Trim();

        row.TingeeEnabled = true;
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = actor;
        await db.SaveChangesAsync(ct);

        var accounts = await TryListVaAsync(row, ct);
        var msg = !string.IsNullOrWhiteSpace(confirmId)
            ? "Tingee yêu cầu OTP — nhập mã rồi bấm Xác nhận VA."
            : !string.IsNullOrWhiteSpace(authorizeLink)
                ? "Mở link ngân hàng để hoàn tất liên kết."
                : "Đã gửi yêu cầu gắn STK.";
        return Map(row, accounts, msg, confirmId, authorizeLink);
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

        var accounts = await TryListVaAsync(row, ct);
        if (string.IsNullOrWhiteSpace(row.TingeeVaAccountNumber) && accounts.Count > 0)
        {
            row.TingeeVaAccountNumber = FirstNonEmpty(
                accounts[0].VaAccountNumber, accounts[0].AccountNumber);
            await db.SaveChangesAsync(ct);
        }

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
        var accounts = await TryListVaAsync(row, ct);
        return Map(row, accounts, "Đã lưu số VA vào cửa hàng.");
    }

    public async Task<List<TingeeVaAccountDto>> ListVaAccountsAsync(Guid storeId, CancellationToken ct = default)
    {
        var row = await GetSettingsAsync(storeId, ct);
        return await TryListVaAsync(row, ct);
    }

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
        string? bankLinkUrl = null) => new(
        row?.TingeeMerchantId,
        row?.TingeeShopId,
        row?.TingeeVaAccountNumber,
        row?.TingeeEnabled == true,
        confirmId,
        authorizeLink,
        bankLinkUrl,
        message,
        accounts);

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
