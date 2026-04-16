// ==========================================
// src/hooks/useShifts.ts
// ==========================================
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { shiftService } from '@/services/shiftService';
import { toast } from 'sonner';
import { CreateShiftRequest, UpdateShiftRequest, UpdateShiftTimesRequest, RejectShiftRequest, ShiftStatus, ShiftManagementFilter } from '@/types/shift';
import { PaginationRequest } from '@/types';

// Query hooks
export const useMyShifts = (paginationRequest: PaginationRequest, status?: ShiftStatus, employeeUserId?: string) => {
  return useQuery({
    queryKey: ['shifts', 'my-shifts', paginationRequest, status, employeeUserId],
    queryFn: () => shiftService.getMyShifts(paginationRequest, status, employeeUserId),
  });
};

export const usePendingShifts = (paginationRequest: PaginationRequest) => {
  return useQuery({
    queryKey: ['shifts', 'pending', paginationRequest],
    queryFn: () => shiftService.getPendingShifts(paginationRequest),
  });
};

export const useManagedShifts = (paginationRequest: PaginationRequest, filters: ShiftManagementFilter) => {
  return useQuery({
    queryKey: ['shifts', 'managed', paginationRequest, filters],
    queryFn: () => shiftService.getManagedShifts(paginationRequest, filters),
  });
};

// Mutation hooks
export const useCreateShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateShiftRequest) => shiftService.createShift(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift created successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to create shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useUpdateShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateShiftRequest }) =>
      shiftService.updateShift(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift updated successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to update shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useDeleteShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => shiftService.deleteShift(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift deleted successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to delete shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useApproveShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => shiftService.approveShift(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift approved successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to approve shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useRejectShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RejectShiftRequest }) =>
      shiftService.rejectShift(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift rejected successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to reject shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useUpdateShiftTimes = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateShiftTimesRequest }) =>
      shiftService.updateShiftTimes(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift times updated successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to update shift times', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useAssignShift = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateShiftRequest & { employeeUserId: string }) =>
      shiftService.assignShift(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shifts'] });
      toast.success('Shift assigned successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to assign shift', {
        description: error.message || 'An error occurred',
      });
    },
  });
};
  