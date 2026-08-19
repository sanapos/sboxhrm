using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

/// <summary>Provider webhook — mỗi cổng (Tingee, Momo, VNPay…) implement 1 class.</summary>
public interface IPaymentWebhookProvider
{
    PosPaymentNotifyProvider Provider { get; }

    bool VerifySignature(
        string? signature,
        string? timestamp,
        string rawBody,
        string secretKey);

    PaymentWebhookPayload Parse(string rawBody);
}

public interface IPaymentWebhookProviderRegistry
{
    IPaymentWebhookProvider Get(PosPaymentNotifyProvider provider);
}

public sealed class PaymentWebhookProviderRegistry : IPaymentWebhookProviderRegistry
{
    private readonly IReadOnlyDictionary<PosPaymentNotifyProvider, IPaymentWebhookProvider> _map;

    public PaymentWebhookProviderRegistry(IEnumerable<IPaymentWebhookProvider> providers)
    {
        _map = providers.ToDictionary(p => p.Provider);
    }

    public IPaymentWebhookProvider Get(PosPaymentNotifyProvider provider)
    {
        if (!_map.TryGetValue(provider, out var p))
            throw new InvalidOperationException($"Payment webhook provider not registered: {provider}");
        return p;
    }
}
