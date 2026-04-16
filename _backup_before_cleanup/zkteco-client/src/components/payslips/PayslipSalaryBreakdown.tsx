import { Payslip } from '@/types/payslip';

interface PayslipSalaryBreakdownProps {
  payslip: Payslip;
}

export function PayslipSalaryBreakdown({ payslip }: PayslipSalaryBreakdownProps) {
  const formatCurrency = (amount: number, currency: string = 'USD') => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency,
    }).format(amount);
  };

  return (
    <div>
      <h3 className="font-semibold mb-3">Salary Breakdown</h3>
      <div className="space-y-2">
        <div className="flex justify-between p-2 border-b">
          <span>Base Salary</span>
          <span className="font-medium">{formatCurrency(payslip.baseSalary, payslip.currency)}</span>
        </div>
        {payslip.overtimePay && (
          <div className="flex justify-between p-2 border-b">
            <span>Overtime Pay</span>
            <span className="font-medium text-blue-600">{formatCurrency(payslip.overtimePay, payslip.currency)}</span>
          </div>
        )}
        {payslip.holidayPay && (
          <div className="flex justify-between p-2 border-b">
            <span>Holiday Pay</span>
            <span className="font-medium text-blue-600">{formatCurrency(payslip.holidayPay, payslip.currency)}</span>
          </div>
        )}
        {payslip.nightShiftPay && (
          <div className="flex justify-between p-2 border-b">
            <span>Night Shift Pay</span>
            <span className="font-medium text-blue-600">{formatCurrency(payslip.nightShiftPay, payslip.currency)}</span>
          </div>
        )}
        {payslip.bonus && (
          <div className="flex justify-between p-2 border-b">
            <span>Bonus</span>
            <span className="font-medium text-green-600">{formatCurrency(payslip.bonus, payslip.currency)}</span>
          </div>
        )}
        <div className="flex justify-between p-2 bg-muted font-semibold">
          <span>Gross Salary</span>
          <span>{formatCurrency(payslip.grossSalary, payslip.currency)}</span>
        </div>
        {payslip.deductions && (
          <div className="flex justify-between p-2 border-b">
            <span>Deductions</span>
            <span className="font-medium text-red-600">-{formatCurrency(payslip.deductions, payslip.currency)}</span>
          </div>
        )}
        <div className="flex justify-between p-3 bg-green-50 dark:bg-green-950 rounded-lg font-bold text-lg">
          <span>Net Salary</span>
          <span className="text-green-600">{formatCurrency(payslip.netSalary, payslip.currency)}</span>
        </div>
      </div>
    </div>
  );
}
