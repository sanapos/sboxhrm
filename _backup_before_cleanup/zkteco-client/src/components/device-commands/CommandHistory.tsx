// ==========================================
// src/components/device-commands/CommandHistory.tsx
// ==========================================
import { DeviceCommand } from '@/types'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { EmptyState } from '@/components/EmptyState'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Clock } from 'lucide-react'
import { CommandHistoryTable } from './CommandHistoryTable'

interface CommandHistoryProps {
  commands: DeviceCommand[] | undefined
  isLoading: boolean
  selectedDeviceId: string
}

export const CommandHistory = ({ commands, isLoading, selectedDeviceId }: CommandHistoryProps) => {
  if (!selectedDeviceId) {
    return null
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Command History</CardTitle>
        <CardDescription>
          Recent commands sent to this device
        </CardDescription>
      </CardHeader>
      <CardContent>
        {isLoading && !commands ? (
          <LoadingSpinner />
        ) : !commands || commands.length === 0 ? (
          <EmptyState
            icon={Clock}
            title="No commands yet"
            description="Send a command to see it appear here"
          />
        ) : (
          <CommandHistoryTable commands={commands} />
        )}
      </CardContent>
    </Card>
  )
}
