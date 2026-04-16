import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Payslip } from '@/types/payslip';
import { PayslipDetailsHeader } from './PayslipDetailsHeader';
import { PayslipWorkUnits } from './PayslipWorkUnits';
import { PayslipSalaryBreakdown } from './PayslipSalaryBreakdown';
import { PayslipAuditInfo } from './PayslipAuditInfo';
import { format } from 'date-fns';

interface PayslipDetailsDialogProps {
  payslip: Payslip | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function PayslipDetailsDialog({ payslip, open, onOpenChange }: PayslipDetailsDialogProps) {
  const getMonthName = (month: number) => {
    const date = new Date(2024, month - 1, 1);
    return format(date, 'MMMM');
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Payslip Details</DialogTitle>
          <DialogDescription>
            {payslip && `${getMonthName(payslip.month)} ${payslip.year}`}
          </DialogDescription>
        </DialogHeader>
        
        {payslip && (
          <div className="space-y-6">
            <PayslipDetailsHeader payslip={payslip} />
            <PayslipWorkUnits payslip={payslip} />
            <PayslipSalaryBreakdown payslip={payslip} />
            
            {payslip.notes && (
              <div>
                <h3 className="font-semibold mb-2">Notes</h3>
                <p className="text-sm text-muted-foreground p-3 bg-muted rounded-lg">{payslip.notes}</p>
              </div>
            )}

            <PayslipAuditInfo payslip={payslip} />
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
