import benefitService from '@/services/benefitService';
import { AssignSalaryProfileRequest, CreateBenefitRequest, UpdateBenefitRequest } from '@/types/benefit';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

import { toast } from 'sonner';

export const useBenefits = (salaryRateType?: number) => {
  return useQuery({
    queryKey: ['benefits', salaryRateType],
    queryFn: () => benefitService.getBenefits(salaryRateType),
  });
};

export const useBenefitById = (id: string) => {
  return useQuery({
    queryKey: ['benefit', id],
    queryFn: () => benefitService.getBenefitById(id),
    enabled: !!id,
  });
};

export const useCreateBenefit = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateBenefitRequest) => benefitService.createBenefit(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['benefits'] });
      toast.success('Benefit profile created successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to create benefit profile', {
        description: error.message,
      });
    },
  });
};

export const useUpdateBenefit = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateBenefitRequest }) =>
      benefitService.updateBenefit(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['benefits'] });
      toast.success('Benefit profile updated successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to update benefit profile', {
        description: error.message,
      });
    },
  });
};

export const useDeleteBenefit = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => benefitService.deleteBenefit(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['benefits'] });
      toast.success('Benefit profile deleted successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to delete benefit profile', {
        description: error.message,
      });
    },
  });
};


export const useAssignEmployee = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: AssignSalaryProfileRequest) => benefitService.assignEmployee(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['benefits'] });
      queryClient.invalidateQueries({ queryKey: ['employeeBenefits'] });
      toast.success('Benefit profile assigned to employee successfully');
    },
    onError: (error: Error) => {
      toast.error('Failed to assign benefit profile', {
        description: error.message,
      });
    },
  });
}

export const useEmployeeBenefits = () => {
  return useQuery({
    queryKey: ['employeeBenefits'],
    queryFn: () => benefitService.getEmployeeBenefits(),
  });
};
