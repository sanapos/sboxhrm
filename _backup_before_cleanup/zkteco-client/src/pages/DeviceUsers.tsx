// ==========================================
// src/pages/Employees.tsx
// ==========================================
import { PageHeader } from "@/components/PageHeader";
import FilterBar from "@/components/deviceUsers/FilterBar";
import { DeviceUserProvider, useDeviceUserContext } from "@/contexts/DeviceUserContext";
import { DeviceUsersTable } from "@/components/deviceUsers/DeviceUserTable";
import { DeviceUserRequestDialog } from "@/components/deviceUsers/dialogs/DeviceUserRequestDialog";
import { MapToEmployeeDialog } from "@/components/deviceUsers/dialogs/MapToEmployeeDialog";
import { EmployeeDetailDialog } from "@/components/employees/dialogs/EmployeeDetailDialog";
import { DeleteDeviceUserDialog } from "@/components/deviceUsers/DeleteDeviceUserDialog";

const DeviceUsersContent = () => {
  const {
    devices,
    selectedDeviceIds,
    handleFilterSubmit,
    mapToEmployeeDialogOpen,
    setMapToEmployeeDialogOpen,
    employeeToMap,
    handleConfirmMapToEmployee,
    linkedEmployee,
    setLinkedEmployee
  } = useDeviceUserContext();

  return (
    <div>
      <PageHeader
        title="Device Users"
        description="Manage Device Users "
      />

      <FilterBar
        devices={devices}
        handleSubmit={handleFilterSubmit}
        selectedDeviceIds={selectedDeviceIds}
      />

      <DeviceUsersTable />

      <DeviceUserRequestDialog />
      
      <MapToEmployeeDialog
        open={mapToEmployeeDialogOpen}
        deviceUser={employeeToMap}
        onOpenChange={setMapToEmployeeDialogOpen}
        onConfirm={handleConfirmMapToEmployee}
      />
      <DeleteDeviceUserDialog />

      <EmployeeDetailDialog
        open={linkedEmployee !== null}
        employee={linkedEmployee}
        onOpenChange={() => setLinkedEmployee(null)}
      />
    </div>
  );
};

export const DeviceUsers = () => {
  return (
    <DeviceUserProvider>
      <DeviceUsersContent />
    </DeviceUserProvider>
  );
};
