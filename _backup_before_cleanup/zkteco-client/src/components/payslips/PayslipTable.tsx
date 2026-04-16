import { Card } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Payslip } from '@/types/payslip';
import { PayslipTableRow } from './PayslipTableRow';

interface PayslipTableProps {
  payslips: Payslip[];
  onViewPayslip: (payslip: Payslip) => void;
}

export function PayslipTable({ payslips, onViewPayslip }: PayslipTableProps) {
  return (
    <Card>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Period</TableHead>
            <TableHead>Employee Name</TableHead>
            <TableHead>Salary Profile</TableHead>
            <TableHead>Work Units</TableHead>
            <TableHead>Gross Salary</TableHead>
            <TableHead>Deductions</TableHead>
            <TableHead>Net Salary</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {payslips.map((payslip) => (
            <PayslipTableRow
              key={payslip.id}
              payslip={payslip}
              onView={onViewPayslip}
            />
          ))}
        </TableBody>
      </Table>
    </Card>
  );
}
