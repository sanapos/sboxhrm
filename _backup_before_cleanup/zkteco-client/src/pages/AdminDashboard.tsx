// ==========================================
// src/pages/AdminDashboard.tsx
// ==========================================
import { PageHeader } from '@/components/PageHeader'
import { LoadingSpinner } from '@/components/LoadingSpinner'
import { useDashboardSummary, useAttendanceTrends, useTopPerformers, useLateEmployees, useDepartmentStats, useDeviceStatus } from '@/hooks/useDashboard'
import { SummaryCards } from '@/components/dashboard/SummaryCards'
import { AttendanceTrendChart } from '@/components/dashboard/AttendanceTrendChart'
import { TopPerformersList } from '@/components/dashboard/TopPerformersList'
import { LateEmployeesList } from '@/components/dashboard/LateEmployeesList'
import { DepartmentStatsCard } from '@/components/dashboard/DepartmentStatsCard'
import { DeviceStatusList } from '@/components/dashboard/DeviceStatusList'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Button } from '@/components/ui/button'
import { RefreshCw, Settings, Users, MonitorSmartphone } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useNavigate } from 'react-router-dom'

export const AdminDashboard = () => {
  const navigate = useNavigate()
  const trendDays = 30
  const performerCount = 10

  // Fetch all dashboard data
  const { data: summary, isLoading: summaryLoading, refetch: refetchSummary } = useDashboardSummary()
  const { data: trends, isLoading: trendsLoading } = useAttendanceTrends(trendDays)
  const { data: topPerformers, isLoading: performersLoading } = useTopPerformers({ count: performerCount })
  const { data: lateEmployees, isLoading: lateLoading } = useLateEmployees({ count: performerCount })
  const { data: departments, isLoading: deptLoading } = useDepartmentStats()
  const { data: devices, isLoading: devicesLoading } = useDeviceStatus()

  const isLoading = summaryLoading

  if (isLoading) {
    return <LoadingSpinner />
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <PageHeader
          title="Admin Dashboard"
          description="Complete system overview and management controls"
        />
        <Button
          variant="outline"
          size="sm"
          onClick={() => refetchSummary()}
          className="gap-2"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </Button>
      </div>

      {/* Quick Admin Actions */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card className="cursor-pointer hover:bg-accent" onClick={() => navigate('/employees')}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Manage Users</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">
              Add, edit, or remove employee accounts
            </p>
          </CardContent>
        </Card>

        <Card className="cursor-pointer hover:bg-accent" onClick={() => navigate('/devices')}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Manage Devices</CardTitle>
            <MonitorSmartphone className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">
              Configure and monitor attendance devices
            </p>
          </CardContent>
        </Card>

        <Card className="cursor-pointer hover:bg-accent" onClick={() => navigate('/settings')}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">System Settings</CardTitle>
            <Settings className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">
              Configure system preferences and policies
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Summary Cards */}
      <SummaryCards summary={summary} isLoading={summaryLoading} />

      {/* Tabs for Different Views */}
      <Tabs defaultValue="overview" className="space-y-4">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="performance">Performance</TabsTrigger>
          <TabsTrigger value="departments">Departments</TabsTrigger>
          <TabsTrigger value="devices">Devices</TabsTrigger>
        </TabsList>

        {/* Overview Tab */}
        <TabsContent value="overview" className="space-y-4">
          <div className="grid gap-4 md:grid-cols-2">
            <AttendanceTrendChart data={trends} isLoading={trendsLoading} />
            <DeviceStatusList devices={devices} isLoading={devicesLoading} />
          </div>
          
          <DepartmentStatsCard departments={departments} isLoading={deptLoading} />
        </TabsContent>

        {/* Performance Tab */}
        <TabsContent value="performance" className="space-y-4">
          <div className="grid gap-4 md:grid-cols-2">
            <TopPerformersList performers={topPerformers} isLoading={performersLoading} />
            <LateEmployeesList employees={lateEmployees} isLoading={lateLoading} />
          </div>
        </TabsContent>

        {/* Departments Tab */}
        <TabsContent value="departments" className="space-y-4">
          <DepartmentStatsCard departments={departments} isLoading={deptLoading} />
        </TabsContent>

        {/* Devices Tab */}
        <TabsContent value="devices" className="space-y-4">
          <DeviceStatusList devices={devices} isLoading={devicesLoading} />
        </TabsContent>
      </Tabs>
    </div>
  )
}
