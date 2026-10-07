using ZKTecoADMS.Application.Helpers;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Tự duyệt phiếu phạt sau kết ca + N giờ (PenaltySetting.AutoApproveHoursAfterShift).
/// Chạy mỗi 15 phút. Phiếu đang khiếu nại (DisputeStatus = 1) sẽ bỏ qua.
/// </summary>
public class PenaltyAutoApproveBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<PenaltyAutoApproveBackgroundService> _logger;
    private readonly TimeSpan _checkInterval = TimeSpan.FromMinutes(15);

    public PenaltyAutoApproveBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<PenaltyAutoApproveBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Penalty Auto-Approve Background Service started");
        await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await AutoApprovePendingPenaltiesAsync(stoppingToken);
                await AutoApprovePendingPenaltyTicketsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in penalty auto-approve service");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }
    }

    /// <summary>Legacy: tự duyệt PaymentTransaction Type=Penalty.</summary>
    private async Task AutoApprovePendingPenaltiesAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        var cutoffDate = DateTime.UtcNow.Date;
        var pendingPenalties = await dbContext.PaymentTransactions
            .AsTracking()
            .Include(pt => pt.Employee)
            .Where(pt => pt.Type == "Penalty"
                && pt.Status == "Pending"
                && pt.TransactionDate.Date < cutoffDate
                && pt.Note != null && pt.Note.Contains("Tự động tạo từ chấm công"))
            .ToListAsync(stoppingToken);

        if (pendingPenalties.Count == 0) return;

        _logger.LogInformation("Found {Count} pending legacy penalty transactions to auto-approve", pendingPenalties.Count);

        foreach (var penalty in pendingPenalties)
        {
            try
            {
                var actor = penalty.PerformedById
                    ?? await PenaltyTicketFinanceHelper.ResolveSystemActorAsync(
                        dbContext, penalty.Employee?.StoreId, stoppingToken);
                if (actor == null) continue;

                penalty.Status = "Completed";
                await CreateCashTransactionForPenaltyAsync(dbContext, penalty, actor.Value, stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error auto-approving legacy penalty {Id}", penalty.Id);
            }
        }

        await dbContext.SaveChangesAsync(stoppingToken);
    }

    private async Task CreateCashTransactionForPenaltyAsync(
        ZKTecoDbContext dbContext,
        Domain.Entities.PaymentTransaction penalty,
        Guid createdByUserId,
        CancellationToken stoppingToken)
    {
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
                CreatedAt = DateTime.UtcNow
            };
            dbContext.TransactionCategories.Add(category);
        }

        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        var txPrefix = $"TC-{dateStr}-";
        var txCode = await PenaltyTicketFinanceHelper.NextTransactionCodeAsync(
            dbContext, penaltyStoreId, txPrefix, stoppingToken);

        var employeeName = penalty.Employee != null
            ? $"{penalty.Employee.LastName} {penalty.Employee.FirstName}".Trim()
            : "N/A";

        var cashTransaction = new Domain.Entities.CashTransaction
        {
            Id = Guid.NewGuid(),
            TransactionCode = txCode,
            Type = CashTransactionType.Income,
            CategoryId = category.Id,
            Amount = Math.Abs(penalty.Amount),
            TransactionDate = VnTimeHelper.NowVn(),
            Description = $"Thu phạt - NV {employeeName} - {penalty.Description}",
            PaymentMethod = PaymentMethodType.Cash,
            Status = CashTransactionStatus.Pending,
            IsPaid = false,
            CreatedByUserId = createdByUserId,
            StoreId = penaltyStoreId,
            InternalNote = $"Tự động tạo từ phiếu phạt #{penalty.Id}",
            CreatedAt = DateTime.UtcNow,
            IsActive = true
        };

        dbContext.CashTransactions.Add(cashTransaction);
        penalty.PaymentMethod = "Cash";
    }

    /// <summary>
    /// Tự duyệt PenaltyTicket dựa trên giờ kết ca + AutoApproveHoursAfterShift.
    /// VD: Ca 8-17h, AutoApproveHoursAfterShift = 2 → phiếu phạt tự duyệt lúc 19h cùng ngày.
    /// Phiếu đang khiếu nại (DisputeStatus = 1) → bỏ qua, chờ quản lý xử lý.
    /// AutoApproveHoursAfterShift = 0 → tắt tự duyệt.
    /// </summary>
    private async Task AutoApprovePendingPenaltyTicketsAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        var nowVn = VnTimeHelper.NowVn();

        var settingsByStore = await dbContext.PenaltySettings.AsNoTracking()
            .ToDictionaryAsync(s => s.StoreId ?? Guid.Empty, stoppingToken);

        var pendingTickets = await dbContext.PenaltyTickets
            .AsTracking()
            .Include(t => t.Employee)
            .Where(t => t.Status == PenaltyTicketStatus.Pending
                && t.CashTransactionId == null
                && t.DisputeStatus != 1)
            .ToListAsync(stoppingToken);

        if (pendingTickets.Count == 0) return;

        var now = DateTime.UtcNow;
        var approved = 0;

        foreach (var ticket in pendingTickets)
        {
            try
            {
                var storeKey = ticket.StoreId ?? Guid.Empty;
                settingsByStore.TryGetValue(storeKey, out var setting);
                var hoursAfterShift = setting?.AutoApproveHoursAfterShift ?? 2;

                if (hoursAfterShift <= 0) continue;

                var shiftEnd = ticket.ShiftEndTime ?? new TimeSpan(18, 0, 0);
                var autoApproveAt = ticket.ViolationDate.Date + shiftEnd + TimeSpan.FromHours(hoursAfterShift);

                // Ca qua đêm: kết ca thuộc ngày hôm sau
                if (ticket.ShiftStartTime.HasValue && shiftEnd < ticket.ShiftStartTime.Value)
                    autoApproveAt = autoApproveAt.AddDays(1);

                if (nowVn < autoApproveAt) continue;

                await PenaltyTicketFinanceHelper.ApplyCollectionAsync(
                    dbContext, ticket, createdByUserId: null, stoppingToken);
                ticket.Status = PenaltyTicketStatus.AutoApproved;
                ticket.ProcessedDate = now;
                ticket.UpdatedAt = now;
                approved++;

                _logger.LogInformation("Auto-approved PenaltyTicket {Code} (shift end {ShiftEnd}, +{Hours}h) - {Amount}",
                    ticket.TicketCode, shiftEnd, hoursAfterShift, ticket.Amount);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error auto-approving PenaltyTicket {Id}", ticket.Id);
            }
        }

        if (approved > 0)
        {
            await dbContext.SaveChangesAsync(stoppingToken);
            _logger.LogInformation("Auto-approved {Count} PenaltyTicket(s)", approved);
        }
    }
}
