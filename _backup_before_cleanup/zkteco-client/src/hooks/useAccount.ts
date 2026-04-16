import { useAuth } from "@/contexts/AuthContext";
import { accountService } from "@/services/accountService";
import { useQuery } from "@tanstack/react-query";

export const useEmployeesByManager = () => {
    const { isManager } = useAuth();
    return useQuery({
        queryKey: ['employeeAccountsByManager'],
        queryFn: () => accountService.getEmployeeAccountsByManager(),
        enabled: isManager,
    });
}