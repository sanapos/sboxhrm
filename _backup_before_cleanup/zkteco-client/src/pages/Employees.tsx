// ==========================================
// src/pages/EmployeeInfo.tsx
// ==========================================
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { EmployeeTable } from "@/components/employees/EmployeeTable";
import { NewEmployeeDialog } from "@/components/employees/dialogs/NewEmployeeDialog";
import { EmployeeFilterBar } from "@/components/employees/EmployeeFilterBar";
import { EmployeeProvider, useEmployeeContext } from "@/contexts/EmployeeContext";
import { AddEmployeeToDeviceDialog } from "@/components/employees/dialogs/AddEmployeeToDeviceDialog";
import { NewEmployeeAccountDialog } from "@/components/employees/dialogs/NewEmployeeAccountDialog";
import { UpdateEmployeeAccountDialog } from "@/components/employees/dialogs/UpdateEmployeeAccountDialog";

const EmployeesContent = () => {
  const { 
    handleOpenCreateDialog
  } = useEmployeeContext();

  return (
    <div className="flex-1 space-y-4 p-4 md:p-8 pt-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold tracking-tight">Employees</h2>
          <p className="text-muted-foreground">
            Manage employee records and information
          </p>
        </div>
        <Button onClick={handleOpenCreateDialog}>
          <Plus className="mr-2 h-4 w-4" />
          Add Employee
        </Button>
      </div>

      <EmployeeFilterBar />
      <EmployeeTable />
      <NewEmployeeDialog />
      <AddEmployeeToDeviceDialog />
      <NewEmployeeAccountDialog />
      <UpdateEmployeeAccountDialog />
    </div>
  );
};

export default function Employees() {
  return (
      <EmployeeProvider>
        <EmployeesContent />
      </EmployeeProvider>
  );
}
