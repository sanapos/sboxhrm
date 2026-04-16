import { TableCell, TableRow } from "@/components/ui/table";
import { DeviceUser } from "@/types/deviceUser";
import { UserPrivileges } from "@/constants";
import { DeviceUserTableActions } from "./DeviceUserTableActions";
import { Button } from "../ui/button";
import { useDeviceUserContext } from "@/contexts/DeviceUserContext";

interface DeviceUserTableRowProps {
  deviceUser: DeviceUser;
}

export const DeviceUserTableRow = ({ deviceUser }: DeviceUserTableRowProps) => {
  const { setLinkedEmployee } = useDeviceUserContext();
  return (
    <TableRow key={deviceUser.id}>
      <TableCell className="text-muted-foreground">
        {deviceUser.deviceName || "-"}
      </TableCell>
      <TableCell className="text-muted-foreground">
        {deviceUser.employee ? (
          <Button
            variant="link"
            className="p-0 m-0 h-auto"
            onClick={() => setLinkedEmployee(deviceUser.employee || null)}
          >
            {deviceUser.employee?.fullName || "-"}
          </Button>
        ) : (
          <span>-</span>
        )}
      </TableCell>
      <TableCell className="font-mono font-medium">{deviceUser.employee?.employeeCode || "-"}</TableCell>
      <TableCell className="font-mono font-medium">{deviceUser.pin}</TableCell>
      <TableCell className="font-medium">{deviceUser.name}</TableCell>
      <TableCell className="font-medium">
        {UserPrivileges[deviceUser.privilege]}
      </TableCell>
      <TableCell className="text-muted-foreground">
        {deviceUser.cardNumber || "-"}
      </TableCell>
      <TableCell className="text-right">
        <DeviceUserTableActions deviceUser={deviceUser} />
      </TableCell>
    </TableRow>
  );
};
