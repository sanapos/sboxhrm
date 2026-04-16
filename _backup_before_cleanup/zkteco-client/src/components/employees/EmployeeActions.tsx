// ==========================================
// src/components/employees/EmployeeActions.tsx
// ==========================================
import { Button } from "@/components/ui/button";
import { MoreVertical, Pencil, Trash2, UserPlus, UserCog, UserPen } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Employee } from "@/types/employee";
import { useEmployeeContext } from "@/contexts/EmployeeContext";

interface EmployeeActionsProps {
  employee: Employee;
}

export const EmployeeActions = ({ employee }: EmployeeActionsProps) => {
  const {
    handleEdit,
    handleDelete,
    handleAddToDevice,
    handleOpenCreateAccount,
    handleOpenUpdateAccount,
  } = useEmployeeContext();

  const hasAccount = employee.hasAccount || !!employee.applicationUserId;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon">
          <MoreVertical className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => handleEdit(employee)}>
          <Pencil className="mr-2 h-4 w-4" />
          Edit
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => handleAddToDevice(employee)}>
          <UserPlus className="mr-2 h-4 w-4" />
          Add To Device
        </DropdownMenuItem>
        {hasAccount ? (
          <DropdownMenuItem onClick={() => handleOpenUpdateAccount(employee)}>
            <UserPen className="mr-2 h-4 w-4" />
            Update Account
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem onClick={() => handleOpenCreateAccount(employee)}>
            <UserCog className="mr-2 h-4 w-4" />
            Create Account
          </DropdownMenuItem>
        )}
        <DropdownMenuItem
          onClick={() => handleDelete(employee)}
          className="text-destructive"
        >
          <Trash2 className="mr-2 h-4 w-4" />
          Delete
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};
