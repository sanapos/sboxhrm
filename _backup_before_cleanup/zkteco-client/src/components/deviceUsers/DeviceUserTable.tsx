import { Card, CardContent } from "@/components/ui/card";
import { Table, TableBody } from "@/components/ui/table";
import { DeviceUserTableHeader } from "./DeviceUserTableHeader";
import { DeviceUserTableLoading } from "./DeviceUserTableLoading";
import { DeviceUserTableEmpty } from "./DeviceUserTableEmpty";
import { DeviceUserTableRow } from "./DeviceUserTableRow";
import { DeviceUser } from "@/types/deviceUser";
import { useDeviceUserContext } from "@/contexts/DeviceUserContext";

export const DeviceUsersTable = () => {
  const {
    deviceUsers,
    isLoading,
    handleOpenCreateDialog,
  } = useDeviceUserContext();

  return (
    <>
      <Card>
        <CardContent className="p-0">
          <Table>
            <DeviceUserTableHeader />
            <TableBody>
              {isLoading ? (
                <DeviceUserTableLoading />
              ) : !deviceUsers || deviceUsers.length === 0 ? (
                <DeviceUserTableEmpty onAddUser={handleOpenCreateDialog} />
              ) : (
                deviceUsers.map((deviceUser: DeviceUser) => (
                  <DeviceUserTableRow
                    key={deviceUser.id}
                    deviceUser={deviceUser}
                  />
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

    </>
  );
};
