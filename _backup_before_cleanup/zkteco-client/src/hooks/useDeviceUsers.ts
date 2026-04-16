
// ==========================================
// src/hooks/useEmployees.ts
// ==========================================
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { deviceUserService } from '@/services/deviceUserService';
import { toast } from 'sonner';
import { CreateDeviceUserRequest, UpdateDeviceUserRequest } from '@/types/deviceUser';
import { accountService } from '@/services/accountService';
import { CreateEmployeeAccountRequest, UpdateEmployeeAccountRequest } from '@/types/account';
import { Employee } from '@/types/employee';

export const useDeviceUsers = (deviceIds: string[]) => {
  return useQuery({
    queryKey: ['device-users', deviceIds],
    queryFn: () => deviceUserService.getEmployeesByDevices(deviceIds),
  });
};

export const useDeviceUser = (id: string) => {
  return useQuery({
    queryKey: ['device-user', id],
    queryFn: () => deviceUserService.getById(id),
    enabled: !!id,
  });
};

export const useCreateDeviceUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateDeviceUserRequest) => deviceUserService.create(data),
    onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['device-users'] });
        toast.success('Device user created successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to create device user', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useUpdateDeviceUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: UpdateDeviceUserRequest) => deviceUserService.update(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device-users'] });
      toast.success('Device user updated successfully');
    },
  });
};

export const useDeleteDeviceUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => deviceUserService.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device-users'] });
      toast.success('Device user deleted successfully');
    },
  });
};

export const useCreateEmployeeAccount = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateEmployeeAccountRequest) => accountService.createUserAccount(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      toast.success('Employee account created successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to create employee account', {
        description: error.message || 'An error occurred',
      });
    }
  });
};

export const useUpdateEmployeeAccount = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({employeeDeviceId, data}: {employeeDeviceId: string, data: UpdateEmployeeAccountRequest}) => accountService.updateUserAccount(employeeDeviceId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      toast.success('Employee account updated successfully');
    },
  });
};

export const useMapDeviceUserToEmployee = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({deviceUserId, employeeId}: {deviceUserId: string, employeeId: string}) => deviceUserService.mapToEmployee(deviceUserId, employeeId),
    onSuccess: (_employee: Employee) => {
      queryClient.invalidateQueries({ queryKey: ['device-users'] });
      toast.success('Device user mapped to employee successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to map device user to employee', {
        description: error.message || 'An error occurred',
      });
    },
  });
}