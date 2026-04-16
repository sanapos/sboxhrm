import { Button } from '@/components/ui/button';
import { TableCell, TableRow } from '@/components/ui/table';
import { Calendar, DollarSign, Download, Eye } from 'lucide-react';
import { format } from 'date-fns';
import { Payslip } from '@/types/payslip';
import { PayslipStatusBadge } from './PayslipStatusBadge';

interface PayslipTableRowProps {
  payslip: Payslip;
  onView: (payslip: Payslip) => void;
}

export function PayslipTableRow({ payslip, onView }: PayslipTableRowProps) {
  const formatCurrency = (amount: number, currency: string = 'USD') => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency,
    }).format(amount);
  };

  const getMonthName = (month: number) => {
    const date = new Date(2024, month - 1, 1);
    return format(date, 'MMMM');
  };

  console.log('Rendering PayslipTableRow for payslip ID:', payslip);
  return (
    <TableRow>
      <TableCell>
        <div className="flex items-center gap-2">
          <Calendar className="w-4 h-4 text-muted-foreground" />
          <span className="font-medium">
            {getMonthName(payslip.month)} {payslip.year}
          </span>
        </div>

        <div className="text-xs text-muted-foreground mt-1">
          {format(new Date(payslip.periodStart), 'MMM dd')} - {format(new Date(payslip.periodEnd), 'MMM dd, yyyy')}
        </div>
      </TableCell>
      <TableCell>
        {payslip.employeeName}
      </TableCell>
      <TableCell>
        <div className="font-medium">{payslip.salaryProfileName}</div>
      </TableCell>
      <TableCell>
        <div>{payslip.regularWorkUnits.toFixed(2)}</div>
        {payslip.overtimeUnits && (
          <div className="text-xs text-muted-foreground">
            + {payslip.overtimeUnits.toFixed(2)} OT
          </div>
        )}
      </TableCell>
      <TableCell>
        <div className="font-medium">{formatCurrency(payslip.grossSalary, payslip.currency)}</div>
      </TableCell>
      <TableCell>
        {payslip.deductions ? formatCurrency(payslip.deductions, payslip.currency) : '-'}
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <DollarSign className="w-4 h-4 text-green-600" />
          <span className="font-bold text-green-600">
            {formatCurrency(payslip.netSalary, payslip.currency)}
          </span>
        </div>
      </TableCell>
      <TableCell>
        <PayslipStatusBadge status={payslip.status} statusName={payslip.statusName} />
      </TableCell>
      <TableCell>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onView(payslip)}
          >
            <Eye className="w-4 h-4 mr-1" />
            View
          </Button>
          <Button variant="ghost" size="sm">
            <Download className="w-4 h-4 mr-1" />
            PDF
          </Button>
        </div>
      </TableCell>
    </TableRow>
  );
}
