import { useQuery } from '@tanstack/react-query';
import { managerDashboardService } from '@/services/managerDashboardService';

export const useManagerDashboard = (date?: Date) => {
  return useQuery({
    queryKey: ['managerDashboard', date?.toISOString()],
    queryFn: () => managerDashboardService.getManagerDashboard(date),
    staleTime: 1000 * 60, // 1 minute
  });
};
