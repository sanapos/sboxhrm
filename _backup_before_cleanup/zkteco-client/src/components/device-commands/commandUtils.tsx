// ==========================================
// src/components/device-commands/commandUtils.tsx
// ==========================================
import { Badge } from '@/components/ui/badge'
import { formatDistanceToNow } from 'date-fns'

export const getStatusBadge = (status: number) => {
  const statusMap: Record<number, { variant: 'default' | 'secondary' | 'destructive' | 'outline', label: string, className?: string }> = {
    0: { variant: 'secondary', label: 'Created', className: 'bg-blue-500' },
    1: { variant: 'outline', label: 'Sent', className: 'bg-yellow-500' },
    2: { variant: 'default', label: 'Success', className: 'bg-green-500' },
    3: { variant: 'destructive', label: 'Failed', className: 'bg-red-500' },
  }
  
  const statusInfo = statusMap[status] || { variant: 'outline', label: status }
  return <Badge variant={statusInfo.variant} className={statusInfo.className}>{statusInfo.label}</Badge>
}

export const formatDate = (dateString?: string) => {
  if (!dateString) return '-'
  try {
    return formatDistanceToNow(new Date(dateString), { addSuffix: true })
  } catch {
    return dateString
  }
}
