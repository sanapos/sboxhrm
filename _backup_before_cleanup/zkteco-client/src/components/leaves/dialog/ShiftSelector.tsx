import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Card } from '@/components/ui/card';
import { Clock } from 'lucide-react';
import { Shift } from '@/types/shift';
import { ShiftDisplay } from './ShiftDisplay';
import { LeaveDialogState } from '@/types/leave';

interface ShiftSelectorProps {
  shiftId: string;
  selectedShift?: Shift | { 
    id: string; 
    startTime: string; 
    endTime: string; 
    totalHours: number; 
    description?: string; 
    employeeName: string 
  } | null;
  approvedShifts: Shift[];
  isEditMode: boolean;
  onShiftChange: (state: Partial<LeaveDialogState>) => void;
}

export const ShiftSelector = ({ 
  shiftId, 
  selectedShift, 
  approvedShifts, 
  isEditMode, 
  onShiftChange 
}: ShiftSelectorProps) => (
  <div className="space-y-3">
    <Label htmlFor="shift" className="text-base font-semibold flex items-center gap-2">
      <Clock className="h-4 w-4" />
      Select Shift
    </Label>
    {isEditMode ? (
      <Card className="p-4 bg-accent/50 border-2">
        {selectedShift && <ShiftDisplay shift={selectedShift} />}
      </Card>
    ) : (
      <Select value={shiftId} onValueChange={v => onShiftChange({ shiftId: v })}>
        <SelectTrigger id="shift" className="h-auto">
          <SelectValue placeholder="Choose a shift" />
        </SelectTrigger>
        <SelectContent>
          {approvedShifts.length === 0 ? (
            <div className="p-4 text-sm text-muted-foreground text-center">
              No approved shifts available
            </div>
          ) : (
            approvedShifts.map((shift) => (
              <SelectItem key={shift.id} value={shift.id} className="py-3">
                <ShiftDisplay shift={shift} />
              </SelectItem>
            ))
          )}
        </SelectContent>
      </Select>
    )}
  </div>
);
