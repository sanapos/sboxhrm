import { apiService } from './api';
import type { ManagerDashboardData } from '@/types/manager-dashboard';

export const managerDashboardService = {
  getManagerDashboard: async (date?: Date): Promise<ManagerDashboardData> => {
    const params = new URLSearchParams();
    if (date) {
      params.append('date', date.toISOString());
    }
    return await apiService.get<ManagerDashboardData>(
      `api/dashboard/manager`
    );
  },
};
