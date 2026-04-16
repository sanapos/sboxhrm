import { Button } from '@/components/ui/button';
import { Trash2, CheckCircle, XCircle, Pencil } from 'lucide-react';
import { LeaveRequest, LeaveStatus } from '@/types/leave';
import { useLeaveContext } from '@/contexts/LeaveContext';
import { useAuth } from '@/contexts/AuthContext';
import { UserRole } from '@/constants/roles';
import { JWT_CLAIMS } from '@/constants/auth';

interface LeaveActionsProps {
  leave: LeaveRequest;
}

export const LeaveActions = ({ leave }: LeaveActionsProps) => {
  const { handleApproveClick, handleRejectClick, handleCancelClick, handleEditClick } = useLeaveContext();
  const { user } = useAuth();
  const isManager = user?.[JWT_CLAIMS.ROLE] === UserRole.MANAGER;

  // For managers: show approve/reject for pending leaves, edit for all
  // For users: show edit for pending, cancel for pending
  const canEdit = isManager || leave.status === LeaveStatus.PENDING;
  const isPending = leave.status === LeaveStatus.PENDING;

  return (
    <div className="flex items-center justify-end gap-2">
      {isManager && isPending && (
        <>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => handleApproveClick(leave)}
            className="text-green-600 hover:text-green-700 hover:bg-green-50"
            title="Approve"
          >
            <CheckCircle className="h-4 w-4 mr-1" />
            Approve
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => handleRejectClick(leave)}
            className="text-red-600 hover:text-red-700 hover:bg-red-50"
            title="Reject"
          >
            <XCircle className="h-4 w-4 mr-1" />
            Reject
          </Button>
        </>
      )}
      
      {canEdit && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => handleEditClick(leave)}
          className="text-blue-600 hover:text-blue-700 hover:bg-blue-50"
          title="Edit"
        >
          <Pencil className="h-4 w-4 mr-1" />
          Edit
        </Button>
      )}
      
      {!isManager && isPending && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => handleCancelClick(leave)}
          className="text-red-600 hover:text-red-700 hover:bg-red-50"
          title="Cancel Request"
        >
          <Trash2 className="h-4 w-4 mr-1" />
          Cancel
        </Button>
      )}
    </div>
  );
};
