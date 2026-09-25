using System.Reflection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Tự duyệt phiếu phạt với DbContext NoTracking (giống cấu hình production):
/// lượt 1 duyệt + tạo đúng 1 phiếu thu mỗi phiếu, mã không trùng; lượt 2 không tạo thêm.
/// </summary>
public class PenaltyAutoApproveTests
{
    [Fact]
    public async Task Approves_each_ticket_once_with_unique_receipt_codes()
    {
        var dbName = Guid.NewGuid().ToString();
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(dbName)
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        var provider = services.BuildServiceProvider();

        var storeId = Guid.NewGuid();
        using (var scope = provider.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            db.Add(new ApplicationUser { Id = Guid.NewGuid(), UserName = "owner", FirstName = "O", LastName = "W", StoreId = storeId, Role = "Admin" });
            var employee = new Employee { Id = Guid.NewGuid(), StoreId = storeId, FirstName = "A", LastName = "B" };
            db.Add(employee);
            for (var i = 0; i < 3; i++)
            {
                db.Add(new PenaltyTicket
                {
                    Id = Guid.NewGuid(),
                    TicketCode = $"PP-{i}",
                    EmployeeId = employee.Id,
                    StoreId = storeId,
                    Amount = 50_000,
                    ViolationDate = DateTime.UtcNow.AddDays(-5),
                    Status = PenaltyTicketStatus.Pending,
                });
            }
            await db.SaveChangesAsync();
        }

        var service = new PenaltyAutoApproveBackgroundService(
            provider, NullLogger<PenaltyAutoApproveBackgroundService>.Instance);
        var run = typeof(PenaltyAutoApproveBackgroundService).GetMethod(
            "AutoApprovePendingPenaltyTicketsAsync", BindingFlags.NonPublic | BindingFlags.Instance)!;

        await (Task)run.Invoke(service, [CancellationToken.None])!;
        await (Task)run.Invoke(service, [CancellationToken.None])!; // lượt 30 phút sau

        using var check = provider.CreateScope();
        var verify = check.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var tickets = await verify.PenaltyTickets.ToListAsync();
        var receipts = await verify.CashTransactions.ToListAsync();

        Assert.All(tickets, t =>
        {
            Assert.Equal(PenaltyTicketStatus.AutoApproved, t.Status);
            Assert.NotNull(t.CashTransactionId);
        });
        Assert.Equal(3, receipts.Count);
        Assert.Equal(3, receipts.Select(r => r.TransactionCode).Distinct().Count());
        Assert.DoesNotContain(receipts, r => r.CreatedByUserId == Guid.Empty);
    }
}
