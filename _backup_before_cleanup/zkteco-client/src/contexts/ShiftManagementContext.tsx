// ==========================================
// src/contexts/ShiftManagementContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, Dispatch } from 'react';
import { CreateShiftRequest, Shift, ShiftTemplate, UpdateShiftTemplateRequest, CreateShiftTemplateRequest, ShiftManagementFilter } from '@/types/shift';
import { 
  usePendingShifts, 
  useManagedShifts, 
  useApproveShift, 
  useRejectShift,
  useCreateShift,
} from '@/hooks/useShifts';
import {
  useShiftTemplates,
  useCreateShiftTemplate,
  useUpdateShiftTemplate,
  useDeleteShiftTemplate
} from '@/hooks/useShiftTemplate';
import { PaginatedResponse, PaginationRequest } from '@/types';
import { defaultShiftManagementFilter, defaultShiftPaginationRequest } from '@/constants/defaultValue';
import { useEmployeesByManager } from '@/hooks/useAccount';

interface ShiftManagementContextValue {
  // State
  pendingPaginationRequest: PaginationRequest;
  allPaginationRequest: PaginationRequest;
  pendingPaginatedShifts: PaginatedResponse<Shift> | undefined;
  allPaginatedShifts: PaginatedResponse<Shift> | undefined;
  templates: ShiftTemplate[];
  isLoading: boolean;
  employees: Array<{ id: string; firstName: string; lastName: string; email: string }>;
  filters: ShiftManagementFilter;

  setPendingPaginationRequest: Dispatch<React.SetStateAction<PaginationRequest>>;
  setAllPaginationRequest: Dispatch<React.SetStateAction<PaginationRequest>>;
  setFilters: Dispatch<React.SetStateAction<ShiftManagementFilter>>;
  
  // Dialog states
  approveDialogOpen: boolean;
  rejectDialogOpen: boolean;
  selectedShift: Shift | null;
  createTemplateDialogOpen: boolean;
  updateTemplateDialogOpen: boolean;
  selectedTemplate: ShiftTemplate | null;
  assignShiftDialogOpen: boolean;
  editShiftDialogOpen: boolean;
  
  // Actions
  setApproveDialogOpen: (open: boolean) => void;
  setRejectDialogOpen: (open: boolean) => void;
  handleApprove: (id: string) => Promise<void>;
  handleReject: (id: string, rejectionReason: string) => Promise<void>;
  handleApproveClick: (shift: Shift) => void;
  handleRejectClick: (shift: Shift) => void;
  
  // Template actions
  setCreateTemplateDialogOpen: (open: boolean) => void;
  setUpdateTemplateDialogOpen: (open: boolean) => void;
  handleCreateTemplate: (data: CreateShiftTemplateRequest) => Promise<void>;
  handleUpdateTemplate: (id: string, data: UpdateShiftTemplateRequest) => Promise<void>;
  handleDeleteTemplate: (id: string) => Promise<void>;
  handleEditTemplateClick: (template: ShiftTemplate) => void;
  
  // Assign shift actions
  setAssignShiftDialogOpen: (open: boolean) => void;
  handleCreateShift: (data: CreateShiftRequest) => Promise<void>;
  
  // Edit shift actions
  setEditShiftDialogOpen: (open: boolean) => void;
  handleEditShiftClick: (shift: Shift) => void;
}

const ShiftManagementContext = createContext<ShiftManagementContextValue | undefined>(undefined);

export const useShiftManagementContext = () => {
  const context = useContext(ShiftManagementContext);
  if (!context) {
    throw new Error('useShiftManagementContext must be used within ShiftManagementProvider');
  }
  return context;
};

interface ShiftManagementProviderProps {
  children: ReactNode;
}

export const ShiftManagementProvider = ({ children }: ShiftManagementProviderProps) => {
  // Dialog states
  const [approveDialogOpen, setApproveDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [selectedShift, setSelectedShift] = useState<Shift | null>(null);
  const [createTemplateDialogOpen, setCreateTemplateDialogOpen] = useState(false);
  const [updateTemplateDialogOpen, setUpdateTemplateDialogOpen] = useState(false);
  const [selectedTemplate, setSelectedTemplate] = useState<ShiftTemplate | null>(null);
  const [assignShiftDialogOpen, setAssignShiftDialogOpen] = useState(false);
  const [editShiftDialogOpen, setEditShiftDialogOpen] = useState(false);
  const [pendingPaginationRequest, setPendingPaginationRequest] = useState(defaultShiftPaginationRequest);
  const [allPaginationRequest, setAllPaginationRequest] = useState(defaultShiftPaginationRequest);
  const [filters, setFilters] = useState<ShiftManagementFilter>(defaultShiftManagementFilter);

  // Hooks
  const { data: pendingPaginatedShifts, isLoading: isPendingLoading } = usePendingShifts(pendingPaginationRequest);
  const { data: allPaginatedShifts, isLoading: isAllLoading } = useManagedShifts(allPaginationRequest, filters);
  const { data: templates = [], isLoading: isTemplatesLoading } = useShiftTemplates();
  const { data: employeesData = [], isLoading: isEmployeesLoading } = useEmployeesByManager();
  const employees = employeesData.map(e => ({
    id: e.id,
    firstName: e.firstName ?? '',
    lastName: e.lastName ?? '',
    email: e.email
  }));

  const approveShiftMutation = useApproveShift();
  const rejectShiftMutation = useRejectShift();
  const createTemplateMutation = useCreateShiftTemplate();
  const updateTemplateMutation = useUpdateShiftTemplate();
  const deleteTemplateMutation = useDeleteShiftTemplate();
  const createShiftMutation = useCreateShift();
  
  const isLoading = isPendingLoading || isAllLoading || isTemplatesLoading || isEmployeesLoading;

  const handleApprove = async (id: string) => {
    await approveShiftMutation.mutateAsync(id);
    setApproveDialogOpen(false);
    setSelectedShift(null);
  };

  const handleReject = async (id: string, rejectionReason: string) => {
    await rejectShiftMutation.mutateAsync({ id, data: { rejectionReason } });
    setRejectDialogOpen(false);
    setSelectedShift(null);
  };

  const handleApproveClick = (shift: Shift) => {
    setSelectedShift(shift);
    setApproveDialogOpen(true);
  };

  const handleRejectClick = (shift: Shift) => {
    setSelectedShift(shift);
    setRejectDialogOpen(true);
  };

  const handleCreateTemplate = async (data: { name: string; startTime: string; endTime: string }) => {
    await createTemplateMutation.mutateAsync(data);
    setCreateTemplateDialogOpen(false);
  };

  const handleUpdateTemplate = async (id: string, data: { name: string; startTime: string; endTime: string; isActive: boolean }) => {
    await updateTemplateMutation.mutateAsync({ id, data });
    setUpdateTemplateDialogOpen(false);
    setSelectedTemplate(null);
  };

  const handleDeleteTemplate = async (id: string) => {
    await deleteTemplateMutation.mutateAsync(id);
  };

  const handleEditTemplateClick = (template: ShiftTemplate) => {
    setSelectedTemplate(template);
    setUpdateTemplateDialogOpen(true);
  };

  const handleCreateShift = async (data: CreateShiftRequest) => {
    await createShiftMutation.mutateAsync(data);
    setAssignShiftDialogOpen(false);
  };

  const handleEditShiftClick = (shift: Shift) => {
    setSelectedShift(shift);
    setEditShiftDialogOpen(true);
  };

  const value: ShiftManagementContextValue = {
    // State
    pendingPaginationRequest,
    allPaginationRequest,
    pendingPaginatedShifts,
    allPaginatedShifts,
    templates,
    isLoading,
    employees,
    filters,

    setAllPaginationRequest,
    setPendingPaginationRequest,
    setFilters,
    
    // Dialog states
    approveDialogOpen,
    rejectDialogOpen,
    selectedShift,
    createTemplateDialogOpen,
    updateTemplateDialogOpen,
    selectedTemplate,
    assignShiftDialogOpen,
    editShiftDialogOpen,
    
    // Actions
    setApproveDialogOpen,
    setRejectDialogOpen,
    handleApprove,
    handleReject,
    handleApproveClick,
    handleRejectClick,
    
    // Template actions
    setCreateTemplateDialogOpen,
    setUpdateTemplateDialogOpen,
    handleCreateTemplate,
    handleUpdateTemplate,
    handleDeleteTemplate,
    handleEditTemplateClick,
    
    // Assign shift actions
    setAssignShiftDialogOpen,
    handleCreateShift,
    
    // Edit shift actions
    setEditShiftDialogOpen,
    handleEditShiftClick,
  };

  return (
    <ShiftManagementContext.Provider value={value}>
      {children}
    </ShiftManagementContext.Provider>
  );
};
