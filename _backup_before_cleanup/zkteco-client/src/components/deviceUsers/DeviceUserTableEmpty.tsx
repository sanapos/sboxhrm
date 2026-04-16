import { TableCell, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/EmptyState";
import { Users as UsersIcon, Plus } from "lucide-react";

interface EmployeeTableEmptyProps {
  onAddUser: () => void;
}

export const DeviceUserTableEmpty = ({ onAddUser }: EmployeeTableEmptyProps) => {
  return (
    <TableRow>
      <TableCell colSpan={9} className="h-48">
        <EmptyState
          icon={UsersIcon}
          title="No users found"
          description="Get started by adding your first user"
          action={
            <Button onClick={onAddUser}>
              <Plus className="w-4 h-4 mr-2" />
              Add User
            </Button>
          }
        />
      </TableCell>
    </TableRow>
  );
};
