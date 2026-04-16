// ==========================================
// src/contexts/AttendanceCorrectionContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, Dispatch, SetStateAction, useMemo, useCallback } from 'react';
import { 
  AttendanceCorrectionRequest, 
  CreateAttendanceCorrectionRequest, 
  ApproveAttendanceCorrectionRequest 
} from '@/types/hrm';
import { attendanceCorrectionService } from '@/services/hrmService';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { defaultPaginationRequest } from '@/constants/defaultValue';
import { PaginatedResponse, PaginationRequest } from '@/types';

interface AttendanceCorrectionContextValue {
  // State
  paginatedRequests: PaginatedResponse<AttendanceCorrectionRequest>;
  paginatedPendingRequests: PaginatedResponse<AttendanceCorrectionRequest>;
  isLoading: boolean;

  // Pagination
  paginationRequest: PaginationRequest;
  setPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;
  pendingPaginationRequest: PaginationRequest;
  setPendingPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;

  // Dialog states
  selectedRequest: AttendanceCorrectionRequest | null;
  dialogMode: 'create' | 'approve' | 'reject' | 'view' | null;
  setDialogMode: (mode: 'create' | 'approve' | 'reject' | 'view' | null) => void;
  rejectReason: string;
  setRejectReason: (reason: string) => void;

  // Actions
  handleCreate: (data: CreateAttendanceCorrectionRequest) => Promise<void>;
  handleApprove: (id: string) => Promise<void>;
  handleReject: (id: string, reason: string) => Promise<void>;
  handleCancel: (id: string) => Promise<void>;
  handleSelectRequest: (request: AttendanceCorrectionRequest | null) => void;
  handleApproveClick: (request: AttendanceCorrectionRequest) => void;
  handleRejectClick: (request: AttendanceCorrectionRequest) => void;
}

const AttendanceCorrectionContext = createContext<AttendanceCorrectionContextValue | undefined>(undefined);

export const useAttendanceCorrectionContext = () => {
  const context = useContext(AttendanceCorrectionContext);
  if (!context) {
    throw new Error('useAttendanceCorrectionContext must be used within AttendanceCorrectionProvider');
  }
  return context;
};

interface AttendanceCorrectionProviderProps {
  children: ReactNode;
}

export const AttendanceCorrectionProvider = ({ children }: AttendanceCorrectionProviderProps) => {
  const queryClient = useQueryClient();

  // Dialog states
  const [selectedRequest, setSelectedRequest] = useState<AttendanceCorrectionRequest | null>(null);
  const [dialogMode, setDialogMode] = useState<'create' | 'approve' | 'reject' | 'view' | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  // Pagination
  const [paginationRequest, setPaginationRequest] = useState<PaginationRequest>(defaultPaginationRequest);
  const [pendingPaginationRequest, setPendingPaginationRequest] = useState<PaginationRequest>(defaultPaginationRequest);

  // Queries
  const { data: paginatedRequests, isLoading: isAllLoading } = useQuery({
    queryKey: ['attendance-corrections', paginationRequest],
    queryFn: () => attendanceCorrectionService.getAllRequests(paginationRequest),
  });

  const { data: paginatedPendingRequests, isLoading: isPendingLoading } = useQuery({
    queryKey: ['attendance-corrections-pending', pendingPaginationRequest],
    queryFn: () => attendanceCorrectionService.getPendingRequests(pendingPaginationRequest),
  });

  // Mutations
  const createMutation = useMutation({
    mutationFn: attendanceCorrectionService.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['attendance-corrections'] });
      toast.success('Yêu cầu sửa chấm công đã được tạo');
      setDialogMode(null);
    },
    onError: () => {
      toast.error('Không thể tạo yêu cầu');
    },
  });

  const approveMutation = useMutation({
    mutationFn: (data: ApproveAttendanceCorrectionRequest) => attendanceCorrectionService.approve(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['attendance-corrections'] });
      toast.success('Yêu cầu đã được duyệt');
      setDialogMode(null);
      setSelectedRequest(null);
    },
    onError: () => {
      toast.error('Không thể duyệt yêu cầu');
    },
  });

  const cancelMutation = useMutation({
    mutationFn: attendanceCorrectionService.cancel,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['attendance-corrections'] });
      toast.success('Yêu cầu đã được hủy');
    },
    onError: () => {
      toast.error('Không thể hủy yêu cầu');
    },
  });

  // Default empty response
  const emptyPaginatedResponse = useMemo<PaginatedResponse<AttendanceCorrectionRequest>>(() => ({
    items: [],
    totalCount: 0,
    pageNumber: 1,
    pageSize: 10,
    totalPages: 0,
    hasPreviousPage: false,
    hasNextPage: false,
  }), []);

  const isLoading = isAllLoading || isPendingLoading;

  // Handlers
  const handleCreate = async (data: CreateAttendanceCorrectionRequest) => {
    await createMutation.mutateAsync(data);
  };

  const handleApprove = async (id: string) => {
    await approveMutation.mutateAsync({ requestId: id, isApproved: true });
  };

  const handleReject = async (id: string, reason: string) => {
    await approveMutation.mutateAsync({ requestId: id, isApproved: false, rejectReason: reason });
    setRejectReason('');
  };

  const handleCancel = async (id: string) => {
    await cancelMutation.mutateAsync(id);
  };

  const handleSelectRequest = useCallback((request: AttendanceCorrectionRequest | null) => {
    setSelectedRequest(request);
  }, []);

  const handleApproveClick = useCallback((request: AttendanceCorrectionRequest) => {
    setSelectedRequest(request);
    setDialogMode('approve');
  }, []);

  const handleRejectClick = useCallback((request: AttendanceCorrectionRequest) => {
    setSelectedRequest(request);
    setDialogMode('reject');
  }, []);

  const value: AttendanceCorrectionContextValue = {
    paginatedRequests: paginatedRequests || emptyPaginatedResponse,
    paginatedPendingRequests: paginatedPendingRequests || emptyPaginatedResponse,
    isLoading,
    paginationRequest,
    setPaginationRequest,
    pendingPaginationRequest,
    setPendingPaginationRequest,
    selectedRequest,
    dialogMode,
    setDialogMode,
    rejectReason,
    setRejectReason,
    handleCreate,
    handleApprove,
    handleReject,
    handleCancel,
    handleSelectRequest,
    handleApproveClick,
    handleRejectClick,
  };

  return (
    <AttendanceCorrectionContext.Provider value={value}>
      {children}
    </AttendanceCorrectionContext.Provider>
  );
};
