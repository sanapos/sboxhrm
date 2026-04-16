import { LeaveRequest, getLeaveTypeLabel } from '@/types/leave';
import { PaginationTable } from '../PaginationTable';
import { ColumnDef } from '@tanstack/react-table';
import { format } from 'date-fns';
import { ShowingDateTimeFormat } from '@/constants';
import { Badge } from '@/components/ui/badge';
import { formatDateTime } from '@/lib/utils';
import { LeaveStatusBadge } from './LeaveStatusBadge';
import { LeaveActions } from './LeaveActions';
import { PaginatedResponse, PaginationRequest } from '@/types';

interface LeavesTableProps {
  paginationRequest: PaginationRequest;
  paginatedLeaves: PaginatedResponse<LeaveRequest>;
  isLoading: boolean;
  showActions?: boolean;
  onPaginationChange: (pageNumber: number, pageSize: number) => void;
  onSortingChange: (sorting: any) => void;
}

export const LeavesTable = ({ 
  paginationRequest,
  paginatedLeaves, 
  isLoading, 
  showActions = true,
  onPaginationChange,
  onSortingChange
}: LeavesTableProps) => {
  const columns: ColumnDef<LeaveRequest>[] = [
    {
      accessorKey: 'employeeName',
      header: 'Employee',
    },
    {
      accessorKey: 'type',
      header: 'Type',
      cell: ({ row }) => getLeaveTypeLabel(row.getValue('type')),
    },
    {
      accessorKey: 'startDate',
      header: 'Start Date',
      cell: ({ row }) => formatDateTime(row.getValue('startDate')),
    },
    {
      accessorKey: 'endDate',
      header: 'End Date',
      cell: ({ row }) => formatDateTime(row.getValue('endDate')),
    },
    {
      accessorKey: 'isHalfShift',
      header: 'Duration',
      cell: ({ row }) => (
        <Badge variant="outline">
          {row.getValue('isHalfShift') ? 'Half shift' : 'Full shift'}
        </Badge>
      ),
    },
    {
      accessorKey: 'reason',
      header: 'Reason',
      cell: ({ row }) => (
        <span className="max-w-[200px] truncate block" title={row.getValue('reason')}>
          {row.getValue('reason')}
        </span>
      ),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => (
        <LeaveStatusBadge 
          status={row.getValue('status')} 
          rejectionReason={row.original.rejectionReason} 
        />
      ),
    },
    {
      accessorKey: 'createdAt',
      header: 'Created At',
      cell: ({ row }) => format(row.getValue('createdAt'), ShowingDateTimeFormat),
    },
    ...(showActions ? [{
      id: 'actions',
      header: 'Actions',
      cell: ({ row }: { row: any }) => (
        <LeaveActions leave={row.original} />
      ),
    }] : []),
  ];

  return (
    <PaginationTable<LeaveRequest>
      columns={columns}
      data={paginatedLeaves.items}
      totalCount={paginatedLeaves.totalCount}
      pageNumber={paginatedLeaves.pageNumber}
      pageSize={paginatedLeaves.pageSize}
      isLoading={isLoading}
      onPaginationChange={onPaginationChange} 
      paginationRequest={paginationRequest}
      onSortingChange={onSortingChange}
    />
  );
};
