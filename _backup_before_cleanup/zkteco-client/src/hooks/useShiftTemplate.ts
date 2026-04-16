import { shiftTemplateService } from "@/services/shiftTemplateService";
import { CreateShiftTemplateRequest, UpdateShiftTemplateRequest } from "@/types/shift";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

// Shift Template hooks
export const useShiftTemplates = () => {
  return useQuery({
    queryKey: ['shift-templates'],
    queryFn: () => shiftTemplateService.getShiftTemplates(),
  });
};

export const useCreateShiftTemplate = () => {
  const queryClient = useQueryClient();
    
  return useMutation({
    mutationFn: (data: CreateShiftTemplateRequest) => shiftTemplateService.createShiftTemplate(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shift-templates'] });
      toast.success('Shift template created successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to create shift template', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useUpdateShiftTemplate = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateShiftTemplateRequest }) =>
      shiftTemplateService.updateShiftTemplate(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shift-templates'] });
      toast.success('Shift template updated successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to update shift template', {
        description: error.message || 'An error occurred',
      });
    },
  });
};

export const useDeleteShiftTemplate = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => shiftTemplateService.deleteShiftTemplate(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shift-templates'] });
      toast.success('Shift template deleted successfully');
    },
    onError: (error: any) => {
      toast.error('Failed to delete shift template', {
        description: error.message || 'An error occurred',
      });
    },
  });
};
