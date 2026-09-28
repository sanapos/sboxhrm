using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Tài chính nhân sự v2: hạn mức ứng, trả góp, liên kết chứng từ, chống tính tiền 2 lần, nguồn cộng/trừ lương.</summary>
public class HrFinanceTests
{
    private static (ServiceProvider provider, ZKTecoDbContext db) NewDb()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        var provider = services.BuildServiceProvider();
        var db = provider.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        return (provider, db);
    }

    [Fact]
    public void Advance_installments_split_exactly_and_legacy_uses_paid_month()
    {
        var a = new AdvanceRequest { Amount = 1_000_000, ForYear = 2026, ForMonth = 11, InstallmentCount = 3, IsPaid = true };
        Assert.Equal(0, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2026, 10));
        Assert.Equal(333_333, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2026, 11));
        Assert.Equal(333_333, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2026, 12));
        Assert.Equal(333_334, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2027, 1));
        Assert.Equal(0, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2027, 2));

        a.ApprovedAmount = 600_000; // duyệt một phần → trừ theo số đã duyệt
        Assert.Equal(200_000, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(a, 2026, 11));

        // Yêu cầu cũ (InstallmentCount = 0): trừ 1 lần vào tháng chi tiền, bỏ qua ForMonth
        var legacy = new AdvanceRequest { Amount = 500_000, ForYear = 2026, ForMonth = 9, InstallmentCount = 0, PaidDate = new DateTime(2026, 8, 28) };
        Assert.Equal(500_000, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(legacy, 2026, 8));
        Assert.Equal(0, HrFinanceSettingsHelper.AdvanceDeductionForPeriod(legacy, 2026, 9));
    }

    [Fact]
    public void Advance_limit_takes_smaller_of_percent_and_amount()
    {
        var s = new HrFinanceSettings { AdvanceLimitPercent = 50 };
        Assert.Equal(5_000_000, HrFinanceSettingsHelper.AdvanceLimit(s, 10_000_000));
        s.AdvanceLimitAmount = 3_000_000;
        Assert.Equal(3_000_000, HrFinanceSettingsHelper.AdvanceLimit(s, 10_000_000));
        Assert.Equal(3_000_000, HrFinanceSettingsHelper.AdvanceLimit(s, null)); // chưa có lương → theo số tiền
        s.AdvanceLimitAmount = null;
        Assert.Null(HrFinanceSettingsHelper.AdvanceLimit(s, null));
        s.AdvanceLimitPercent = null;
        Assert.Null(HrFinanceSettingsHelper.AdvanceLimit(s, 10_000_000));

        Assert.Equal(300_000m * 26, HrFinanceSettingsHelper.MonthlyFromRate("Daily", 300_000));
        Assert.Equal(25_000m * 8 * 26, HrFinanceSettingsHelper.MonthlyFromRate("Hourly", 25_000));
        Assert.Equal(9_000_000m, HrFinanceSettingsHelper.MonthlyFromRate("Monthly", 9_000_000));
    }

    [Fact]
    public void Markers_map_to_source_type_without_confusion()
    {
        var id = Guid.NewGuid();
        Assert.Equal((PaymentFinanceHelper.SourceAdvance, id), PaymentFinanceHelper.SourceFromMarker(PaymentFinanceHelper.AdvanceNote(id)));
        Assert.Equal((PaymentFinanceHelper.SourceReward, id), PaymentFinanceHelper.SourceFromMarker(PaymentFinanceHelper.BonusPenaltyNote(id)));
        Assert.Equal((PaymentFinanceHelper.SourceTripAdvance, id), PaymentFinanceHelper.SourceFromMarker(BusinessTripFinanceHelper.TripAdvanceNote(id)));
        Assert.Equal((PaymentFinanceHelper.SourceTripSettlement, id), PaymentFinanceHelper.SourceFromMarker(BusinessTripFinanceHelper.SettlementExtraNote(id)));
        Assert.Equal((PaymentFinanceHelper.SourceTripRefund, id), PaymentFinanceHelper.SourceFromMarker(BusinessTripFinanceHelper.SurplusRefundNote(id)));
        Assert.Null(PaymentFinanceHelper.SourceFromMarker("Ghi chú tự do"));
    }

    private static async Task<(Guid storeId, Employee emp)> SeedAsync(ZKTecoDbContext db, HrFinanceSettings? settings = null)
    {
        var storeId = Guid.NewGuid();
        var emp = new Employee { Id = Guid.NewGuid(), StoreId = storeId, FirstName = "An", LastName = "Lê", EmployeeCode = "NV01", ApplicationUserId = Guid.NewGuid() };
        db.Add(emp);
        db.Add(new TransactionCategory { Id = Guid.NewGuid(), StoreId = storeId, Name = "Thưởng nhân viên", Type = CashTransactionType.Expense, IsActive = true });
        db.Add(new TransactionCategory { Id = Guid.NewGuid(), StoreId = storeId, Name = "Phạt nhân viên", Type = CashTransactionType.Income, IsActive = true });
        if (settings != null) { settings.Id = Guid.NewGuid(); settings.StoreId = storeId; db.Add(settings); }
        await db.SaveChangesAsync();
        return (storeId, emp);
    }

    [Fact]
    public async Task Approve_salary_penalty_creates_no_cash_and_cash_bonus_is_skipped_by_payroll()
    {
        var (provider, db) = NewDb();
        using var _ = provider;
        var (storeId, emp) = await SeedAsync(db);
        var actor = Guid.NewGuid();

        // Phạt không chọn cách xử lý → mặc định trừ lương, KHÔNG tạo phiếu thu (trước đây bị tính 2 lần)
        var penalty = new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Penalty", Amount = 100_000, Status = "Completed", TransactionDate = DateTime.Now };
        db.Add(penalty);
        await db.SaveChangesAsync();
        var cash = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(db, penalty, storeId, actor);
        Assert.Null(cash);
        Assert.Equal("Salary", penalty.PaymentMethod);
        Assert.Equal("salary", penalty.Settlement);
        Assert.Equal(0, await db.CashTransactions.CountAsync());

        // Thưởng tiền mặt → 1 phiếu chi có nguồn chuẩn, PaymentMethod=Cash để bảng lương bỏ qua
        var bonus = new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Bonus", Amount = 300_000, Status = "Completed", TransactionDate = DateTime.Now };
        db.Add(bonus);
        await db.SaveChangesAsync();
        var c1 = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(db, bonus, storeId, actor, "Cash");
        Assert.NotNull(c1);
        Assert.Equal("Cash", bonus.PaymentMethod);
        Assert.Equal(PaymentFinanceHelper.SourceReward, c1!.SourceType);
        Assert.Equal(bonus.Id, c1.SourceId);
        Assert.Equal(emp.Id, c1.EmployeeId);
        Assert.Equal(c1.Id, bonus.CashTransactionId);

        // Duyệt lại không tạo phiếu trùng; tìm được theo nguồn
        var c2 = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(db, bonus, storeId, actor, "Cash");
        Assert.Equal(c1.Id, c2!.Id);
        Assert.Equal(1, await db.CashTransactions.CountAsync());
        var linked = await PaymentFinanceHelper.ResolveLinkedAsync(db, storeId, PaymentFinanceHelper.BonusPenaltyNote(bonus.Id));
        Assert.Equal(c1.Id, linked!.Id);

        // Hoàn duyệt khi phiếu chi chưa trả → bỏ đánh dấu; đã trả thì giữ
        PaymentFinanceHelper.ClearSalaryDisbursementOnUnapprove(bonus, linked);
        Assert.Null(bonus.PaymentMethod);
        bonus.PaymentMethod = "Cash";
        linked.IsPaid = true;
        PaymentFinanceHelper.ClearSalaryDisbursementOnUnapprove(bonus, linked);
        Assert.Equal("Cash", bonus.PaymentMethod);
    }

    [Fact]
    public async Task Store_default_cash_penalty_creates_income_receipt()
    {
        var (provider, db) = NewDb();
        using var _ = provider;
        var (storeId, emp) = await SeedAsync(db, new HrFinanceSettings { PenaltyDefaultSettlement = "cash" });
        var penalty = new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Penalty", Amount = 50_000, Status = "Completed", TransactionDate = DateTime.Now };
        db.Add(penalty);
        await db.SaveChangesAsync();
        var cash = await PaymentFinanceHelper.ApplyBonusPenaltyDisbursementOnApproveAsync(db, penalty, storeId, Guid.NewGuid());
        Assert.NotNull(cash);
        Assert.Equal(CashTransactionType.Income, cash!.Type);
        Assert.Equal("Cash", penalty.PaymentMethod);
    }

    [Fact]
    public async Task Payroll_adjustments_follow_settlement_and_advance_period_rules()
    {
        var (provider, db) = NewDb();
        using var _ = provider;
        var (storeId, emp) = await SeedAsync(db);
        var other = new Employee { Id = Guid.NewGuid(), StoreId = storeId, FirstName = "Bình", LastName = "Trần", EmployeeCode = "NV02" };
        db.Add(other);
        var inOct = new DateTime(2026, 10, 10);
        db.AddRange(
            new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Bonus", Amount = 200_000, Status = "Completed", PaymentMethod = "Salary", TransactionDate = inOct },
            new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Bonus", Amount = 999_000, Status = "Completed", PaymentMethod = "Cash", TransactionDate = inOct },
            new PaymentTransaction { Id = Guid.NewGuid(), EmployeeUserId = emp.ApplicationUserId, Type = "Penalty", Amount = -30_000, Status = "Completed", TransactionDate = inOct },
            new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Bonus", Amount = 777_000, Status = "Pending", TransactionDate = inOct },
            new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Bonus", Amount = 555_000, Status = "Completed", TransactionDate = new DateTime(2026, 9, 30) },
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = emp.Id, TicketCode = "PP1", Amount = 20_000, Status = PenaltyTicketStatus.AutoApproved, ViolationDate = inOct },
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = emp.Id, TicketCode = "PP2", Amount = 40_000, Status = PenaltyTicketStatus.Approved, CollectionMethod = "Cash", ViolationDate = inOct },
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = emp.Id, TicketCode = "PP3", Amount = 60_000, Status = PenaltyTicketStatus.Pending, ViolationDate = inOct },
            new AdvanceRequest { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = emp.Id, Amount = 2_000_000, Status = AdvanceRequestStatus.Approved, IsPaid = true, PaidDate = new DateTime(2026, 9, 25), ForYear = 2026, ForMonth = 10, InstallmentCount = 2 },
            new AdvanceRequest { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = other.Id, Amount = 400_000, Status = AdvanceRequestStatus.Approved, IsPaid = true, PaidDate = new DateTime(2026, 10, 5), ForYear = 2026, ForMonth = 11, InstallmentCount = 0 },
            new AdvanceRequest { Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = other.Id, Amount = 900_000, Status = AdvanceRequestStatus.Approved, IsPaid = false, ForYear = 2026, ForMonth = 10, InstallmentCount = 1 });
        await db.SaveChangesAsync();

        var emps = new List<(Guid, Guid?, string, string)>
        {
            (emp.Id, emp.ApplicationUserId, "Lê An", "NV01"),
            (other.Id, null, "Trần Bình", "NV02"),
        };
        var rows = await HrFinanceController.ComputePayrollAdjustmentsAsync(db, storeId, emps, new DateTime(2026, 10, 1), new DateTime(2026, 10, 31));
        var r1 = rows.Single(r => r.EmployeeId == emp.Id);
        Assert.Equal(200_000, r1.Bonus);          // bỏ thưởng tiền mặt, chờ duyệt, tháng khác
        Assert.Equal(30_000, r1.Penalty);         // phạt thủ công theo EmployeeUserId, lấy trị tuyệt đối
        Assert.Equal(20_000, r1.TicketPenalty);   // bỏ phiếu thu tiền mặt + phiếu chờ duyệt
        Assert.Equal(1_000_000, r1.Advance);      // trừ theo kỳ ForMonth=10, góp 2 kỳ (dù chi 25/9)
        var r2 = rows.Single(r => r.EmployeeId == other.Id);
        Assert.Equal(400_000, r2.Advance);        // yêu cầu cũ: theo ngày chi trong kỳ; chưa chi thì không trừ

        var nov = await HrFinanceController.ComputePayrollAdjustmentsAsync(db, storeId, emps, new DateTime(2026, 11, 1), new DateTime(2026, 11, 30));
        Assert.Equal(1_000_000, nov.Single(r => r.EmployeeId == emp.Id).Advance);
        Assert.DoesNotContain(nov, r => r.EmployeeId == other.Id);
    }
}
