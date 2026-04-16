// ==========================================
// src/contexts/AdvanceRequestContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, Dispatch, SetStateAction, useMemo, useCallback } from 'react';
import { AdvanceRequest, CreateAdvanceRequest, ApproveAdvanceRequest } from '@/types/hrm';
import { advanceRequestService } from '@/services/hrmService';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { defaultPaginationRequest } from '@/constants/defaultValue';
import { PaginatedResponse, PaginationRequest } from '@/types';

interface AdvanceRequestContextValue {
  // State
  paginatedRequests: PaginatedResponse<AdvanceRequest>;
  paginatedPendingRequests: PaginatedResponse<AdvanceRequest>;
  isLoading: boolean;

  // Pagination
  paginationRequest: PaginationRequest;
  setPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;
  pendingPaginationRequest: PaginationRequest;
  setPendingPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;

  // Dialog states
  selectedRequest: AdvanceRequest | null;
  dialogMode: 'create' | 'approve' | 'reject' | 'view' | null;
  setDialogMode: (mode: 'create' | 'approve' | 'reject' | 'view' | null) => void;
  rejectReason: string;
  setRejectReason: (reason: string) => void;

  // Actions
  handleCreate: (data: CreateAdvanceRequest) => Promise<void>;
  handleApprove: (id: string) => Promise<void>;
  handleReject: (id: string, reason: string) => Promise<void>;
  handleMarkAsPaid: (id: string) => Promise<void>;
  handleCancel: (id: string) => Promise<void>;
  handleSelectRequest: (request: AdvanceRequest | null) => void;
  handleApproveClick: (request: AdvanceRequest) => void;
  handleRejectClick: (request: AdvanceRequest) => void;
}

const AdvanceRequestContext = createContext<AdvanceRequestContextValue | undefined>(undefined);

export const useAdvanceRequestContext = () => {
  const context = useContext(AdvanceRequestContext);
  if (!context) {
    throw new Error('useAdvanceRequestContext must be used within AdvanceRequestProvider');
  }
  return context;
};

interface AdvanceRequestProviderProps {
  children: ReactNode;
}

export const AdvanceRequestProvider = ({ children }: AdvanceRequestProviderProps) => {
  const queryClient = useQueryClient();

  // Dialog states
  const [selectedRequest, setSelectedRequest] = useState<AdvanceRequest | null>(null);
  const [dialogMode, setDialogMode] = useState<'create' | 'approve' | 'reject' | 'view' | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  // Pagination
  const [paginationRequest, setPaginationRequest] = useState<PaginationRequest>(defaultPaginationRequest);
  const [pendingPaginationRequest, setPendingPaginationRequest] = useState<PaginationRequest>(defaultPaginationRequest);

  // Queries
  const { data: paginatedRequests, isLoading: isAllLoading } = useQuery({
    queryKey: ['advance-requests', paginationRequest],
    queryFn: () => advanceRequestService.getAllRequests(paginationRequest),
  });

  const { data: paginatedPendingRequests, isLoading: isPendingLoading } = useQuery({
    queryKey: ['advance-requests-pending', pendingPaginationRequest],
    queryFn: () => advanceRequestService.getPendingRequests(pendingPaginationRequest),
  });

  // Mutations
  const createMutation = useMutation({
    mutationFn: advanceRequestService.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['advance-requests'] });
      toast.success('Yêu cầu ứng lương đã được tạo');
      setDialogMode(null);
    },
    onError: () => {
      toast.error('Không thể tạo yêu cầu');
    },
  });

  const approveMutation = useMutation({
    mutationFn: (data: ApproveAdvanceRequest) => advanceRequestService.approve(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['advance-requests'] });
      toast.success('Yêu cầu đã được duyệt');
      setDialogMode(null);
      setSelectedRequest(null);
    },
    onError: () => {
      toast.error('Không thể duyệt yêu cầu');
    },
  });

  const markAsPaidMutation = useMutation({
    mutationFn: advanceRequestService.markAsPaid,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['advance-requests'] });
      toast.success('Đã đánh dấu thanh toán');
    },
    onError: () => {
      toast.error('Không thể cập nhật trạng thái');
    },
  });

  const cancelMutation = useMutation({
    mutationFn: advanceRequestService.cancel,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['advance-requests'] });
      toast.success('Yêu cầu đã được hủy');
    },
    onError: () => {
      toast.error('Không thể hủy yêu cầu');
    },
  });

  // Default empty response
  const emptyPaginatedResponse = useMemo<PaginatedResponse<AdvanceRequest>>(() => ({
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
  const handleCreate = async (data: CreateAdvanceRequest) => {
    await createMutation.mutateAsync(data);
  };

  const handleApprove = async (id: string) => {
    await approveMutation.mutateAsync({ requestId: id, isApproved: true });
  };

  const handleReject = async (id: string, reason: string) => {
    await approveMutation.mutateAsync({ requestId: id, isApproved: false, rejectReason: reason });
    setRejectReason('');
  };

  const handleMarkAsPaid = async (id: string) => {
    await markAsPaidMutation.mutateAsync(id);
  };

  const handleCancel = async (id: string) => {
    await cancelMutation.mutateAsync(id);
  };

  const handleSelectRequest = useCallback((request: AdvanceRequest | null) => {
    setSelectedRequest(request);
  }, []);

  const handleApproveClick = useCallback((request: AdvanceRequest) => {
    setSelectedRequest(request);
    setDialogMode('approve');
  }, []);

  const handleRejectClick = useCallback((request: AdvanceRequest) => {
    setSelectedRequest(request);
    setDialogMode('reject');
  }, []);

  const value: AdvanceRequestContextValue = {
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
    handleMarkAsPaid,
    handleCancel,
    handleSelectRequest,
    handleApproveClick,
    handleRejectClick,
  };

  return (
    <AdvanceRequestContext.Provider value={value}>
      {children}
    </AdvanceRequestContext.Provider>
  );
};
