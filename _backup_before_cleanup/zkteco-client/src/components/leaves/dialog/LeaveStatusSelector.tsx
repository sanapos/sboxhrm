import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { CheckCircle } from 'lucide-react';
import { LeaveStatus, getLeaveStatusLabel } from '@/types/leave';

interface LeaveStatusSelectorProps {
  status: LeaveStatus | undefined;
  onStatusChange: (status: LeaveStatus) => void;
}

export const LeaveStatusSelector = ({ status, onStatusChange }: LeaveStatusSelectorProps) => (
  <div className="space-y-3">
    <Label htmlFor="status" className="text-base font-semibold flex items-center gap-2">
      <CheckCircle className="h-4 w-4" />
      Leave Status
    </Label>
    <Select value={status?.toString()} onValueChange={v => onStatusChange(parseInt(v) as LeaveStatus)}>
      <SelectTrigger id="status">
        <SelectValue placeholder="Select status" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={LeaveStatus.PENDING.toString()}>{getLeaveStatusLabel(LeaveStatus.PENDING)}</SelectItem>
        <SelectItem value={LeaveStatus.APPROVED.toString()}>{getLeaveStatusLabel(LeaveStatus.APPROVED)}</SelectItem>
        <SelectItem value={LeaveStatus.REJECTED.toString()}>{getLeaveStatusLabel(LeaveStatus.REJECTED)}</SelectItem>
        <SelectItem value={LeaveStatus.CANCELLED.toString()}>{getLeaveStatusLabel(LeaveStatus.CANCELLED)}</SelectItem>
      </SelectContent>
    </Select>
  </div>
);
