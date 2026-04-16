// ==========================================
// src/components/employees/EmployeeStatusBadge.tsx
// ==========================================
import { Badge } from "@/components/ui/badge";

interface EmployeeStatusBadgeProps {
  status: string;
}

export const EmployeeStatusBadge = ({ status }: EmployeeStatusBadgeProps) => {
  const variants: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
    "0": "default",      // Active
    "1": "destructive",  // Resigned
  };

  const labels: Record<string, string> = {
    "0": "Active",
    "1": "Resigned",
  };
  
  return (
    <Badge variant={variants[status] || "outline"}>
      {labels[status] || status}
    </Badge>
  );
};
