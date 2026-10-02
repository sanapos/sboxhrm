using System.Reflection;
using ClosedXML.Excel;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Trả lương: tiền mặt / chuyển khoản / kết hợp, trả một phần, hủy phiếu chi, xuất file ngân hàng.</summary>
public class PayrollPaymentTests
{
    private static readonly Guid Store = Guid.NewGuid();
    private static readonly Guid User = Guid.NewGuid();
    private static readonly ISystemNotificationService Noop = DispatchProxy.Create<ISystemNotificationService, MobileDeviceHubTests.NoopProxy>();

    private static ServiceProvider Provider()
    {
        var services = new ServiceCollection();
        var name = Guid.NewGuid().ToString();
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(name)
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        return services.BuildServiceProvider();
    }

    private static ZKTecoDbContext Db(ServiceProvider sp) => sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();

    private static async Task<(Guid Payslip, Guid Bank)> SeedAsync(ServiceProvider sp, decimal net = 10_000_000)
    {
        var db = Db(sp);
        var emp = new Employee
        {
            Id = Guid.NewGuid(), StoreId = Store, EmployeeCode = "NV001", LastName = "Nguyễn Văn", FirstName = "An",
            BankName = "Vietcombank - NH TMCP Ngoại thương Việt Nam", BankAccountNumber = "0011 0023 4567",
            BankAccountName = "Nguyễn Văn An", BranchId = Guid.NewGuid(),
        };
        var p = new Payslip
        {
            Id = Guid.NewGuid(), StoreId = Store, EmployeeId = emp.Id, SalaryProfileId = Guid.NewGuid(), Year = 2026, Month = 9,
            PeriodStart = new DateTime(2026, 9, 1), PeriodEnd = new DateTime(2026, 9, 30), NetSalary = net, GrossSalary = net,
            Status = PayslipStatus.Approved, Currency = "VND",
        };
        var bank = new BankAccount
        {
            Id = Guid.NewGuid(), StoreId = Store, AccountName = "CONG TY A", AccountNumber = "999", BankCode = "970407",
            BankName = "Techcombank", IsActive = true,
        };
        db.Employees.Add(emp);
        db.Payslips.Add(p);
        db.BankAccounts.Add(bank);
        await db.SaveChangesAsync();
        // Như sau khi chốt lương: phiếu chi chờ = thực lĩnh.
        await new PayslipPaymentService(Db(sp)).SyncAsync(p.Id, Store, User, ensurePending: true);
        return (p.Id, bank.Id);
    }

    private static Task<List<CashTransaction>> Vouchers(ServiceProvider sp, Guid payslipId) =>
        Db(sp).CashTransactions.Where(c => c.SourceId == payslipId).OrderBy(c => c.CreatedAt).ToListAsync();

    [Fact]
    public async Task Finalize_creates_one_pending_voucher_for_net_salary_with_branch()
    {
        using var sp = Provider();
        var (pid, _) = await SeedAsync(sp);
        var v = Assert.Single(await Vouchers(sp, pid));
        Assert.Equal(10_000_000, v.Amount);
        Assert.Equal(CashTransactionStatus.Pending, v.Status);
        Assert.NotNull(v.BranchId);
        // Đồng bộ lại không tạo trùng.
        await new PayslipPaymentService(Db(sp)).SyncAsync(pid, Store, User, ensurePending: true);
        Assert.Single(await Vouchers(sp, pid));
    }

    [Fact]
    public async Task Mixed_cash_and_bank_creates_two_paid_vouchers_and_marks_paid()
    {
        using var sp = Provider();
        var (pid, bank) = await SeedAsync(sp);

        var err = await PayslipPayments.PayAsync(Db(sp), Noop, Store, User,
            new PayslipPayRequest(pid, 3_000_000, 7_000_000, bank, "LUONG T09 2026 NV001", null));

        Assert.Null(err);
        var vs = (await Vouchers(sp, pid)).Where(v => v.Status != CashTransactionStatus.Cancelled).ToList();
        Assert.Equal(2, vs.Count);
        Assert.Contains(vs, v => v.PaymentMethod == PaymentMethodType.Cash && v.Amount == 3_000_000 && v.IsPaid && v.BankAccountId == null);
        Assert.Contains(vs, v => v.PaymentMethod == PaymentMethodType.BankTransfer && v.Amount == 7_000_000 && v.IsPaid && v.BankAccountId == bank);
        var p = await Db(sp).Payslips.SingleAsync(x => x.Id == pid);
        Assert.Equal(PayslipStatus.Paid, p.Status);
        Assert.Equal(10_000_000, p.PaidAmount);
    }

    [Fact]
    public async Task Partial_payment_keeps_pending_voucher_for_remaining()
    {
        using var sp = Provider();
        var (pid, _) = await SeedAsync(sp);

        Assert.Null(await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 4_000_000, 0, null, null, null)));

        var p = await Db(sp).Payslips.SingleAsync(x => x.Id == pid);
        Assert.Equal(PayslipStatus.Approved, p.Status);
        Assert.Equal(4_000_000, p.PaidAmount);
        var open = Assert.Single((await Vouchers(sp, pid)).Where(v => !v.IsPaid && v.Status == CashTransactionStatus.Pending));
        Assert.Equal(6_000_000, open.Amount);

        // Trả vượt số còn lại bị chặn; trả nốt thì đủ.
        Assert.NotNull(await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 7_000_000, 0, null, null, null)));
        Assert.Null(await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 6_000_000, 0, null, null, null)));
        Assert.Equal(PayslipStatus.Paid, (await Db(sp).Payslips.SingleAsync(x => x.Id == pid)).Status);
        Assert.DoesNotContain(await Vouchers(sp, pid), v => !v.IsPaid && v.Status == CashTransactionStatus.Pending);
    }

    [Fact]
    public async Task Bank_part_requires_source_account()
    {
        using var sp = Provider();
        var (pid, _) = await SeedAsync(sp);
        var err = await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 0, 10_000_000, null, null, null));
        Assert.Equal("Chọn tài khoản ngân hàng chi lương", err);
    }

    [Fact]
    public async Task Cancelling_a_paid_voucher_reopens_payslip()
    {
        using var sp = Provider();
        var (pid, bank) = await SeedAsync(sp);
        await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 3_000_000, 7_000_000, bank, null, null));

        var db = Db(sp);
        var bankVoucher = await db.CashTransactions.AsTracking().SingleAsync(c => c.SourceId == pid && c.PaymentMethod == PaymentMethodType.BankTransfer);
        bankVoucher.Status = CashTransactionStatus.Cancelled;
        bankVoucher.IsPaid = false;
        await db.SaveChangesAsync();
        await PayslipPayments.SyncForVoucherAsync(db, bankVoucher, Store, User, ensurePending: false);

        var p = await Db(sp).Payslips.SingleAsync(x => x.Id == pid);
        Assert.Equal(PayslipStatus.Approved, p.Status);
        Assert.Equal(3_000_000, p.PaidAmount);
    }

    [Fact]
    public async Task Refinalize_after_paid_with_raise_creates_supplement_voucher()
    {
        using var sp = Provider();
        var (pid, _) = await SeedAsync(sp);
        await PayslipPayments.PayAsync(Db(sp), Noop, Store, User, new PayslipPayRequest(pid, 10_000_000, 0, null, null, null));

        var db = Db(sp);
        var p = await db.Payslips.AsTracking().SingleAsync(x => x.Id == pid);
        p.NetSalary = 10_500_000; // chốt lại: tăng 500k
        await db.SaveChangesAsync();
        var state = await new PayslipPaymentService(Db(sp)).SyncAsync(pid, Store, User, ensurePending: true);

        Assert.NotNull(state);
        Assert.Equal(500_000, state!.Remaining);
        Assert.Equal(PayslipStatus.Approved, state.Status);
        Assert.Single((await Vouchers(sp, pid)).Where(v => !v.IsPaid && v.Status == CashTransactionStatus.Pending && v.Amount == 500_000));
    }

    [Theory]
    [InlineData("Vietcombank - NH TMCP Ngoại thương Việt Nam", "970436")]
    [InlineData("VietinBank - NH TMCP Công thương Việt Nam", "970415")]
    [InlineData("MB Bank - NH TMCP Quân đội", "970422")]
    [InlineData("Sacombank - NH TMCP Sài Gòn Thương Tín", "970403")]
    [InlineData("SHB - NH TMCP Sài Gòn - Hà Nội", "970443")]
    [InlineData("HDBank - NH TMCP Phát triển TP.HCM", "970437")]
    [InlineData("ngân hàng á châu", "970416")]
    [InlineData("970422", "970422")]
    [InlineData("TCB", "970407")]
    public void Resolves_free_text_bank_names(string text, string bin)
    {
        Assert.Equal(bin, VietQRBanks.Resolve(text)?.BIN);
    }

    [Fact]
    public void Unknown_bank_is_not_guessed()
    {
        Assert.Null(VietQRBanks.Resolve("Ngân hàng ABC không tồn tại"));
        Assert.Null(VietQRBanks.Resolve(""));
    }

    [Fact]
    public void Bank_export_splits_same_bank_other_bank_and_missing()
    {
        var p = new Payslip { Id = Guid.NewGuid(), Month = 9, Year = 2026 };
        PayrollTransferLine L(string code, string bank, string? acc, decimal amt) => PayrollBankExport.Line(p,
            new Employee { EmployeeCode = code, LastName = "Trần Thị", FirstName = "Bình", BankName = bank, BankAccountNumber = acc }, amt);
        var lines = new[]
        {
            L("NV1", "Vietcombank", "0011002345", 8_000_000),
            L("NV2", "Techcombank", "1903", 6_500_000),
            L("NV3", "Vietcombank", null, 5_000_000),
        };
        var bytes = PayrollBankExport.Build(PayrollBankExport.Find("VCB"), lines, "T09/2026");
        using var wb = new XLWorkbook(new MemoryStream(bytes));
        var same = wb.Worksheet("Cung ngan hang");
        Assert.Equal("0011002345", same.Cell(2, 2).GetString()); // giữ số 0 đầu
        Assert.Equal("TRAN THI BINH", same.Cell(2, 3).GetString());
        Assert.Equal(8_000_000, same.Cell(2, 4).GetValue<decimal>());
        Assert.Equal("LUONG T09 2026 NV1", same.Cell(2, 5).GetString());
        Assert.Equal("1903", wb.Worksheet("Khac ngan hang").Cell(2, 2).GetString());
        Assert.Equal("NV3", wb.Worksheet("Thieu thong tin").Cell(2, 2).GetString());
    }
}
