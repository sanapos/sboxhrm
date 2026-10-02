using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public sealed class PayslipIdsRequest
{
    public List<Guid> Ids { get; set; } = [];
}

public sealed class PayslipPayItemDto
{
    public Guid PayslipId { get; set; }
    public decimal CashAmount { get; set; }
    public decimal BankAmount { get; set; }
}

public sealed class PayPayslipsRequest
{
    public List<PayslipPayItemDto> Items { get; set; } = [];
    /// <summary>Tài khoản cửa hàng chi phần chuyển khoản.</summary>
    public Guid? BankAccountId { get; set; }
    public DateTime? PaidAt { get; set; }
}

public sealed class PayslipBankExportRequest
{
    public List<Guid> Ids { get; set; } = [];
    public string? Template { get; set; }
}

/// <summary>
/// Trả lương: thông tin chuyển khoản từng nhân viên (VietQR, mở app ngân hàng), ghi nhận trả bằng tiền mặt /
/// chuyển khoản / kết hợp vào Thu chi, xuất file chuyển lương hàng loạt theo mẫu ngân hàng.
/// </summary>
[ApiController]
[Route("api/payslips")]
[Authorize(Policy = PolicyNames.ManagerOrAccountant)]
public class PayrollPaymentController(
    ZKTecoDbContext db,
    ISystemNotificationService notifications) : AuthenticatedControllerBase
{
    private async Task<List<(Payslip P, Employee E, decimal Remaining)>> LoadAsync(List<Guid> ids, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        ids = ids.Distinct().Take(1000).ToList();
        var rows = await db.Payslips.AsNoTracking().Include(p => p.Employee)
            .Where(p => ids.Contains(p.Id) && p.StoreId == storeId && p.Status != PayslipStatus.Cancelled)
            .ToListAsync(ct);
        return rows
            .Where(p => p.Employee != null)
            .Select(p =>
            {
                var paid = p.Status == PayslipStatus.Paid ? Math.Max(p.PaidAmount, p.NetSalary) : p.PaidAmount;
                return (p, p.Employee!, Math.Max(0, p.NetSalary - paid));
            })
            .OrderBy(x => x.Item2.EmployeeCode)
            .ToList();
    }

    /// <summary>Thông tin trả lương: còn phải trả, ngân hàng + STK nhân viên, QR, nội dung; tài khoản chi của cửa hàng.</summary>
    [HttpPost("payment-info")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> PaymentInfo([FromBody] PayslipIdsRequest req, CancellationToken ct)
    {
        var rows = await LoadAsync(req.Ids, ct);
        var items = rows.Select(x =>
        {
            var line = PayrollBankExport.Line(x.P, x.E, x.Remaining);
            var qr = line.Ready
                ? VietQRBanks.GenerateVietQRUrl(line.BankBin!, line.AccountNumber!, x.Remaining, line.Content, "compact2")
                  + "&accountName=" + Uri.EscapeDataString(line.AccountName)
                : null;
            return new
            {
                payslipId = x.P.Id,
                employeeId = x.E.Id,
                employeeCode = x.E.EmployeeCode,
                employeeName = line.EmployeeName,
                month = x.P.Month,
                year = x.P.Year,
                netSalary = x.P.NetSalary,
                paidAmount = x.P.NetSalary - x.Remaining,
                remaining = x.Remaining,
                bankText = x.E.BankName,
                bankRecognized = line.BankBin != null,
                bankCode = line.BankCode,
                bankBin = line.BankBin,
                bankShortName = line.BankShortName,
                bankLogo = line.BankCode != null && VietQRBanks.Banks.TryGetValue(line.BankCode, out var b) ? b.Logo : null,
                accountNumber = line.AccountNumber,
                accountName = line.AccountName,
                transferContent = line.Content,
                qrUrl = qr,
                ready = line.Ready,
            };
        }).ToList();

        var storeId = RequiredStoreId;
        var accounts = (await db.BankAccounts.AsNoTracking()
                .Where(a => a.StoreId == storeId && a.IsActive)
                .OrderByDescending(a => a.IsDefault).ThenBy(a => a.BankName)
                .ToListAsync(ct))
            .Select(a => new
            {
                id = a.Id,
                bankName = a.BankShortName ?? a.BankName,
                accountNumber = a.AccountNumber,
                accountName = a.AccountName,
                bin = a.BankCode,
                isDefault = a.IsDefault,
                // Mở app ngân hàng của tài khoản chi để chuyển (VietQR deeplink; đa số app chỉ mở, chưa tự điền).
                appId = VietQRBanks.DeeplinkAppId(a.BankCode),
            }).ToList();

        return Ok(AppResponse<object>.Success(new { items, sourceAccounts = accounts }));
    }

    /// <summary>
    /// Ghi nhận trả lương. Mỗi dòng: phần tiền mặt + phần chuyển khoản (từ <see cref="PayPayslipsRequest.BankAccountId"/>).
    /// Trả thiếu = trả một phần; phần còn lại giữ phiếu chi chờ.
    /// </summary>
    [HttpPost("pay")]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Pay([FromBody] PayPayslipsRequest req, CancellationToken ct)
    {
        if (req.Items.Count == 0) return Ok(AppResponse<object>.Error("Chưa chọn phiếu lương"));
        var storeId = RequiredStoreId;
        var ok = 0;
        decimal cash = 0, bank = 0;
        var errors = new List<string>();
        foreach (var item in req.Items.Take(1000))
        {
            var err = await PayslipPayments.PayAsync(db, notifications, storeId, CurrentUserId,
                new PayslipPayRequest(item.PayslipId, Math.Round(item.CashAmount, 0), Math.Round(item.BankAmount, 0),
                    req.BankAccountId, null, req.PaidAt), ct);
            db.ChangeTracker.Clear();
            if (err == null)
            {
                ok++;
                cash += item.CashAmount;
                bank += item.BankAmount;
            }
            else
            {
                errors.Add(err);
            }
        }
        if (ok == 0) return Ok(AppResponse<object>.Error(string.Join("\n", errors.Take(5))));
        return Ok(AppResponse<object>.Success(new { paid = ok, cash, bank, errors }));
    }

    [HttpGet("bank-export/templates")]
    [RequireModulePermission("Payslip", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> ExportTemplates() =>
        Ok(AppResponse<object>.Success(PayrollBankExport.Templates.Select(t => new { key = t.Key, name = t.Name, bin = t.Bin, note = t.Note }).ToList()));

    /// <summary>File Excel chuyển lương hàng loạt (số còn phải trả của các phiếu đã chọn) theo mẫu ngân hàng.</summary>
    [HttpPost("bank-export")]
    [RequireModulePermission("Payroll", ModulePermissionAction.Export)]
    public async Task<IActionResult> BankExport([FromBody] PayslipBankExportRequest req, CancellationToken ct)
    {
        var rows = await LoadAsync(req.Ids, ct);
        var lines = rows.Where(x => x.Remaining > 0).Select(x => PayrollBankExport.Line(x.P, x.E, x.Remaining)).ToList();
        if (lines.Count == 0) return Ok(AppResponse<object>.Error("Không còn phiếu lương nào chưa trả"));
        var t = PayrollBankExport.Find(req.Template);
        var periods = rows.Select(x => $"T{x.P.Month:D2}-{x.P.Year}").Distinct().ToList();
        var label = periods.Count == 1 ? periods[0] : "nhieu-ky";
        var bytes = PayrollBankExport.Build(t, lines, label.Replace('-', '/'));
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", $"chi-luong-{label}-{t.Key}.xlsx");
    }
}
