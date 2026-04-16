import { createContext, useContext, useState, ReactNode } from 'react';
import {
  useBenefits,
  useCreateBenefit,
  useUpdateBenefit,
  useDeleteBenefit,
} from '@/hooks/useBenefits';
import { Benefit, CreateBenefitRequest, UpdateBenefitRequest } from '@/types/benefit';

interface SalaryProfileContextValue {
  // State
  benefits: Benefit[] | undefined;
  isLoading: boolean;
  showActiveOnly: boolean;
  
  // Dialog states
  createDialogOpen: boolean;
  editDialogOpen: boolean;
  assignDialogOpen: boolean;
  profileToEdit: Benefit | null;
  preSelectedEmployeeId: string | null;
  
  // Actions
  setCreateDialogOpen: (open: boolean) => void;
  setEditDialogOpen: (open: boolean) => void;
  setAssignDialogOpen: (open: boolean) => void;
  setShowActiveOnly: (show: boolean) => void;
  handleCreateProfile: (data: CreateBenefitRequest) => Promise<void>;
  handleUpdateProfile: (data: UpdateBenefitRequest) => Promise<void>;
  handleEdit: (profile: Benefit) => void;
  handleOpenCreateDialog: () => void;
  handleDelete: (id: string) => Promise<void>;
  handleOpenAssignDialog: (employeeId?: string) => void;
  
  // Mutation states
  isCreatePending: boolean;
  isUpdatePending: boolean;
  isDeletePending: boolean;
}

const SalaryProfileContext = createContext<SalaryProfileContextValue | undefined>(undefined);

export const useSalaryProfileContext = () => {
  const context = useContext(SalaryProfileContext);
  if (!context) {
    throw new Error('useSalaryProfileContext must be used within SalaryProfileProvider');
  }
  return context;
};

interface BenefitProviderProps {
  children: ReactNode;
}

export const BenefitProvider = ({ children }: BenefitProviderProps) => {
  // State
  const [showActiveOnly, setShowActiveOnly] = useState(false);
  const [createDialogOpen, setCreateDialogOpenState] = useState(false);
  const [editDialogOpen, setEditDialogOpenState] = useState(false);
  const [assignDialogOpen, setAssignDialogOpenState] = useState(false);
  const [profileToEdit, setProfileToEdit] = useState<Benefit | null>(null);
  const [preSelectedEmployeeId, setPreSelectedEmployeeId] = useState<string | null>(null);
  
  // Hooks
  const { data: benefits, isLoading } = useBenefits();
  const createProfileMutation = useCreateBenefit();
  const updateProfileMutation = useUpdateBenefit();
  const deleteProfileMutation = useDeleteBenefit();

  // Wrapper to clear profile state when closing dialog
  const setCreateDialogOpen = (open: boolean) => {
    if (!open) {
      setProfileToEdit(null);
    }
    setCreateDialogOpenState(open);
  };

  const setEditDialogOpen = (open: boolean) => {
    if (!open) {
      setProfileToEdit(null);
    }
    setEditDialogOpenState(open);
  };

  const setAssignDialogOpen = (open: boolean) => {
    if (!open) {
      setPreSelectedEmployeeId(null);
    }
    setAssignDialogOpenState(open);
  };

  // Handlers
  const handleCreateProfile = async (data: CreateBenefitRequest) => {
    await createProfileMutation.mutateAsync(data);
    setCreateDialogOpen(false);
  };

  const handleUpdateProfile = async (data: UpdateBenefitRequest) => {
    if (!profileToEdit?.id) return;
    
    await updateProfileMutation.mutateAsync({
      id: profileToEdit.id,
      data,
    });
    setEditDialogOpen(false);
    setProfileToEdit(null);
  };

  const handleEdit = (profile: Benefit) => {
    setProfileToEdit(profile);
    setEditDialogOpen(true);
  };

  const handleOpenCreateDialog = () => {
    setProfileToEdit(null);
    setCreateDialogOpen(true);
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this salary profile?')) {
      return;
    }
    await deleteProfileMutation.mutateAsync(id);
  };

  const handleOpenAssignDialog = (employeeId?: string) => {
    setPreSelectedEmployeeId(employeeId || null);
    setAssignDialogOpen(true);
  };

  const value: SalaryProfileContextValue = {
    // State
    benefits,
    isLoading,
    showActiveOnly,
    
    // Dialog states
    createDialogOpen,
    editDialogOpen,
    assignDialogOpen,
    profileToEdit,
    preSelectedEmployeeId,
    
    // Actions
    setCreateDialogOpen,
    setEditDialogOpen,
    setAssignDialogOpen,
    setShowActiveOnly,
    handleCreateProfile,
    handleUpdateProfile,
    handleEdit,
    handleOpenCreateDialog,
    handleDelete,
    handleOpenAssignDialog,
    
    // Mutation states
    isCreatePending: createProfileMutation.isPending,
    isUpdatePending: updateProfileMutation.isPending,
    isDeletePending: deleteProfileMutation.isPending,
  };

  return (
    <SalaryProfileContext.Provider value={value}>
      {children}
    </SalaryProfileContext.Provider>
  );
};

// Alias for backward compatibility
export { BenefitProvider as SalaryProfileProvider };
