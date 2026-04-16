
// ==========================================
// src/pages/Settings.tsx
// ==========================================
import { PageHeader } from '@/components/PageHeader'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Settings as SettingsIcon } from 'lucide-react'

export const Settings = () => {
  return (
    <div>
      <PageHeader
        title="Settings"
        description="Configure system settings"
      />

      <Card>
        <CardHeader>
          <CardTitle>System Settings</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-center py-12">
            <SettingsIcon className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
            <p className="text-muted-foreground">
              Settings feature coming soon...
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}