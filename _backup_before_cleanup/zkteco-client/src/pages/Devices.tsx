// ==========================================
// src/pages/Devices.tsx
// ==========================================
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/button'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { EmptyState } from '@/components/EmptyState'
import { useDevices } from '@/hooks/useDevices'
import { Monitor, Plus } from 'lucide-react'
import { CreateDeviceDialog } from '@/components/dialogs/CreateDeviceDialog'
import { DevicesContent, DeviceInfoDialog } from '@/components/devices'
import { DeviceProvider, useDeviceContext } from '@/contexts/DeviceContext'

const DevicesContent_Internal = () => {
  const { data: devices, isFetching, isError } = useDevices()
  
  // Get all state and actions from context
  const {
    openCreateDialog,
    openInfoDialog,
  } = useDeviceContext()

  const handleShowInfo = (id: string) => {
    const device = devices?.find((d) => d.id === id)
    openInfoDialog(id, device?.deviceName)
  }

  if (isError) {
    return (
      <EmptyState
        icon={Monitor}
        title="Error loading devices"
        description="There was an error loading your devices. Please try again later."
      />
    )
  }

  if (isFetching && !devices) {
    return <LoadingSpinner />
  }

  return (
    <div>
      <PageHeader
        title="Devices"
        description="Mange your Biometric devices."
        action={
          <Button onClick={openCreateDialog}>
            <Plus className="w-4 h-4 mr-2" />
            Add Device
          </Button>
        }
      />

      <DevicesContent
        devices={devices}
        onShowInfo={handleShowInfo}
      />

      <CreateDeviceDialog />
      <DeviceInfoDialog />
    </div>
  )
}

// Wrap with DeviceProvider
export const Devices = () => {
  return (
    <DeviceProvider>
      <DevicesContent_Internal />
    </DeviceProvider>
  )
}
