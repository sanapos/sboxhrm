import { Button } from "@/components/ui/button";
import { Trash2, Edit, UserPlus, UserCheck } from "lucide-react";
import { DeviceUser } from "@/types/deviceUser";
import { useDeviceUserContext } from "@/contexts/DeviceUserContext";

interface DeviceUserTableActionsProps {
  deviceUser: DeviceUser;
}

export const DeviceUserTableActions = ({
  deviceUser,
}: DeviceUserTableActionsProps) => {
  
  const {
    isDeletePending,
    handleEdit,
    handleDelete,
    handleMapToEmployee,
  } = useDeviceUserContext()
  
  return (
    <>
      <div className="flex justify-end gap-2">
        <Button
            variant="ghost"
            size="icon"
            onClick={() => handleMapToEmployee(deviceUser)}
            title="Map to Employee"
          >
          {
            deviceUser.employee ? (
              <UserCheck className="w-4 h-4 text-success text-green-500" />
            ) : (
              <UserPlus className="w-4 h-4" />
            )
          }
        </Button>
        
        <Button
          variant="ghost"
          size="icon"
          onClick={() => handleEdit(deviceUser)}
          title="Edit User"
        >
          <Edit className="w-4 h-4" />
        </Button>
        
        <Button
          variant="ghost"
          size="icon"
          onClick={() => handleDelete(deviceUser)}
          disabled={isDeletePending}
          title="Delete User"
        >
          <Trash2 className="w-4 h-4 text-destructive" />
        </Button>
      </div>

      
    </>
  );
};