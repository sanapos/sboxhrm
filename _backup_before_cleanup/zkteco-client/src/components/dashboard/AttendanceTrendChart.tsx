import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts'
import { Skeleton } from '@/components/ui/skeleton'
import { format } from 'date-fns'
import { AttendanceTrend } from '@/types/dashboard'

interface AttendanceTrendChartProps {
  data?: AttendanceTrend[]
  isLoading?: boolean
}

export const AttendanceTrendChart = ({
  data,
  isLoading,
}: AttendanceTrendChartProps) => {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Attendance Trends</CardTitle>
        </CardHeader>
        <CardContent>
          <Skeleton className="h-[300px] w-full" />
        </CardContent>
      </Card>
    )
  }

  if (!data || data.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Attendance Trends</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-[300px] text-muted-foreground">
            No trend data available
          </div>
        </CardContent>
      </Card>
    )
  }

  const chartData = data.map((item) => ({
    date: format(new Date(item.date), 'MMM dd'),
    'Check-ins': item.totalCheckIns,
    'Check-outs': item.totalCheckOuts,
    'Late Arrivals': item.lateArrivals,
    'Attendance Rate': item.attendanceRate,
  }))

  return (
    <Card>
      <CardHeader>
        <CardTitle>Attendance Trends</CardTitle>
        <p className="text-sm text-muted-foreground">
          Daily attendance patterns over the selected period
        </p>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis
              dataKey="date"
              tick={{ fontSize: 12 }}
              tickLine={false}
            />
            <YAxis tick={{ fontSize: 12 }} tickLine={false} />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(var(--background))',
                border: '1px solid hsl(var(--border))',
                borderRadius: '6px',
              }}
            />
            <Legend />
            <Line
              type="monotone"
              dataKey="Check-ins"
              stroke="hsl(var(--primary))"
              strokeWidth={2}
              dot={false}
            />
            <Line
              type="monotone"
              dataKey="Check-outs"
              stroke="hsl(var(--chart-2))"
              strokeWidth={2}
              dot={false}
            />
            <Line
              type="monotone"
              dataKey="Late Arrivals"
              stroke="hsl(var(--destructive))"
              strokeWidth={2}
              dot={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
