import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { FileText } from 'lucide-react';
import { LeaveDialogState, LeaveType } from '@/types/leave';

interface LeaveTypeSelectorProps {
  type: LeaveType;
  onTypeChange: (state: Partial<LeaveDialogState>) => void;
}

export const LeaveTypeSelector = ({ type, onTypeChange }: LeaveTypeSelectorProps) => (
  <div className="space-y-3">
    <Label htmlFor="type" className="text-base font-semibold flex items-center gap-2">
      <FileText className="h-4 w-4" />
      Leave Type
    </Label>
    <Select value={type.toString()} onValueChange={v => onTypeChange({ type: parseInt(v) as LeaveType })}>
      <SelectTrigger id="type">
        <SelectValue placeholder="Select leave type" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={LeaveType.SICK.toString()}>Sick</SelectItem>
        <SelectItem value={LeaveType.VACATION.toString()}>Vacation</SelectItem>
        <SelectItem value={LeaveType.PERSONAL.toString()}>Personal</SelectItem>
        <SelectItem value={LeaveType.OTHER.toString()}>Other</SelectItem>
      </SelectContent>
    </Select>
  </div>
);
