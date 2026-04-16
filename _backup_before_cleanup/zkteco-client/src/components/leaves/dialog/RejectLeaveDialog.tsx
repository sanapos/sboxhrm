import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { XCircle } from 'lucide-react';

interface RejectLeaveDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const RejectLeaveDialog = ({
  open,
  onOpenChange,
}: RejectLeaveDialogProps) => {
  const [reason, setReason] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) return;

    setIsSubmitting(true);
    try {
      setReason('');
    } catch (error) {
      console.error(error);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClose = () => {
    setReason('');
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-xl text-destructive">
            <XCircle className="h-5 w-5" />
            Reject Leave Request
          </DialogTitle>
          <DialogDescription>
            Please provide a reason for rejecting this leave request.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-3">
            <Label htmlFor="reason" className="text-base font-semibold">
              Rejection Reason <span className="text-destructive">*</span>
            </Label>
            <Textarea
              id="reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Please explain why this leave request is being rejected..."
              className="min-h-[120px] resize-none"
              required
            />
            <p className="text-xs text-muted-foreground">
              This reason will be shared with the employee
            </p>
          </div>

          <DialogFooter className="gap-3">
            <Button type="button" variant="outline" onClick={handleClose}>
              Cancel
            </Button>
            <Button 
              type="submit" 
              variant="destructive"
              disabled={isSubmitting || !reason.trim()}
            >
              {isSubmitting ? 'Rejecting...' : 'Reject Leave'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
