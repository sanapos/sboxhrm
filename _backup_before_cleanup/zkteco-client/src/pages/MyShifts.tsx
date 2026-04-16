import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { ShiftTable } from '@/components/shifts/ShiftTable';
import { ShiftRequestDialog } from '@/components/dialogs/ShiftRequestDialog';
import { ShiftProvider, useShiftContext } from '@/contexts/ShiftContext';
import { useCallback } from 'react';
import { useAuth } from "@/contexts/AuthContext";

const MyShiftsContent = () => {
    const { 
        paginatedShifts,
        paginationRequest,
        isLoading, 
        setDialogMode,
        handleEdit,
        handleDelete,
        setPaginationRequest
    } = useShiftContext();
    
    const onPaginationChange = useCallback((pageNumber: number, pageSize: number) => {
        setPaginationRequest(prev => ({
            ...prev,
            pageNumber: pageNumber,
            pageSize: pageSize
        }));
    }, [setPaginationRequest]);

    const onSortingChange = useCallback((sorting: any) => {
        setPaginationRequest(prev => ({
            ...prev,
            sortBy: sorting.length > 0 ? sorting[0].id : undefined,
            sortOrder: sorting.length > 0 ? (sorting[0].desc ? 'desc' : 'asc') : undefined,
            pageNumber: 1, // Reset to first page when sorting changes
        }));
    }, [setPaginationRequest]);

    const onFiltersChange = useCallback((filters: any) => {
        // Implement filters change logic if needed
        console.log("Filters changed:", filters);
    }, []); 
    const {
        isHourlyEmployee
    } = useAuth();  

    return (
        <div>
            <PageHeader
                title="My Shifts"
                description="Manage your shift schedules"
                action={
                    isHourlyEmployee && (
                        <Button onClick={() => setDialogMode('create')}>
                            <Plus className="w-4 h-4 mr-2" />
                            Request Shift
                        </Button>
                    )
                }
            />
             <div className="mt-6">
                <ShiftTable
                    paginatedShifts={paginatedShifts}
                    paginationRequest={paginationRequest}
                    isLoading={isLoading}
                    showEmployeeInfo={false}
                    showActions={true}
                    onEdit={handleEdit}
                    onDelete={handleDelete}
                    onPaginationChange={onPaginationChange}
                    onSortingChange={onSortingChange}
                    onFiltersChange={onFiltersChange}
                />
            </div>
            
            <ShiftRequestDialog />
        </div>
    );
};

export const MyShifts = () => {
    return (
        <ShiftProvider>
            <MyShiftsContent />
        </ShiftProvider>
    );
};
