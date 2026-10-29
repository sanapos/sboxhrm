using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Commands.BusinessTrip;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>Duyệt hạch toán công tác không được xóa phiếu hạch toán / dòng chi / người công tác (QA 29/10/2026).</summary>
public class BusinessTripSettlementApproveTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    sealed class NoUserStore : IUserStore<ApplicationUser>
    {
        public void Dispose() { }
        public Task<string> GetUserIdAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task<string?> GetUserNameAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task SetUserNameAsync(ApplicationUser user, string? userName, CancellationToken ct) => throw new NotSupportedException();
        public Task<string?> GetNormalizedUserNameAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task SetNormalizedUserNameAsync(ApplicationUser user, string? normalizedName, CancellationToken ct) => throw new NotSupportedException();
        public Task<IdentityResult> CreateAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task<IdentityResult> UpdateAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task<IdentityResult> DeleteAsync(ApplicationUser user, CancellationToken ct) => throw new NotSupportedException();
        public Task<ApplicationUser?> FindByIdAsync(string userId, CancellationToken ct) => Task.FromResult<ApplicationUser?>(null);
        public Task<ApplicationUser?> FindByNameAsync(string normalizedUserName, CancellationToken ct) => Task.FromResult<ApplicationUser?>(null);
    }

    [Fact]
    public async Task Approve_keeps_settlement_lines_and_employee()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var storeId = Guid.NewGuid();
        var user = new ApplicationUser { Id = Guid.NewGuid(), UserName = "owner@x.test", Email = "owner@x.test", FirstName = "A", LastName = "Chủ" };
        var cat = new BusinessTripExpenseCategory { Id = Guid.NewGuid(), StoreId = storeId, Code = "AN", Name = "Tiền ăn" };
        var tripCase = new BusinessTripCase
        {
            Id = Guid.NewGuid(), StoreId = storeId, CaseCode = "CT-1", Title = "Test", EmployeeUserId = user.Id,
            Status = BusinessTripCaseStatus.SettlementPending, SettledAmount = 150000, BalanceAmount = 150000,
        };
        var settlement = new BusinessTripSettlementClaim
        {
            Id = Guid.NewGuid(), CaseId = tripCase.Id, StoreId = storeId, TotalAmount = 150000, BalanceAmount = 150000,
            Status = AdvanceRequestStatus.Pending, TotalApprovalLevels = 1,
        };
        db.AddRange(user, cat, tripCase, settlement,
            new BusinessTripExpenseLine { Id = Guid.NewGuid(), SettlementClaimId = settlement.Id, CategoryId = cat.Id, Amount = 150000, ExpenseDate = DateTime.Today },
            new BusinessTripSettlementApprovalRecord
            {
                Id = Guid.NewGuid(), SettlementClaimId = settlement.Id, StoreId = storeId, StepOrder = 1,
                StepName = "Quản lý", Status = ApprovalStatus.Pending,
            });
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var tenant = new NoTenant();
        var users = new UserManager<ApplicationUser>(new NoUserStore(), null!, null!, null!, null!, null!, null!, null!,
            NullLogger<UserManager<ApplicationUser>>.Instance);
        var handler = new ApproveBusinessTripSettlementHandler(
            new EfRepository<BusinessTripCase>(db, NullLogger<EfRepository<BusinessTripCase>>.Instance, tenant),
            new EfRepository<BusinessTripSettlementClaim>(db, NullLogger<EfRepository<BusinessTripSettlementClaim>>.Instance, tenant),
            new EfRepository<BusinessTripSettlementApprovalRecord>(db, NullLogger<EfRepository<BusinessTripSettlementApprovalRecord>>.Instance, tenant),
            users,
            null!); // thông báo nằm trong try/catch

        var res = await handler.Handle(new ApproveBusinessTripSettlementCommand(storeId, tripCase.Id, Guid.NewGuid(), true, null), default);

        Assert.True(res.IsSuccess, res.Message);
        db.ChangeTracker.Clear();
        var saved = await db.Set<BusinessTripSettlementClaim>().AsNoTracking().SingleOrDefaultAsync(s => s.CaseId == tripCase.Id);
        Assert.NotNull(saved);
        Assert.Equal(AdvanceRequestStatus.Approved, saved!.Status);
        Assert.Equal(1, await db.Set<BusinessTripExpenseLine>().CountAsync(l => l.SettlementClaimId == settlement.Id));
        var reloaded = await db.Set<BusinessTripCase>().AsNoTracking().SingleAsync(c => c.Id == tripCase.Id);
        Assert.Equal(user.Id, reloaded.EmployeeUserId);
        Assert.NotNull(res.Data?.Settlement);
    }
}
