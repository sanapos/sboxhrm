import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AttendanceRate } from '@/types/manager-dashboard';
import { Users, CheckCircle2, Clock, XCircle, Coffee } from 'lucide-react';

interface AttendanceStatsCardsProps {
  data: AttendanceRate;
}

export const AttendanceStatsCards = ({ data }: AttendanceStatsCardsProps) => {
  const stats = [
    {
      title: 'Total Employees',
      value: data.totalEmployeesWithShift,
      icon: Users,
      description: 'With shift today',
      color: 'text-blue-600',
      bgColor: 'bg-blue-100',
    },
    {
      title: 'Present & On Time',
      value: data.presentEmployees,
      icon: CheckCircle2,
      description: `${data.punctualityPercentage.toFixed(1)}% punctuality`,
      color: 'text-green-600',
      bgColor: 'bg-green-100',
    },
    {
      title: 'Late Arrivals',
      value: data.lateEmployees,
      icon: Clock,
      description: 'Checked in late',
      color: 'text-yellow-600',
      bgColor: 'bg-yellow-100',
    },
    {
      title: 'Absent',
      value: data.absentEmployees,
      icon: XCircle,
      description: 'No check-in yet',
      color: 'text-red-600',
      bgColor: 'bg-red-100',
    },
    {
      title: 'On Leave',
      value: data.onLeaveEmployees,
      icon: Coffee,
      description: 'Approved leaves',
      color: 'text-purple-600',
      bgColor: 'bg-purple-100',
    },
  ];

  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-5">
      {stats.map((stat) => (
        <Card key={stat.title}>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">{stat.title}</CardTitle>
            <stat.icon className={`h-4 w-4 ${stat.color}`} />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stat.value}</div>
            <p className="text-xs text-muted-foreground">{stat.description}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
};
