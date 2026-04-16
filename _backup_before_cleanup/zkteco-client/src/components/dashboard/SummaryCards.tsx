import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Monitor, Users, Clock, AlertCircle, TrendingUp, TrendingDown } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { DashboardSummary } from '@/types/dashboard'

interface SummaryCardsProps {
  summary?: DashboardSummary
  isLoading?: boolean
}

export const SummaryCards = ({ summary, isLoading }: SummaryCardsProps) => {
  if (isLoading) {
    return (
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {[...Array(4)].map((_, i) => (
          <Card key={i}>
            <CardHeader className="pb-2">
              <Skeleton className="h-4 w-24" />
            </CardHeader>
            <CardContent>
              <Skeleton className="h-8 w-16 mb-2" />
              <Skeleton className="h-4 w-32" />
            </CardContent>
          </Card>
        ))}
      </div>
    )
  }

  if (!summary) return null

  const stats = [
    {
      title: 'Total Employees',
      value: summary.totalEmployees,
      icon: Users,
      description: `${summary.activeEmployees} active, ${summary.inactiveEmployees} inactive`,
      trend: summary.activeEmployees > summary.inactiveEmployees ? 'up' : 'down',
    },
    {
      title: 'Devices',
      value: summary.totalDevices,
      icon: Monitor,
      badges: [
        { label: `${summary.onlineDevices} Online`, variant: 'success' as const },
        { label: `${summary.offlineDevices} Offline`, variant: 'secondary' as const },
      ],
    },
    {
      title: "Today's Attendance",
      value: summary.todayCheckIns,
      icon: Clock,
      description: `${summary.todayCheckOuts} check-outs`,
      rate: `${summary.averageAttendanceRate.toFixed(1)}% rate`,
    },
    {
      title: "Today's Issues",
      value: summary.todayLateArrivals + summary.todayAbsences,
      icon: AlertCircle,
      badges: [
        { label: `${summary.todayLateArrivals} Late`, variant: 'warning' as const },
        { label: `${summary.todayAbsences} Absent`, variant: 'destructive' as const },
      ],
    },
  ]

  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
      {stats.map((stat) => (
        <Card key={stat.title}>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">{stat.title}</CardTitle>
            <stat.icon className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="flex items-baseline gap-2">
              <div className="text-2xl font-bold">{stat.value}</div>
              {stat.trend && (
                stat.trend === 'up' ? (
                  <TrendingUp className="w-4 h-4 text-green-500" />
                ) : (
                  <TrendingDown className="w-4 h-4 text-red-500" />
                )
              )}
            </div>
            {stat.description && (
              <p className="text-xs text-muted-foreground mt-2">
                {stat.description}
              </p>
            )}
            {stat.rate && (
              <p className="text-xs text-green-600 font-medium mt-2">
                {stat.rate}
              </p>
            )}
            {stat.badges && (
              <div className="flex items-center gap-2 mt-2 flex-wrap">
                {stat.badges.map((badge) => (
                  <Badge key={badge.label} variant={badge.variant}>
                    {badge.label}
                  </Badge>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
