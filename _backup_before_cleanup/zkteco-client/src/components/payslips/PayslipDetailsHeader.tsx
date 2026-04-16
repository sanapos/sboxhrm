import { format } from 'date-fns';
import { Payslip } from '@/types/payslip';
import { PayslipStatusBadge } from './PayslipStatusBadge';

interface PayslipDetailsHeaderProps {
  payslip: Payslip;
}

export function PayslipDetailsHeader({ payslip }: PayslipDetailsHeaderProps) {
  return (
    <div className="grid grid-cols-2 gap-4 p-4 bg-muted rounded-lg">
      <div>
        <div className="text-sm text-muted-foreground">Employee</div>
        <div className="font-medium">{payslip.employeeName}</div>
      </div>
      <div>
        <div className="text-sm text-muted-foreground">Period</div>
        <div className="font-medium">
          {format(new Date(payslip.periodStart), 'MMM dd, yyyy')} - {format(new Date(payslip.periodEnd), 'MMM dd, yyyy')}
        </div>
      </div>
      <div>
        <div className="text-sm text-muted-foreground">Salary Profile</div>
        <div className="font-medium">{payslip.salaryProfileName}</div>
      </div>
      <div>
        <div className="text-sm text-muted-foreground">Status</div>
        <PayslipStatusBadge status={payslip.status} statusName={payslip.statusName} />
      </div>
    </div>
  );
}
