// ==========================================
// src/contexts/ShiftContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode, Dispatch, SetStateAction, useMemo, useCallback } from 'react';
import { Shift, CreateShiftRequest, UpdateShiftRequest } from '@/types/shift';
import { 
  useMyShifts, 
  useCreateShift, 
  useUpdateShift, 
  useDeleteShift 
} from '@/hooks/useShifts';
import { defaultShiftPaginationRequest } from '@/constants/defaultValue';
import { PaginatedResponse, PaginationRequest } from '@/types';

interface ShiftContextValue {
  // State
  isLoading: boolean;
  paginatedShifts: PaginatedResponse<Shift>

  paginationRequest: PaginationRequest;
  setPaginationRequest: Dispatch<SetStateAction<PaginationRequest>>;

  // Dialog states
  dialogMode: 'create' | 'edit' | null;
  setDialogMode: (mode: 'create' | 'edit' | null) => void;
  selectedShift: Shift | null;
  
  // Actions
  handleCreate: (data: CreateShiftRequest) => Promise<void>;
  handleUpdate: (id: string, data: UpdateShiftRequest) => Promise<void>;
  handleDelete: (id: string) => Promise<void>;
  handleEdit: (shift: Shift) => void;
}

const ShiftContext = createContext<ShiftContextValue | undefined>(undefined);

export const useShiftContext = () => {
  const context = useContext(ShiftContext);
  if (!context) {
    throw new Error('useShiftContext must be used within ShiftProvider');
  }
  return context;
};

interface ShiftProviderProps {
  children: ReactNode;
}

export const ShiftProvider = ({ children }: ShiftProviderProps) => {
  // Dialog states
  const [dialogMode, setDialogMode] = useState<'create' | 'edit' | null>(null);
  const [selectedShift, setSelectedShift] = useState<Shift | null>(null);
  const [paginationRequest, setPaginationRequest] = useState(defaultShiftPaginationRequest);

  // Hooks
  const { data: paginatedShifts, isLoading } = useMyShifts(paginationRequest);
  const createShiftMutation = useCreateShift();
  const updateShiftMutation = useUpdateShift();
  const deleteShiftMutation = useDeleteShift();

  const handleCreate = useCallback(async (data: CreateShiftRequest) => {
    await createShiftMutation.mutateAsync(data);
    setDialogMode(null);
  }, [createShiftMutation]);

  const handleUpdate = useCallback(async (id: string, data: UpdateShiftRequest) => {
    await updateShiftMutation.mutateAsync({ id, data });
    setSelectedShift(null);
    setDialogMode(null);
  }, [updateShiftMutation]);

  const handleDelete = useCallback(async (id: string) => {
    await deleteShiftMutation.mutateAsync(id);
  }, [deleteShiftMutation]);

  const handleEdit = useCallback((shift: Shift) => {
    setSelectedShift(shift);
    setDialogMode('edit');
  }, []);

  // Memoize the default empty paginated response
  const emptyPaginatedResponse = useMemo<PaginatedResponse<Shift>>(() => ({ 
    items: [], 
    totalCount: 0, 
    pageNumber: 1, 
    pageSize: 10, 
    totalPages: 0,
    hasPreviousPage: false,
    hasNextPage: false
  }), []);

  // Memoize the context value
  const value: ShiftContextValue = {
    // State
    paginatedShifts: paginatedShifts || emptyPaginatedResponse,
    isLoading,
    paginationRequest,
    setPaginationRequest,
    // Dialog states
    dialogMode,
    setDialogMode,
    selectedShift,
    
    // Actions
    handleCreate,
    handleUpdate,
    handleDelete,
    handleEdit,
  }

  return (
    <ShiftContext.Provider value={value}>
      {children}
    </ShiftContext.Provider>
  );
};
