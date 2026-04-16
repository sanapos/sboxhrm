import { useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Shift } from '@/types/shift';
import { formatDateTime } from '@/lib/utils';

interface RejectShiftDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    shift: Shift;
    onSubmit: (reason: string) => void;
}

export const RejectShiftDialog = ({ open, onOpenChange, shift, onSubmit }: RejectShiftDialogProps) => {
    const [rejectionReason, setRejectionReason] = useState('');

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        onSubmit(rejectionReason);
        setRejectionReason('');
    };

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <form onSubmit={handleSubmit}>
                    <DialogHeader>
                        <DialogTitle>Reject Shift Request</DialogTitle>
                        <DialogDescription>
                            Please provide a reason for rejecting this shift request
                        </DialogDescription>
                    </DialogHeader>

                    <div className="space-y-4 py-4">
                        <div className="space-y-3">
                            <div>
                                <span className="font-medium">Employee:</span> {shift.employeeName}
                            </div>
                            <div>
                                <span className="font-medium">Start Time:</span> {formatDateTime(shift.startTime)}
                            </div>
                            <div>
                                <span className="font-medium">End Time:</span> {formatDateTime(shift.endTime)}
                            </div>
                            {shift.description && (
                                <div>
                                    <span className="font-medium">Description:</span> {shift.description}
                                </div>
                            )}
                        </div>

                        <div className="space-y-2">
                            <Label htmlFor="rejectionReason">Rejection Reason *</Label>
                            <Textarea
                                id="rejectionReason"
                                value={rejectionReason}
                                onChange={(e) => setRejectionReason(e.target.value)}
                                placeholder="Explain why this shift request is being rejected..."
                                rows={4}
                                required
                            />
                        </div>
                    </div>

                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                            Cancel
                        </Button>
                        <Button type="submit" variant="destructive">
                            Reject
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
};
