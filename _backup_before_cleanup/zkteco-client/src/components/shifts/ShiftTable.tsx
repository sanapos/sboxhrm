import { Shift } from '@/types/shift';
import { PaginationTable } from '../PaginationTable';
import { ColumnDef } from '@tanstack/react-table';
import { format } from 'date-fns';
import { ShowingDateTimeFormat } from '@/constants';
import { StatusBadge } from './StatusBadge';
import { ShiftActions } from './ShiftActions';
import { PaginatedResponse, PaginationRequest } from '@/types';
import { SortingHeader } from '../SortingHeader';

interface ShiftTableProps {
    paginatedShifts: PaginatedResponse<Shift>;
    paginationRequest: PaginationRequest;
    isLoading: boolean;
    onApprove?: (shift: Shift) => void;
    onReject?: (shift: Shift) => void;
    showEmployeeInfo?: boolean;
    showActions?: boolean;
    onEdit?: (shift: Shift) => void;
    onDelete?: (id: string) => void;
    pageCount?: number;
    totalRows?: number;
    onPaginationChange: (pageNumber: number, pageSize: number) => void;
    onSortingChange?: (sorting: any) => void;
    onFiltersChange?: (filters: any) => void;
}

export const ShiftTable = ({
    isLoading,
    onApprove,
    onReject,
    showEmployeeInfo = false,
    showActions = true,
    onEdit,
    onDelete,
    paginatedShifts,
    paginationRequest,
    onPaginationChange,
    onSortingChange,
    onFiltersChange
}: ShiftTableProps) => {
    const columns : ColumnDef<Shift>[] = [
        ...(showEmployeeInfo ? [
            { 
                accessorKey: 'employeeName', 
                header: ({ column }: any) => <SortingHeader column={column} title="Employee" />,
                enableSorting: true
            }] : []),
        { 
            accessorKey: 'startTime', 
            header: ({ column }) => <SortingHeader column={column} title="Start Time" />,
            cell: ({ row }) => format(new Date(row.getValue('startTime')), ShowingDateTimeFormat),
            enableSorting: true,
            sortDescFirst: true
        },
        { 
            accessorKey: 'endTime', 
            header: ({ column }) => <SortingHeader column={column} title="End Time" />,
            cell: ({ row }) => format(new Date(row.getValue('endTime')), ShowingDateTimeFormat),
            enableSorting: true,
        },
        {
            accessorKey: 'checkInTime',
            header: 'Check-In',
            cell: ({ row }) => {
                const checkInTime = row.getValue('checkInTime') as string | undefined;
                return checkInTime ? format(new Date(checkInTime), ShowingDateTimeFormat) : '-';
            },
            enableSorting: true,
        },
        {
            accessorKey: 'checkOutTime',
            header: "Check-Out",
            cell: ({ row }) => {
                const checkOutTime = row.getValue('checkOutTime') as string | undefined;
                return checkOutTime ? format(new Date(checkOutTime), ShowingDateTimeFormat) : '-    ';
            },
            enableSorting: true,    
        },
        { 
            accessorKey: 'totalHours', 
            header: 'Total Hours'
        },
        { 
            accessorKey: 'description', 
            header: 'Description'
        },  
        { 
            accessorKey: 'status', 
            header: ({ column }) => <SortingHeader column={column} title="Status" />,
            cell: ({ row }) => {
                const status = row.getValue('status') as Shift['status'];
                return <StatusBadge status={status} rejectionReason={row.original.rejectionReason} />
            },
            enableSorting: true,
        },
        { 
            accessorKey: 'createdAt', 
            header: ({ column }) => <SortingHeader column={column} title="Submitted" />,
            cell: ({ row }) => format(new Date(row.getValue('createdAt')), ShowingDateTimeFormat),
            enableSorting: true,
        },
        ...(showActions ? [{ 
            id: 'actions', 
            header: 'Actions', 
            cell: ({ row }: { row: any }) => (
                <ShiftActions
                    shift={row.original}
                    onApprove={onApprove}
                    onReject={onReject}
                    onEdit={onEdit}
                    onDelete={onDelete}
                />
            ),
            enableSorting: false,
        }] : []),
    ]

    return (
        <PaginationTable<Shift>
            columns={columns}
            data={paginatedShifts.items}
            paginationRequest={paginationRequest}
            totalCount={paginatedShifts.totalCount}
            pageNumber={paginatedShifts.pageNumber}
            pageSize={paginatedShifts.pageSize}
            isLoading={isLoading}
            onPaginationChange={onPaginationChange}
            onSortingChange={onSortingChange}
            onFiltersChange={onFiltersChange}
            manualSorting={true}
            manualFiltering={true}
            containerHeight={"calc(100vh - 320px)"}
        />
    );
};
