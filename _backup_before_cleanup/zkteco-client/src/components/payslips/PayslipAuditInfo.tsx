import { format } from 'date-fns';
import { Payslip } from '@/types/payslip';

interface PayslipAuditInfoProps {
  payslip: Payslip;
}

export function PayslipAuditInfo({ payslip }: PayslipAuditInfoProps) {
  return (
    <div className="text-xs text-muted-foreground space-y-1 pt-4 border-t">
      {payslip.generatedDate && (
        <div>
          Generated on {format(new Date(payslip.generatedDate), 'PPp')}
          {payslip.generatedByUserName && ` by ${payslip.generatedByUserName}`}
        </div>
      )}
      {payslip.approvedDate && (
        <div>
          Approved on {format(new Date(payslip.approvedDate), 'PPp')}
          {payslip.approvedByUserName && ` by ${payslip.approvedByUserName}`}
        </div>
      )}
      {payslip.paidDate && (
        <div>Paid on {format(new Date(payslip.paidDate), 'PPp')}</div>
      )}
    </div>
  );
}
