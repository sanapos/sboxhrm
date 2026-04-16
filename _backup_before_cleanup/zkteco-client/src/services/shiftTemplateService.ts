import { CreateShiftTemplateRequest, ShiftTemplate, UpdateShiftTemplateRequest } from "@/types/shift";
import { apiService } from "./api";

export const shiftTemplateService = {
     // Shift Template endpoints
    getShiftTemplates: async () => {
        return await apiService.get<ShiftTemplate[]>('/api/shifts/templates');
    },

    createShiftTemplate: async (data: CreateShiftTemplateRequest) => {
        return await apiService.post<ShiftTemplate>('/api/shifts/templates', data);
    },

    updateShiftTemplate: async (id: string, data: UpdateShiftTemplateRequest) => {
        return await apiService.put<ShiftTemplate>(`/api/shifts/templates/${id}`, data);
    },

    deleteShiftTemplate: async (id: string) => {
        return await apiService.delete<boolean>(`/api/shifts/templates/${id}`);
    },
}