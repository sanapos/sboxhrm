import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import { Settings, RefreshCw, Trash2, RefreshCcwDotIcon } from 'lucide-react'
import { useState } from 'react'
import { DeviceCommandTypes } from '@/types/device'
import { useDeviceCommands } from '@/hooks/useDeviceCommands'

interface DeviceSettingsDropdownProps {
  deviceId: string
}

  const getConfirmationContent = (confirmAction: DeviceCommandTypes) => {
    switch (confirmAction) {
      case DeviceCommandTypes.ClearAttendances:
        return {
          title: 'Clear All Attendances?',
          description: 'This will permanently delete all attendance records from this device. This action cannot be undone.',
        }
      case DeviceCommandTypes.ClearEmployees:
        return {
          title: 'Clear All Users?',
          description: 'This will remove all user data from this device. This action cannot be undone.',
        }
      case DeviceCommandTypes.ClearData:
        return {
          title: 'Clear All Data?',
          description: 'This will permanently delete all data (users, attendances, etc.) from this device. This action cannot be undone.',
        }
      case DeviceCommandTypes.RestartDevice:
        return {
          title: 'Reboot Device',
          description: 'This will restart the device. Any unsaved data may be lost.',
        }
      case DeviceCommandTypes.SyncAttendances:
        return {
          title: 'Sync Attendances',
          description: 'This will synchronize attendance records from the device to the server.',
        }
      case DeviceCommandTypes.SyncUsers:
        return {
          title: 'Sync Users',
          description: 'This will synchronize user data from the device to the server.',
        }
      default:
        return { title: '', description: '' }
    }
  }

export const DeviceSettingsDropdown = ({
  deviceId,
}: DeviceSettingsDropdownProps) => {
    const [confirmAction, setConfirmAction] = useState<DeviceCommandTypes | null>(null)
    
    const {
      handleSyncAttendances,
      handleSyncUsers,
      handleClearAttendances,
      handleRestartDevice,
      handleClearUsers,
      handleClearData
    } = useDeviceCommands()

  const handleConfirm = async () => {
    switch (confirmAction) {
      case DeviceCommandTypes.SyncAttendances:
        await handleSyncAttendances(deviceId)
        break
      case DeviceCommandTypes.SyncUsers:
        await handleSyncUsers(deviceId)
        break
      case DeviceCommandTypes.ClearAttendances:
        await handleClearAttendances(deviceId)
        break
      case DeviceCommandTypes.ClearEmployees:
        await handleClearUsers(deviceId)
        break
      case DeviceCommandTypes.ClearData:
        await handleClearData(deviceId)
        break
      case DeviceCommandTypes.RestartDevice:
        await handleRestartDevice(deviceId)
        break
      default:
        break
    }
    setConfirmAction(null)
  }
  const { title, description } = getConfirmationContent(confirmAction!);
  
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon">
            <Settings className="w-4 h-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel>Device Actions</DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.SyncAttendances)}>
            <RefreshCcwDotIcon className="w-4 h-4 mr-2 text-green-500" />
            Sync Attendances
          </DropdownMenuItem>

          <DropdownMenuSeparator />

          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.SyncUsers)}>
            <RefreshCcwDotIcon className="w-4 h-4 mr-2 text-green-500" />
            Sync Users
          </DropdownMenuItem>

          <DropdownMenuSeparator />
          
          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.ClearAttendances)}>
            <Trash2 className="w-4 h-4 mr-2 text-red-500" />
            Clear Attendances
          </DropdownMenuItem>
          <DropdownMenuSeparator />

          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.ClearEmployees)}>
            <Trash2 className="w-4 h-4 mr-2 text-red-500" />
            Clear Users
          </DropdownMenuItem>
          
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.ClearData)}>
            <Trash2 className="w-4 h-4 mr-2 text-red-500" />
            Clear All Data
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          
          <DropdownMenuItem onClick={() => setConfirmAction(DeviceCommandTypes.RestartDevice)}>
            <RefreshCw className="w-4 h-4 mr-2" />
            Reboot Device
          </DropdownMenuItem>
          
        </DropdownMenuContent>
      </DropdownMenu>

      <AlertDialog open={confirmAction !== null} onOpenChange={() => setConfirmAction(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <Trash2 className="w-5 h-5 text-red-500" />
              {title}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {description}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleConfirm}
              className="bg-red-500 hover:bg-red-600"
            >
              Yes
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
