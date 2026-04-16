// ==========================================
// src/contexts/LeaveContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, Dispatch, SetStateAction, useMemo } from 'react';
import { LeaveRequest, CreateLeaveRequest, UpdateLeaveRequest, LeaveDialogState } from '@/types/leave';
import { 
  usePendingLeaves, 
  useAllLeaves, 
  useApproveLeave, 
  useRejectLeave,
  useCreateLeave,
  useUpdateLeave,
  useCancelLeave,
} from '@/hooks/useLeaves';
import { format } from 'date-fns';
import { DateTimeFormat } from '@/constants';
import { defaultPaginationRequest } from '@/constants/defaultValue';
import { PaginatedResponse, PaginationRequest } from '@/types';

interface LeaveContextValue {
  // State
  paginatedPendingLeaves: PaginatedResponse<LeaveRequest>;
  paginatedLeaves: PaginatedResponse<LeaveRequest>;
  isLoading: boolean;
  
  // Dialog states
  approveDialogOpen: boolean;
  rejectDialogOpen: boolean;
  cancelDialogOpen: boolean;
  createDialogOpen: boolean;
  selectedLeave: LeaveRequest | null;
  rejectionReason: string;
  
  paginationRequest: PaginationRequest
  setPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;
  pendingPaginationRequest: PaginationRequest;
  setPendingPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;

  // Actions
  setApproveDialogOpen: (open: boolean) => void;
  setRejectDialogOpen: (open: boolean) => void;
  setCancelDialogOpen: (open: boolean) => void;
  setCreateDialogOpen: (open: boolean) => void;
  setRejectionReason: (reason: string) => void;
  handleApprove: (id: string) => Promise<void>;
  handleReject: (id: string, rejectionReason: string) => Promise<void>;
  handleCancel: (id: string) => Promise<void>;
  handleCreate: (data: CreateLeaveRequest) => Promise<void>;
  handleUpdate: (id: string, data: UpdateLeaveRequest) => Promise<void>;
  handleApproveClick: (leave: LeaveRequest) => void;
  handleRejectClick: (leave: LeaveRequest) => void;
  handleCancelClick: (leave: LeaveRequest) => void;
  handleEditClick: (leave: LeaveRequest) => void;

  handleAddOrUpdate: (data: CreateLeaveRequest | UpdateLeaveRequest | LeaveDialogState, id?: string) => Promise<void>;

  dialogMode: 'create' | 'edit' | null;
  setDialogMode: (mode: 'create' | 'edit' | null) => void;
}

const LeaveContext = createContext<LeaveContextValue | undefined>(undefined);

export const useLeaveContext = () => {
  const context = useContext(LeaveContext);
  if (!context) {
    throw new Error('useLeaveContext must be used within LeaveProvider');
  }
  return context;
};

interface LeaveProviderProps {
  children: ReactNode;
}

export const LeaveProvider = ({ children }: LeaveProviderProps) => {
  // Dialog states
  const [approveDialogOpen, setApproveDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [selectedLeave, setSelectedLeave] = useState<LeaveRequest | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');

  const [dialogMode, setDialogMode] = useState<'create' | 'edit' | null>(null);

  const [paginationRequest, setPaginationRequest] = useState(defaultPaginationRequest)
  const [pendingPaginationRequest, setPendingPaginationRequest] = useState(defaultPaginationRequest);
  
  // Hooks
  const { data: paginatedPendingLeaves, isLoading: isPendingLoading } = usePendingLeaves(pendingPaginationRequest);
  const { data: paginatedLeaves, isLoading: isAllLoading } = useAllLeaves(paginationRequest);

  const approveLeaveMutation = useApproveLeave();
  const rejectLeaveMutation = useRejectLeave();
  const cancelLeaveMutation = useCancelLeave();
  const createLeaveMutation = useCreateLeave();
  const updateLeaveMutation = useUpdateLeave();
  
  const isLoading = isPendingLoading || isAllLoading;

    // Memoize the default empty paginated response
  const emptyPaginatedResponse = useMemo<PaginatedResponse<LeaveRequest>>(() => ({ 
    items: [], 
    totalCount: 0, 
    pageNumber: 1, 
    pageSize: 10, 
    totalPages: 0,
    hasPreviousPage: false,
    hasNextPage: false
  }), []);
  
  const handleApprove = async (id: string) => {
    await approveLeaveMutation.mutateAsync(id);
    setApproveDialogOpen(false);
    setSelectedLeave(null);
  };

  const handleReject = async (id: string, rejectionReason: string) => {
    await rejectLeaveMutation.mutateAsync({ id, data: { reason: rejectionReason } });
    setRejectDialogOpen(false);
    setSelectedLeave(null);
    setRejectionReason('');
  };

  const handleCancel = async (id: string) => {
    await cancelLeaveMutation.mutateAsync(id);
    setCancelDialogOpen(false);
    setSelectedLeave(null);
  };

  const handleCreate = async (data: CreateLeaveRequest) => {
    await createLeaveMutation.mutateAsync(data);
    setCreateDialogOpen(false);
  };

  const handleUpdate = async (id: string, data: UpdateLeaveRequest) => {
    await updateLeaveMutation.mutateAsync({ id, data });
    setDialogMode(null);
    setSelectedLeave(null);
  };

  const handleApproveClick = (leave: LeaveRequest) => {
    setSelectedLeave(leave);
    setApproveDialogOpen(true);
  };

  const handleRejectClick = (leave: LeaveRequest) => {
    setSelectedLeave(leave);
    setRejectDialogOpen(true);
  };

  const handleCancelClick = (leave: LeaveRequest) => {
    setSelectedLeave(leave);
    setCancelDialogOpen(true);
  };

  const handleEditClick = (leave: LeaveRequest) => {
    setDialogMode('edit');
    setSelectedLeave(leave);
    setDialogMode('edit');
  };

  const handleAddOrUpdate = async (data: CreateLeaveRequest | UpdateLeaveRequest | LeaveDialogState, id?: string) => {
    data.startDate = format(data.startDate as Date, DateTimeFormat);
    data.endDate = format(data.endDate as Date, DateTimeFormat);

    if( dialogMode === 'create') {
      await handleCreate(data as CreateLeaveRequest);
    } else if (dialogMode === 'edit' && id) {
      await handleUpdate(id, data as UpdateLeaveRequest);
    }
  }

  const value: LeaveContextValue = {
    // State
    paginatedPendingLeaves: paginatedPendingLeaves || emptyPaginatedResponse,
    paginatedLeaves: paginatedLeaves || emptyPaginatedResponse,
    isLoading,
    dialogMode,
    setDialogMode,

    paginationRequest,
    setPaginationRequest,
    pendingPaginationRequest,
    setPendingPaginationRequest,
    // Dialog states
    approveDialogOpen,
    rejectDialogOpen,
    cancelDialogOpen,
    createDialogOpen,
    selectedLeave,
    rejectionReason,
    
    // Actions
    setApproveDialogOpen,
    setRejectDialogOpen,
    setCancelDialogOpen,
    setCreateDialogOpen,
    setRejectionReason,
    handleApprove,
    handleReject,
    handleCancel,
    handleCreate,
    handleUpdate,
    handleApproveClick,
    handleRejectClick,
    handleCancelClick,
    handleEditClick,
    handleAddOrUpdate
  };

  return (
    <LeaveContext.Provider value={value}>
      {children}
    </LeaveContext.Provider>
  );
};
