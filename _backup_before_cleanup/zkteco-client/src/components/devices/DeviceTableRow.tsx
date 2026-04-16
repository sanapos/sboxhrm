import { Button } from '@/components/ui/button'
import { TableCell, TableRow } from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Monitor, Trash2, InfoIcon } from 'lucide-react'
import { format } from 'date-fns'
import { Device } from '@/types'
import { DeviceSettingsDropdown } from './DeviceSettingsDropdown'
import { useDeviceContext } from '@/contexts/DeviceContext'

export const DeviceTableRow = ({
  device,
  onShowInfo
}: {
  device: Device
  onShowInfo?: (id: string) => void
}) => {
  const {
    handleDelete,
    handleToggleActive,
  } = useDeviceContext()
  return (
    <TableRow key={device.id}>
      <TableCell className="font-medium">{device.deviceName}</TableCell>
      <TableCell className="text-muted-foreground">
        {device.serialNumber}
      </TableCell>
      <TableCell>{device.location || '-'}</TableCell>
      <TableCell>{device.description || '-'}</TableCell>
      <TableCell>
        <Badge variant={device.isActive ? 'default' : 'secondary'}>
          {device.isActive ? 'Active' : 'Inactive'}
        </Badge>
      </TableCell>
      <TableCell className="text-muted-foreground">
        {device.lastOnline
          ? format(new Date(device.lastOnline), 'MMM dd, yyyy HH:mm')
          : 'Never'}
      </TableCell>
      <TableCell className="text-right">
        <div className="flex justify-end gap-2">
          <DeviceSettingsDropdown
            deviceId={device.id}
          />
          <Button
            variant="ghost"
            size="icon"
            onClick={() => onShowInfo?.(device.id)}
          >
            <InfoIcon className="w-4 h-4" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => handleToggleActive(device.id)}
          >
            <Monitor
              className={`w-4 h-4 ${
                device.isActive ? 'text-green-500' : 'text-gray-500'
              }`}
            />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => handleDelete(device.id)}
          >
            <Trash2 className="w-4 h-4 text-destructive" />
          </Button>
        </div>
      </TableCell>
    </TableRow>
  )
}
