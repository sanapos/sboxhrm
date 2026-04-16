import { useState, useEffect } from 'react';
import { defaultLeaveDialogState } from '@/constants/defaultValue';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { LeaveDialogState } from '@/types/leave';
import { differenceInHours } from 'date-fns';
import { useMyShifts } from '@/hooks/useShifts';
import { ShiftStatus } from '@/types/shift';
import { Calendar } from 'lucide-react';
import { useLeaveContext } from '@/contexts/LeaveContext';
import { useAuth } from '@/contexts/AuthContext';
import { useEmployeesByManager } from '@/hooks/useAccount';
import { ShiftDetailsCard } from '@/components/leaves/dialog/ShiftDetailsCard';
import { DurationDisplay } from '@/components/leaves/dialog/DurationDisplay';
import { EmployeeSelector } from '@/components/leaves/dialog/EmployeeSelector';
import { ShiftSelector } from '@/components/leaves/dialog/ShiftSelector';
import { LeaveTypeSelector } from '@/components/leaves/dialog/LeaveTypeSelector';
import { LeaveStatusSelector } from '@/components/leaves/dialog/LeaveStatusSelector';
import { HalfShiftToggle } from '@/components/leaves/dialog/HalfShiftToggle';
import { HalfShiftTypeSelector } from '@/components/leaves/dialog/HalfShiftTypeSelector';
import { LeaveReasonInput } from '@/components/leaves/dialog/LeaveReasonInput';

// Calculate half shift type from dates
const calculateHalfShiftType = (start: Date, end: Date, isHalf: boolean): 'first' | 'second' | '' => {
  if (!isHalf) return '';
  const dayStart = new Date(start);
  dayStart.setHours(0, 0, 0, 0);
  const timeFromDayStart = start.getTime() - dayStart.getTime();
  const totalDuration = end.getTime() - start.getTime();
  return timeFromDayStart < totalDuration / 2 ? 'first' : 'second';
};

export const LeaveRequestDialog = () => {
  const [dialogState, setDialogState] = useState<LeaveDialogState>({ ...defaultLeaveDialogState });
  const { 
    selectedLeave,
    dialogMode,
    setDialogMode,
    handleAddOrUpdate
  } = useLeaveContext();
  
  const { 
    isManager
  } = useAuth();
  
  const { 
    employeeUserId, 
    shiftId, 
    type, 
    isHalfShift, 
    halfShiftType, 
    startDate, 
    endDate, 
    reason 
  } = dialogState;

  const { data: pagedApprovedShifts } = useMyShifts(
    {
      pageNumber: 1,
      pageSize: 1000,
      sortOrder: 'desc',
      sortBy: 'StartTime',
    },
    ShiftStatus.Approved, 
    isManager && employeeUserId ? employeeUserId : undefined
  );

  const { data: employees = [] } = useEmployeesByManager();
  const [isSubmitting, setIsSubmitting] = useState(false);

  const isEditMode = dialogMode == 'edit' && selectedLeave !== null;

  // Determine selected shift based on mode
  const selectedShift = isEditMode ? selectedLeave?.shift : pagedApprovedShifts?.items.find(s => s.id === shiftId);

  // Handler to close dialog
  const handleClose = () => {
    setDialogMode(null);
    setDialogState({ ...defaultLeaveDialogState });
  };

  // Initialize dialog state when editing
  useEffect(() => {
    if (isEditMode && selectedLeave) {
      const leaveStartDate = new Date(selectedLeave.startDate);
      const leaveEndDate = new Date(selectedLeave.endDate);
      
      setDialogState({
        employeeUserId: selectedLeave.employeeUserId,
        shiftId: selectedLeave.shiftId,
        type: selectedLeave.type,
        isHalfShift: selectedLeave.isHalfShift,
        halfShiftType: calculateHalfShiftType(leaveStartDate, leaveEndDate, selectedLeave.isHalfShift),
        startDate: leaveStartDate,
        endDate: leaveEndDate,
        reason: selectedLeave.reason,
        status: selectedLeave.status,
      });
    } else if (!isEditMode) {
      setDialogState({ ...defaultLeaveDialogState });
    }
  }, [isEditMode, selectedLeave]);

  // Reset shift when employee changes
  useEffect(() => {
    if (!isEditMode && employeeUserId) {
      setDialogState((prev) => ({
        ...prev,
        shiftId: '',
        startDate: undefined,
        endDate: undefined,
      }));
    }
  }, [employeeUserId, isEditMode]);

  // Auto-fill dates when shift is selected or when toggling half shift
  useEffect(() => {
    if (!selectedShift || isEditMode) return;

    const shiftStart = new Date(selectedShift.startTime);
    const shiftEnd = new Date(selectedShift.endTime);

    if (!isHalfShift) {
      setDialogState((prev: LeaveDialogState) => ({ 
        ...prev, 
        startDate: shiftStart, 
        endDate: shiftEnd 
      }));
      return;
    }

    const midTime = new Date(shiftStart.getTime() + (shiftEnd.getTime() - shiftStart.getTime()) / 2);
    
    const dates = halfShiftType === 'first' 
      ? { startDate: shiftStart, endDate: midTime }
      : halfShiftType === 'second'
      ? { startDate: midTime, endDate: shiftEnd }
      : { startDate: undefined, endDate: undefined };

    setDialogState((prev: LeaveDialogState) => ({ ...prev, ...dates }));
  }, [selectedShift?.id, isHalfShift, halfShiftType, isEditMode]);
  
  const duration = startDate && endDate ? differenceInHours(endDate, startDate) : 0;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validation
    if (!selectedShift || !startDate || !endDate) return;
    if (isManager && !employeeUserId && !isEditMode) return;

    setIsSubmitting(true);
    try {
      await handleAddOrUpdate(dialogState, selectedLeave?.id);
      handleClose();
    } catch (error) {
      console.error('Failed to submit leave request:', error);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleHalfShiftToggle = (checked: boolean) => {
    const updates: Partial<LeaveDialogState> = {
      isHalfShift: checked,
      halfShiftType: '',
    };

    if (!checked && selectedShift) {
      updates.startDate = new Date(selectedShift.startTime);
      updates.endDate = new Date(selectedShift.endTime);
    }

    setDialogState((prev) => ({ ...prev, ...updates }));
  };

  const updateDialogState = (updates: Partial<LeaveDialogState>) => {
    setDialogState((prev) => ({ ...prev, ...updates }));
  };

  return (
    <Dialog open={dialogMode !== null} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-[600px] max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-xl">
            <Calendar className="h-5 w-5" />
            {isEditMode ? 'Edit Leave Request: ' + selectedShift?.employeeName : 'Request Leave'}
          </DialogTitle>
          <DialogDescription>
            {isEditMode 
              ? "Update the leave request details."
              : isManager 
                ? "Create a leave request for an employee." 
                : "Submit a leave request for your approved shift."}
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-6 mt-4">
          {/* Employee Selection (Manager only, disabled in edit mode) */}
          {isManager && !isEditMode && (
            <EmployeeSelector
              employeeUserId={employeeUserId ?? ""}
              employees={employees}
              onEmployeeChange={updateDialogState}
            />
          )}

          {/* Shift Selection */}
          <ShiftSelector
            shiftId={shiftId}
            selectedShift={selectedShift}
            approvedShifts={pagedApprovedShifts?.items || []}
            isEditMode={isEditMode}
            onShiftChange={updateDialogState}
          />

          {selectedShift && <ShiftDetailsCard shift={selectedShift} />}

          {/* Leave Type */}
          <LeaveTypeSelector type={type} onTypeChange={updateDialogState} />

          {/* Leave Status (Manager only) */}
          {isManager && (
            <LeaveStatusSelector status={selectedLeave?.status} onStatusChange={value => updateDialogState({ status: value })} />
          )}

          {/* Half Shift Toggle */}
          <HalfShiftToggle isHalfShift={isHalfShift} onToggle={handleHalfShiftToggle} />

          {/* Half Shift Type Select */}
          {isHalfShift && selectedShift && (
            <HalfShiftTypeSelector
              halfShiftType={halfShiftType}
              onHalfShiftTypeChange={updateDialogState}
            />
          )}

          {/* Duration Display */}
          {duration > 0 && (
            <DurationDisplay 
              duration={duration} 
              isHalfShift={isHalfShift} 
              totalHours={selectedShift?.totalHours} 
            />
          )}

          {/* Reason */}
          <LeaveReasonInput reason={reason} onReasonChange={updateDialogState} />

          <DialogFooter className="gap-3 pt-4">
            <Button type="button" variant="outline" onClick={handleClose} className="min-w-[100px]">
              Cancel
            </Button>
            <Button 
              type="submit" 
              disabled={
                isSubmitting || 
                !shiftId || 
                !reason.trim() || 
                (isManager && !isEditMode && !employeeUserId)
              }
              className="min-w-[140px]"
            >
              {isSubmitting ? 'Submitting...' : isEditMode ? 'Update Request' : 'Submit Request'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
