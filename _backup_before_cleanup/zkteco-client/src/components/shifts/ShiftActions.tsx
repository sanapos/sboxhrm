import { Shift, ShiftStatus } from '@/types/shift';
import { Button } from '@/components/ui/button';
import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
    AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { CheckCircle, XCircle, Trash2, Pencil } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';

interface ShiftActionsProps {
    shift: Shift;
    onApprove?: (shift: Shift) => void;
    onReject?: (shift: Shift) => void;
    onEdit?: (shift: Shift) => void;
    onDelete?: (id: string) => void;
}

export const ShiftActions = ({
    shift,
    onApprove,
    onReject,
    onDelete,
    onEdit
}: ShiftActionsProps) => {
    const isPending = shift.status === ShiftStatus.Pending;
    const { isManager } = useAuth()
    
    return (
        <div className="flex justify-end gap-2">
            {/* Edit button - show for all shifts if onEdit callback is provided */}
            {isManager && onEdit && (
                <Button
                    size="sm"
                    variant="outline"
                    onClick={() => onEdit(shift)}
                >
                    <Pencil className="w-4 h-4 mr-1" />
                    Edit Times
                </Button>
            )}
            
            {isPending && onApprove && onReject && (
                <>
                    <Button
                        size="sm"
                        variant="outline"
                        className="text-green-600 hover:text-green-700"
                        onClick={() => onApprove(shift)}
                    >
                        <CheckCircle className="w-4 h-4 mr-1" />
                        Approve
                    </Button>
                    <Button
                        size="sm"
                        variant="outline"
                        className="text-red-600 hover:text-red-700"
                        onClick={() => onReject(shift)}
                    >
                        <XCircle className="w-4 h-4 mr-1" />
                        Reject
                    </Button>
                </>
            )}
            {isPending && onDelete && (
                <AlertDialog>
                    <AlertDialogTrigger asChild>
                        <Button
                            size="sm"
                            variant="destructive"
                        >
                            <Trash2 className="w-4 h-4 mr-1" />
                            Delete
                        </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                        <AlertDialogHeader>
                            <AlertDialogTitle>Delete Shift</AlertDialogTitle>
                            <AlertDialogDescription>
                                Are you sure you want to delete this shift? This action cannot be undone.
                            </AlertDialogDescription>
                        </AlertDialogHeader>
                        <AlertDialogFooter>
                            <AlertDialogCancel>Cancel</AlertDialogCancel>
                            <AlertDialogAction
                                onClick={() => onDelete(shift.id)}
                                className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                            >
                                Delete
                            </AlertDialogAction>
                        </AlertDialogFooter>
                    </AlertDialogContent>
                </AlertDialog>
            )}
        </div>
    );
};
