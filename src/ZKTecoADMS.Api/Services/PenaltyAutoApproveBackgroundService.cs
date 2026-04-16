using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Background service tự động duyệt phiếu phạt (PaymentTransaction Type=Penalty, Status=Pending) sau 24h nếu chưa hủy.
/// Chạy mỗi 30 phút. Khi duyệt tự động → tạo phiếu thu (CashTransaction).
/// </summary>
public class PenaltyAutoApproveBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<PenaltyAutoApproveBackgroundService> _logger;
    private readonly TimeSpan _checkInterval = TimeSpan.FromMinutes(30);

    public PenaltyAutoApproveBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<PenaltyAutoApproveBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🔔 Penalty Auto-Approve Background Service started");

        // Chờ app khởi động xong
        await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await AutoApprovePendingPenaltiesAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in penalty auto-approve service");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }

        _logger.LogInformation("🔔 Penalty Auto-Approve Background Service stopped");
    }

    private async Task AutoApprovePendingPenaltiesAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        // Lấy PaymentTransaction Type=Penalty, Status=Pending mà TransactionDate < hôm nay (qua ngày hôm sau)
        // Chỉ lấy phiếu tự động tạo từ chấm công (Note chứa "Tự động tạo từ chấm công")
        var cutoffDate = DateTime.Now.Date;
        var pendingPenalties = await dbContext.PaymentTransactions
            .Include(pt => pt.Employee)
            .Where(pt => pt.Type == "Penalty"
                && pt.Status == "Pending"
                && pt.TransactionDate.Date < cutoffDate
                && pt.Note != null && pt.Note.Contains("Tự động tạo từ chấm công"))
            .ToListAsync(stoppingToken);

        if (pendingPenalties.Count == 0) return;

        _logger.LogInformation("🔔 Found {Count} pending penalty transactions to auto-approve", pendingPenalties.Count);

        foreach (var penalty in pendingPenalties)
        {
            try
            {
                // Tự động duyệt
                penalty.Status = "Completed";

                // Tạo phiếu thu (CashTransaction)
                await CreateCashTransactionForPenaltyAsync(dbContext, penalty, stoppingToken);

                _logger.LogInformation("🔔 Auto-approved penalty transaction {Id} - Amount: {Amount}",
                    penalty.Id, Math.Abs(penalty.Amount));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error auto-approving penalty {Id}", penalty.Id);
            }
        }

        await dbContext.SaveChangesAsync(stoppingToken);
        _logger.LogInformation("🔔 Auto-approved {Count} penalty transactions", pendingPenalties.Count);
    }

    private async Task CreateCashTransactionForPenaltyAsync(
        ZKTecoDbContext dbContext,
        Domain.Entities.PaymentTransaction penalty,
        CancellationToken stoppingToken)
    {
        // Tìm hoặc tạo danh mục "Phạt nhân viên"
        var penaltyStoreId = penalty.Employee?.StoreId;
        var category = await dbContext.TransactionCategories
            .FirstOrDefaultAsync(c => c.Name == "Phạt nhân viên"
                && c.Type == CashTransactionType.Income
                && c.StoreId == penaltyStoreId,
                stoppingToken);

        if (category == null)
        {
            category = new Domain.Entities.TransactionCategory
            {
                Id = Guid.NewGuid(),
                Name = "Phạt nhân viên",
                Description = "Thu phạt nhân viên vi phạm nội quy (đi trễ, về sớm, ...)",
                Type = CashTransactionType.Income,
                Icon = "gavel",
                Color = "#F44336",
                IsSystem = true,
                StoreId = penaltyStoreId,
                IsActive = true,
                CreatedAt = DateTime.Now
            };
            dbContext.TransactionCategories.Add(category);
        }

        // Sinh mã phiếu thu
        var dateStr = DateTime.Now.ToString("yyyyMMdd");
        var txPrefix = $"TC-{dateStr}-";
        var txCount = await dbContext.CashTransactions
            .CountAsync(ct => ct.TransactionCode.StartsWith(txPrefix) && ct.StoreId == penaltyStoreId, stoppingToken);

        var employeeName = penalty.Employee != null
            ? $"{penalty.Employee.LastName} {penalty.Employee.FirstName}".Trim()
            : "N/A";

        var cashTransaction = new Domain.Entities.CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = $"{txPrefix}{(txCount + 1):D4}",
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = Math.Abs(penalty.Amount),
            TransactionDate = DateTime.Now,
            Description = $"Thu phạt - NV {employeeName} - {penalty.Description}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Pending,
            IsPaid = false,
            CreatedByUserId = penalty.PerformedById ?? Guid.Empty,
            StoreId = penaltyStoreId,
            InternalNote = $"Tự động tạo từ phiếu phạt #{penalty.Id}",
            CreatedAt = DateTime.Now,
            IsActive = true
        };

        dbContext.CashTransactions.Add(cashTransaction);

        // Cập nhật PaymentMethod trên penalty transaction
        penalty.PaymentMethod = "Cash";
    }
}
