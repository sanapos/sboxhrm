import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { payslipService } from '@/services/payslipService';
import { GeneratePayslipRequest } from '@/types/payslip';
import { toast } from 'sonner';

// Fetch employee's payslips
export const usePayslips = (employeeUserId?: string) => {
  return useQuery({
    queryKey: ['payslips', employeeUserId],
    queryFn: () => payslipService.getPayslips(employeeUserId),
    enabled: true,
  });
};

// Fetch a specific payslip by ID
export const usePayslip = (id: string) => {
  return useQuery({
    queryKey: ['payslip', id],
    queryFn: () => payslipService.getPayslipById(id),
    enabled: !!id,
  });
};

// Generate payslip mutation
export const useGeneratePayslip = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: GeneratePayslipRequest) => payslipService.generatePayslip(data),
    onSuccess: (data) => {
      toast.success('Payslip generated successfully');
      // Invalidate payslips for this employee
      queryClient.invalidateQueries({ queryKey: ['payslips', data.employeeUserId] });
      queryClient.invalidateQueries({ queryKey: ['payslips'] });
    },
    onError: (error: any) => {
      toast.error(error.message || 'Failed to generate payslip');
    },
  });
};

