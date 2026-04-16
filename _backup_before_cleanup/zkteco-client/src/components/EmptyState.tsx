
// ==========================================
// src/components/EmptyState.tsx
// ==========================================
import { LucideIcon } from 'lucide-react'

interface EmptyStateProps {
  icon: LucideIcon
  title: string
  description: string
  action?: React.ReactNode
}

export const EmptyState = ({ 
  icon: Icon, 
  title, 
  description, 
  action 
}: EmptyStateProps) => {
  return (
    <div className="flex flex-col items-center justify-center h-full py-12">
      <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mb-4">
        <Icon className="w-8 h-8 text-muted-foreground" />
      </div>
      <h3 className="text-lg font-semibold mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground mb-6 text-center max-w-md">
        {description}
      </p>
      {action}
    </div>
  )
}
