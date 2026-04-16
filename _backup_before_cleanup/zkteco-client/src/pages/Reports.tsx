
// ==========================================
// src/pages/Reports.tsx
// ==========================================
import { PageHeader } from '@/components/PageHeader'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { FileText } from 'lucide-react'

export const Reports = () => {
  return (
    <div>
      <PageHeader
        title="Reports"
        description="Generate and view attendance reports"
      />

      <Card>
        <CardHeader>
          <CardTitle>Reports Feature</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-center py-12">
            <FileText className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
            <p className="text-muted-foreground">
              Reports feature coming soon...
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}