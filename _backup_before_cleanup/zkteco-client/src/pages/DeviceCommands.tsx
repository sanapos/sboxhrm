// ==========================================
// src/pages/DeviceCommands.tsx
// ==========================================
import { useState, useEffect } from 'react'
import { PageHeader } from '@/components/PageHeader'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { EmptyState } from '@/components/EmptyState'
import { useDevices } from '@/hooks/useDevices'
import { CommandCenter, CommandHistory } from '@/components/device-commands'
import { Terminal, AlertCircle } from 'lucide-react'
import { useGetDeviceCommands } from '@/hooks/useDeviceCommands'
import { Alert, AlertDescription } from '@/components/ui/alert'

export const DeviceCommands = () => {
  const { data: devices, isLoading: devicesLoading } = useDevices()
  const [selectedDeviceId, setSelectedDeviceId] = useState<string>('')
  const { data: commands, isFetching: commandsLoading, refetch } = useGetDeviceCommands(selectedDeviceId)

  // Auto-select first device
  useEffect(() => {
    if (devices && devices.length > 0 && !selectedDeviceId) {
      setSelectedDeviceId(devices[0].id)
    }
  }, [devices, selectedDeviceId])

  // Get selected device to check if it's active
  const selectedDevice = devices?.find(d => d.id === selectedDeviceId)
  const isDeviceInactive = selectedDevice && !selectedDevice.isActive

  if (devicesLoading) {
    return <LoadingSpinner />
  }

  if (!devices || devices.length === 0) {
    return (
      <EmptyState
        icon={Terminal}
        title="No devices available"
        description="You need to add a device before sending commands."
      />
    )
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Commands"
        description="Send commands and monitor their execution status"
      />

      {isDeviceInactive && (
        <Alert variant="destructive">
          <AlertCircle className="h-4 w-4" />
          <AlertDescription>
            This device is currently inactive. All command actions are disabled. 
            Please contact an administrator to activate this device.
          </AlertDescription>
        </Alert>
      )}

      <CommandCenter
        devices={devices}
        selectedDeviceId={selectedDeviceId}
        onDeviceChange={setSelectedDeviceId}
        onRefresh={refetch}
        isDeviceInactive={isDeviceInactive}
      />

      <CommandHistory
        commands={commands}
        isLoading={commandsLoading}
        selectedDeviceId={selectedDeviceId}
      />
    </div>
  )
}
