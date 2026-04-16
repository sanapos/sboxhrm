import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Shift } from '@/types/shift';
import { formatDateTime } from '@/lib/utils';

interface ApproveShiftDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    shift: Shift;
    onConfirm: () => void;
}

export const ApproveShiftDialog = ({ open, onOpenChange, shift, onConfirm }: ApproveShiftDialogProps) => {
    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Approve Shift Request</DialogTitle>
                    <DialogDescription>
                        Are you sure you want to approve this shift request?
                    </DialogDescription>
                </DialogHeader>

                <div className="space-y-3 py-4">
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

                <DialogFooter>
                    <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                        Cancel
                    </Button>
                    <Button type="button" onClick={onConfirm} className="bg-green-600 hover:bg-green-700">
                        Approve
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};
