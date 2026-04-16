import { Payslip } from '@/types/payslip';

interface PayslipWorkUnitsProps {
  payslip: Payslip;
}

export function PayslipWorkUnits({ payslip }: PayslipWorkUnitsProps) {
  return (
    <div>
      <h3 className="font-semibold mb-3">Work Units</h3>
      <div className="grid grid-cols-2 gap-3">
        <div className="p-3 border rounded-lg">
          <div className="text-sm text-muted-foreground">Regular Work</div>
          <div className="text-lg font-semibold">{payslip.regularWorkUnits.toFixed(2)}</div>
        </div>
        {payslip.overtimeUnits && payslip.overtimeUnits > 0 && (
          <div className="p-3 border rounded-lg">
            <div className="text-sm text-muted-foreground">Overtime</div>
            <div className="text-lg font-semibold">{payslip.overtimeUnits.toFixed(2)}</div>
          </div>
        )}
        {payslip.holidayUnits && payslip.holidayUnits > 0 && (
          <div className="p-3 border rounded-lg">
            <div className="text-sm text-muted-foreground">Holiday</div>
            <div className="text-lg font-semibold">{payslip.holidayUnits.toFixed(2)}</div>
          </div>
        )}
        {payslip.nightShiftUnits && payslip.nightShiftUnits > 0 && (
          <div className="p-3 border rounded-lg">
            <div className="text-sm text-muted-foreground">Night Shift</div>
            <div className="text-lg font-semibold">{payslip.nightShiftUnits.toFixed(2)}</div>
          </div>
        )}
      </div>
    </div>
  );
}
