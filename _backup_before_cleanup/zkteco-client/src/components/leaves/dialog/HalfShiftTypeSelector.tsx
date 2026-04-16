import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Clock } from 'lucide-react';
import { LeaveDialogState } from '@/types/leave';

interface HalfShiftTypeSelectorProps {
  halfShiftType: '' | 'first' | 'second';
  onHalfShiftTypeChange: (state: Partial<LeaveDialogState>) => void;
}

export const HalfShiftTypeSelector = ({ halfShiftType, onHalfShiftTypeChange }: HalfShiftTypeSelectorProps) => (
  <div className="space-y-3">
    <Label htmlFor="halfShiftType" className="text-base font-semibold flex items-center gap-2">
      <Clock className="h-4 w-4" />
      Select Half Shift
    </Label>
    <Select value={halfShiftType} onValueChange={v => onHalfShiftTypeChange({ halfShiftType: v as 'first' | 'second' })}>
      <SelectTrigger id="halfShiftType">
        <SelectValue placeholder="Choose half shift" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="first">1st Half</SelectItem>
        <SelectItem value="second">2nd Half</SelectItem>
      </SelectContent>
    </Select>
  </div>
);
