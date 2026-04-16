// ==========================================
// src/hooks/useEmployeeInfo.ts
// ==========================================
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { employeeService, GetEmployeesParams } from '@/services/employeeService';
import { toast } from 'sonner';
import { CreateEmployeeRequest, UpdateEmployeeRequest } from '@/types/employee';

export const useEmployees = (params: GetEmployeesParams = {}) => {
  return useQuery({
    queryKey: ['employeesInfo', params],
    queryFn: () => employeeService.getEmployees(params),
  });
};

export const useEmployeeById = (id: string) => {
  return useQuery({
    queryKey: ['employeeInfo', id],
    queryFn: () => employeeService.getEmployeeById(id),
    enabled: !!id,
  });
};

export const useCreateEmployee = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateEmployeeRequest) => employeeService.createEmployee(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employeesInfo'] });
      toast.success('Employee created successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to create employee', {
        description: error.message,
      });
    },
  });
};

export const useUpdateEmployee = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateEmployeeRequest }) =>
      employeeService.updateEmployee(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employeesInfo'] });
      toast.success('Employee updated successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to update employee', {
        description: error.message,
      });
    },
  });
};

export const useDeleteEmployee = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => employeeService.deleteEmployee(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employeesInfo'] });
      toast.success('Employee deleted successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to delete employee', {
        description: error.message,
      });
    },
  });
};
