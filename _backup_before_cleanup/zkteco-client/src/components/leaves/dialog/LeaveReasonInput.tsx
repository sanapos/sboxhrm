import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { LeaveDialogState } from '@/types/leave';

interface LeaveReasonInputProps {
  reason: string;
  onReasonChange: (state: Partial<LeaveDialogState>) => void;
}

export const LeaveReasonInput = ({ reason, onReasonChange }: LeaveReasonInputProps) => (
  <div className="space-y-3">
    <Label htmlFor="reason" className="text-base font-semibold">
      Reason for Leave <span className="text-destructive">*</span>
    </Label>
    <Textarea
      id="reason"
      value={reason}
      onChange={e => onReasonChange({ reason: e.target.value })}
      placeholder="Please provide a detailed reason for your leave request..."
      className="min-h-[120px] resize-none"
      required
    />
    <p className="text-xs text-muted-foreground">
      Required field - Please explain why you need this leave
    </p>
  </div>
);
