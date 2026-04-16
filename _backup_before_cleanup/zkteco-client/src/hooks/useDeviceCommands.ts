// ==========================================
// src/hooks/useDeviceCommands.ts
// ==========================================
import { toast } from 'sonner'
import { DeviceCommandRequest, DeviceCommandTypes } from '@/types/device'
import { deviceCommandService } from '@/services/deviceCommandService'
import { useMutation, useQuery } from '@tanstack/react-query'

export interface DeviceCommandHandlers {
  handleSyncUsers: (deviceId: string) => Promise<void>
  handleSyncAttendances: (deviceId: string) => Promise<void>
  handleClearAttendances: (deviceId: string) => Promise<void>
  handleClearUsers: (deviceId: string) => Promise<void>
  handleClearData: (deviceId: string) => Promise<void>
  handleRestartDevice: (deviceId: string) => Promise<void>
}
/**
 * Custom hook that provides device command handlers and their loading states.
 * Can be used in any component that needs to execute device commands.
 * 
 * @param options.onSuccess - Optional callback to execute after successful command
 * @param options.validateDeviceId - Whether to validate deviceId before execution (default: true)
 */
export const useDeviceCommands = (options?: {
  onSuccess?: () => void
  validateDeviceId?: boolean
}): DeviceCommandHandlers => {
  const { onSuccess, validateDeviceId = true } = options || {}

  // Command mutations
    const createCommand = useCreateCommand()    
  /**
   * Generic command handler that validates device ID and handles success/error
   */
  const executeCommand = async (
    deviceId: string,
    commandType: DeviceCommandTypes,
    commandName: string
  ) => {
    if (validateDeviceId && !deviceId) {
      toast.error('Please select a device')
      return
    }

    try {
      await createCommand.mutateAsync({
        deviceId: deviceId,
        data: {
          commandType: commandType
        }
      })
      toast.success(`${commandName} command sent successfully`)
      onSuccess?.()
    } catch (error) {
      toast.error(`Failed to send ${commandName} command`)
      console.error(`Error executing ${commandName}:`, error)
    }
  }

  return {
    handleSyncUsers: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.SyncUsers, 'Sync Employees'),
    handleSyncAttendances: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.SyncAttendances, 'Sync Attendances'),
    handleClearAttendances: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.ClearAttendances, 'Clear Attendances'),
    handleClearData: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.ClearData, 'Clear Data'),
    handleClearUsers: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.ClearEmployees, 'Clear Employees'),
    handleRestartDevice: (deviceId) => executeCommand(deviceId, DeviceCommandTypes.RestartDevice, 'Restart Device')
  }
}

export const useGetDeviceCommands = (deviceId: string) => {
  return useQuery({
    queryKey: ['commands', deviceId],
    queryFn: () => deviceCommandService.getByDevice(deviceId),
    enabled: !!deviceId,
    refetchInterval: 3000, // Refetch every 10 seconds
  });
};

export const useCreateCommand = () => {
  return useMutation({
    mutationFn: ({ deviceId, data }: { deviceId: string; data: DeviceCommandRequest }) =>
      deviceCommandService.createDeviceCommand(deviceId, data),
  });
};