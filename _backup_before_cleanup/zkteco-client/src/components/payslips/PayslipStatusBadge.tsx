import { Badge } from '@/components/ui/badge';
import { PayslipStatus } from '@/types/payslip';

interface PayslipStatusBadgeProps {
  status: PayslipStatus;
  statusName: string;
}

export function PayslipStatusBadge({ status, statusName }: PayslipStatusBadgeProps) {
  const getStatusColor = (status: PayslipStatus) => {
    switch (status) {
      case PayslipStatus.Draft:
        return 'secondary';
      case PayslipStatus.PendingApproval:
        return 'default';
      case PayslipStatus.Approved:
        return 'default';
      case PayslipStatus.Paid:
        return 'default';
      case PayslipStatus.Cancelled:
        return 'destructive';
      default:
        return 'secondary';
    }
  };

  return (
    <Badge variant={getStatusColor(status)}>
      {statusName}
    </Badge>
  );
}
