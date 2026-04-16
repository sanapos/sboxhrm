import {
  Table,
  TableBody,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { DeviceTableRow } from './DeviceTableRow'
import { Device } from '@/types'

interface DevicesTableProps {
  devices: Device[]
  onShowInfo?: (id: string) => void
}

export const DevicesTable = ({
  devices,
  onShowInfo,
}: DevicesTableProps) => {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Device Name</TableHead>
          <TableHead>Serial Number</TableHead>
          <TableHead>Location</TableHead>
          <TableHead>Description</TableHead>
          <TableHead>Is Active</TableHead>
          <TableHead>Last Online</TableHead>
          <TableHead className="text-right">Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {devices.map((device) => (
          <DeviceTableRow
            key={device.id}
            device={device}
            onShowInfo={onShowInfo}
          />
        ))}
      </TableBody>
    </Table>
  )
}
