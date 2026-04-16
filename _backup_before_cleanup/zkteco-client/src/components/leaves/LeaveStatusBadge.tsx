import { Badge } from '@/components/ui/badge';
import { LeaveStatus, getLeaveStatusLabel } from '@/types/leave';

interface LeaveStatusBadgeProps {
  status: LeaveStatus;
  rejectionReason?: string;
}

const getStatusColor = (status: LeaveStatus) => {
  switch (status) {
    case LeaveStatus.APPROVED:
      return 'bg-green-500';
    case LeaveStatus.REJECTED:
      return 'bg-red-500';
    case LeaveStatus.CANCELLED:
      return 'bg-gray-500';
    default:
      return 'bg-yellow-500';
  }
};

export const LeaveStatusBadge = ({ status, rejectionReason }: LeaveStatusBadgeProps) => {
  return (
    <div>
      <Badge className={getStatusColor(status)}>
        {getLeaveStatusLabel(status)}
      </Badge>
      {status === LeaveStatus.REJECTED && rejectionReason && (
        <div className="text-xs text-red-500 mt-1">
          {rejectionReason}
        </div>
      )}
    </div>
  );
};
