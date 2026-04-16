import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { EmptyState } from '@/components/EmptyState'
import { DevicesTable } from './DevicesTable'
import { Monitor, Plus } from 'lucide-react'
import { Device } from '@/types'
import { useDeviceContext } from '@/contexts/DeviceContext'

interface DevicesContentProps {
  devices: Device[] | undefined
  onShowInfo?: (id: string) => void
}

export const DevicesContent = ({
  devices,
  onShowInfo,
}: DevicesContentProps) => {
  const {
    openCreateDialog,
  } = useDeviceContext()
  
  return (
    <Card>
      <CardContent className="p-0">
        {!devices || devices.length === 0 ? (
          <EmptyState
            icon={Monitor}
            title="No devices found"
            description="Get started by adding your own device."
            action={
              <Button onClick={openCreateDialog}>
                <Plus className="w-4 h-4 mr-2" />
                Add Device
              </Button>
            }
          />
        ) : (
          <DevicesTable
            devices={devices}
            onShowInfo={onShowInfo}
          />
        )}
      </CardContent>
    </Card>
  )
}
