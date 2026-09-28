using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.EInvoice;

/// <summary>
/// Xuất HĐĐT nền cho đơn hoàn tất KHÔNG qua quầy (đơn online COD, Tingee webhook tự hoàn tất):
/// không có thu ngân bấm chip → theo «Mặc định xuất hóa đơn» trong cấu hình.
/// Chạy nền để webhook / API trả về ngay (gọi hãng có thể mất 30–90 giây).
/// </summary>
public sealed class PosEInvoiceAutoIssuer(IServiceScopeFactory scopes, ILogger<PosEInvoiceAutoIssuer> logger)
{
    public void Enqueue(Guid storeId, Guid orderId)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                // Chờ request gốc commit xong (paid amount / phương thức TT cập nhật sau hoàn tất).
                await Task.Delay(TimeSpan.FromSeconds(3));
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                var svc = scope.ServiceProvider.GetRequiredService<PosEInvoiceService>();
                var order = await db.PosSaleOrders
                    .Include(o => o.Lines)
                    .FirstOrDefaultAsync(o => o.Id == orderId && o.StoreId == storeId && o.Deleted == null);
                if (order == null || order.Status != PosSaleOrderStatus.Completed)
                    return;
                if (!string.IsNullOrWhiteSpace(order.EInvoiceStatus) &&
                    !string.Equals(order.EInvoiceStatus, "None", StringComparison.OrdinalIgnoreCase))
                    return;
                await svc.HandleAfterCompleteAsync(order, issueFlag: null, buyer: null);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Auto e-invoice failed for order {OrderId}", orderId);
            }
        });
    }
}
