// ==========================================
// src/components/device-commands/CommandHistoryTable.tsx
// ==========================================
import { DeviceCommand } from '@/types'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { getStatusBadge, formatDate } from './commandUtils.tsx'
import { DeviceCommandTypes } from '@/types/device.ts'

interface CommandHistoryTableProps {
  commands: DeviceCommand[]
}

export const CommandHistoryTable = ({ commands }: CommandHistoryTableProps) => {
  return (
    <div className="rounded-md border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Command</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Created</TableHead>
            <TableHead>Sent</TableHead>
            <TableHead>Completed</TableHead>
            <TableHead>Message</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {commands.map((command: DeviceCommand) => (
            <TableRow key={command.id}>
              <TableCell className="font-medium">
                {DeviceCommandTypes[command.commandType]}
              </TableCell>
              <TableCell>
                {getStatusBadge(command.status)}
              </TableCell>
              <TableCell className="text-muted-foreground text-sm">
                {formatDate(command.createdAt)}
              </TableCell>
              <TableCell className="text-muted-foreground text-sm">
                {formatDate(command.sentAt)}
              </TableCell>
              <TableCell className="text-muted-foreground text-sm">
                {formatDate(command.completedAt)}
              </TableCell>
              <TableCell className={`${command.status === 2 ? 'text-green-600' : 'text-red-600'} text-sm`}>
                {command.errorMessage || '-'}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
