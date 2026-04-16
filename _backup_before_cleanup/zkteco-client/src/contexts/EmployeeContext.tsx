// ==========================================
// src/contexts/EmployeeInfoContext.tsx
// ==========================================
import { createContext, useContext, useState, ReactNode } from 'react';

import {
  useEmployees,
  useDeleteEmployee,
  useCreateEmployee,
  useUpdateEmployee,
} from '@/hooks/useEmployee';
import { useCreateEmployeeAccount, useUpdateEmployeeAccount } from '@/hooks/useDeviceUsers';
import { Employee, CreateEmployeeRequest, UpdateEmployeeRequest } from '@/types/employee';
import { GetEmployeesParams } from '@/services/employeeService';
import { CreateEmployeeAccountRequest } from '@/types/account';

interface EmployeeContextValue {
  // State
  employees: any | undefined;
  isLoading: boolean;
  queryParams: GetEmployeesParams;
  
  // Dialog states
  createDialogOpen: boolean;
  deleteDialogOpen: boolean;
  addToDeviceDialogOpen: boolean;
  createAccountDialogOpen: boolean;
  updateAccountDialogOpen: boolean;
  employeeToEdit: Employee | null;
  employeeToDelete: Employee | null;
  employeeToAddToDevice: Employee | null;
  employeeForAccount: Employee | null;
  employeeForUpdateAccount: Employee | null;
  
  // Actions
  setCreateDialogOpen: (open: boolean) => void;
  setDeleteDialogOpen: (open: boolean) => void;
  setAddToDeviceDialogOpen: (open: boolean) => void;
  setCreateAccountDialogOpen: (open: boolean) => void;
  setUpdateAccountDialogOpen: (open: boolean) => void;
  setQueryParams: (params: GetEmployeesParams) => void;
  handleDelete: (employee: Employee) => void;
  handleConfirmDelete: () => Promise<void>;
  handleAddEmployee: (data: CreateEmployeeRequest) => Promise<void>;
  handleUpdateEmployee: (data: UpdateEmployeeRequest) => Promise<void>;
  handleEdit: (employee: Employee) => void;
  handleOpenCreateDialog: () => void;
  handleAddToDevice: (employee: Employee) => void;
  handleOpenCreateAccount: (employee: Employee) => void;
  handleOpenUpdateAccount: (employee: Employee) => void;
  handleCreateAccount: (data: CreateEmployeeAccountRequest) => Promise<void>;
  handleUpdateAccount: (data: any) => Promise<void>;
  
  // Mutation states
  isDeletePending: boolean;
  isCreatePending: boolean;
  isUpdatePending: boolean;
  isCreateAccountPending: boolean;
  isUpdateAccountPending: boolean;
}

const EmployeeInfoContext = createContext<EmployeeContextValue | undefined>(undefined);

export const useEmployeeContext = () => {
  const context = useContext(EmployeeInfoContext);
  if (!context) {
    throw new Error('useEmployeeInfoContext must be used within EmployeeInfoProvider');
  }
  return context;
};

interface EmployeeProviderProps {
  children: ReactNode;
}

export const EmployeeProvider = ({ children }: EmployeeProviderProps) => {
  // Dialog states
  const [createDialogOpen, setCreateDialogOpenState] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [addToDeviceDialogOpen, setAddToDeviceDialogOpen] = useState(false);
  const [createAccountDialogOpen, setCreateAccountDialogOpen] = useState(false);
  const [updateAccountDialogOpen, setUpdateAccountDialogOpen] = useState(false);
  const [employeeToEdit, setEmployeeToEdit] = useState<Employee | null>(null);
  const [employeeToDelete, setEmployeeToDelete] = useState<Employee | null>(null);
  const [employeeToAddToDevice, setEmployeeToAddToDevice] = useState<Employee | null>(null);
  const [employeeForAccount, setEmployeeForAccount] = useState<Employee | null>(null);
  const [employeeForUpdateAccount, setEmployeeForUpdateAccount] = useState<Employee | null>(null);
  const [queryParams, setQueryParams] = useState<GetEmployeesParams>({
    pageNumber: 1,
    pageSize: 10,
    searchTerm: '',
    workStatus: '',
    employmentType: '',
  });
  
  // Hooks
  const { data: employees, isLoading } = useEmployees(queryParams);
  const deleteEmployeeMutation = useDeleteEmployee();
  const createEmployeeMutation = useCreateEmployee();
  const updateEmployeeMutation = useUpdateEmployee();
  const createAccountMutation = useCreateEmployeeAccount();
  const updateAccountMutation = useUpdateEmployeeAccount();

  // Wrapper for setCreateDialogOpen to clear employee state when closing
  const setCreateDialogOpen = (open: boolean) => {
    if (!open) {
      setEmployeeToEdit(null); // Clear employee data when dialog closes
    }
    setCreateDialogOpenState(open);
  };

  // Handlers
  const handleDelete = (employee: Employee) => {
    setEmployeeToDelete(employee);
    setDeleteDialogOpen(true);
  };

  const handleConfirmDelete = async () => {
    if (!employeeToDelete?.id) return;
    await deleteEmployeeMutation.mutateAsync(employeeToDelete.id);
    setDeleteDialogOpen(false);
    setEmployeeToDelete(null);
  };

  const handleAddEmployee = async (data: CreateEmployeeRequest) => {
    await createEmployeeMutation.mutateAsync(data);
    setCreateDialogOpen(false);
  };

  const handleUpdateEmployee = async (data: UpdateEmployeeRequest) => {
    if (!employeeToEdit?.id) return;
    
    await updateEmployeeMutation.mutateAsync({
      id: employeeToEdit.id,
      data,
    });
    setCreateDialogOpen(false);
    setEmployeeToEdit(null);
  };

  const handleEdit = (employee: Employee) => {
    setEmployeeToEdit(employee);
    setCreateDialogOpen(true);
  };

  const handleOpenCreateDialog = () => {
    setEmployeeToEdit(null); // Clear any previous employee data
    setCreateDialogOpen(true);
  };

  const handleAddToDevice = (employee: Employee) => {
    setEmployeeToAddToDevice(employee);
    setAddToDeviceDialogOpen(true);
  };

  const handleOpenCreateAccount = (employee: Employee) => {
    setEmployeeForAccount(employee);
    setCreateAccountDialogOpen(true);
  };

  const handleCreateAccount = async (data: CreateEmployeeAccountRequest) => {
    await createAccountMutation.mutateAsync(data);
    setCreateAccountDialogOpen(false);
    setEmployeeForAccount(null);
  };

  const handleOpenUpdateAccount = (employee: Employee) => {
    setEmployeeForUpdateAccount(employee);
    setUpdateAccountDialogOpen(true);
  };

  const handleUpdateAccount = async (data: any) => {
    await updateAccountMutation.mutateAsync(data);
    setUpdateAccountDialogOpen(false);
    setEmployeeForUpdateAccount(null);
  };

  const value: EmployeeContextValue = {
    // State
    employees,
    isLoading,
    queryParams,
    
    // Dialog states
    createDialogOpen,
    deleteDialogOpen,
    addToDeviceDialogOpen,
    createAccountDialogOpen,
    updateAccountDialogOpen,
    employeeToEdit,
    employeeToDelete,
    employeeToAddToDevice,
    employeeForAccount,
    employeeForUpdateAccount,
    
    // Actions
    setCreateDialogOpen,
    setDeleteDialogOpen,
    setAddToDeviceDialogOpen,
    setCreateAccountDialogOpen,
    setUpdateAccountDialogOpen,
    setQueryParams,
    handleDelete,
    handleConfirmDelete,
    handleAddEmployee,
    handleUpdateEmployee,
    handleEdit,
    handleOpenCreateDialog,
    handleAddToDevice,
    handleOpenCreateAccount,
    handleOpenUpdateAccount,
    handleCreateAccount,
    handleUpdateAccount,
    
    // Mutation states
    isDeletePending: deleteEmployeeMutation.isPending,
    isCreatePending: createEmployeeMutation.isPending,
    isUpdatePending: updateEmployeeMutation.isPending,
    isCreateAccountPending: createAccountMutation.isPending,
    isUpdateAccountPending: updateAccountMutation.isPending,
  };

  return (
    <EmployeeInfoContext.Provider value={value}>
      {children}
    </EmployeeInfoContext.Provider>
  );
};
