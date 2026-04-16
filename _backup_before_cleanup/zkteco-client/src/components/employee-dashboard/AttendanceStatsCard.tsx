import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BarChart3, TrendingDown, TrendingUp, Clock } from "lucide-react";
import { AttendanceStats } from "@/types/employee-dashboard";
import { Badge } from "@/components/ui/badge";

interface AttendanceStatsCardProps {
  stats: AttendanceStats | null;
  isLoading?: boolean;
}

export const AttendanceStatsCard = ({ stats, isLoading }: AttendanceStatsCardProps) => {
  if (isLoading) {
    return (
      <Card className="col-span-2">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Attendance Statistics</CardTitle>
          <BarChart3 className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-32">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!stats) {
    return (
      <Card className="col-span-2">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium">Attendance Statistics</CardTitle>
          <BarChart3 className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">No statistics available</div>
        </CardContent>
      </Card>
    );
  }

  const getPeriodLabel = () => {
    switch (stats.period) {
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      case 'year':
        return 'This Year';
      default:
        return 'Period';
    }
  };

  return (
    <Card className="col-span-2">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">
          Attendance Statistics - {getPeriodLabel()}
        </CardTitle>
        <BarChart3 className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {/* Attendance Rate */}
          <div className="space-y-2">
            <div className="text-xs text-muted-foreground">Attendance Rate</div>
            <div className="flex items-center gap-2">
              <div className="text-2xl font-bold">{stats.attendanceRate.toFixed(1)}%</div>
              {stats.attendanceRate >= 90 ? (
                <TrendingUp className="h-4 w-4 text-green-600" />
              ) : (
                <TrendingDown className="h-4 w-4 text-orange-600" />
              )}
            </div>
            <div className="text-xs text-muted-foreground">
              {stats.presentDays}/{stats.totalWorkDays} days present
            </div>
          </div>

          {/* Punctuality Rate */}
          <div className="space-y-2">
            <div className="text-xs text-muted-foreground">Punctuality Rate</div>
            <div className="flex items-center gap-2">
              <div className="text-2xl font-bold">{stats.punctualityRate.toFixed(1)}%</div>
              {stats.punctualityRate >= 90 ? (
                <TrendingUp className="h-4 w-4 text-green-600" />
              ) : (
                <TrendingDown className="h-4 w-4 text-orange-600" />
              )}
            </div>
            <div className="text-xs text-muted-foreground">
              On-time arrivals
            </div>
          </div>

          {/* Late Check-ins */}
          <div className="space-y-2">
            <div className="text-xs text-muted-foreground">Late Check-ins</div>
            <div className="flex items-center gap-2">
              <div className="text-2xl font-bold text-orange-600">{stats.lateCheckIns}</div>
              <Badge variant="outline" className="text-xs">
                {stats.totalWorkDays > 0 
                  ? ((stats.lateCheckIns / stats.totalWorkDays) * 100).toFixed(0)
                  : 0}%
              </Badge>
            </div>
            <div className="text-xs text-muted-foreground">
              Times late
            </div>
          </div>

          {/* Early Check-outs */}
          <div className="space-y-2">
            <div className="text-xs text-muted-foreground">Early Check-outs</div>
            <div className="flex items-center gap-2">
              <div className="text-2xl font-bold text-red-600">{stats.earlyCheckOuts}</div>
              <Badge variant="outline" className="text-xs">
                {stats.totalWorkDays > 0 
                  ? ((stats.earlyCheckOuts / stats.totalWorkDays) * 100).toFixed(0)
                  : 0}%
              </Badge>
            </div>
            <div className="text-xs text-muted-foreground">
              Times early
            </div>
          </div>
        </div>

        {/* Additional Stats Row */}
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mt-4 pt-4 border-t">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Total Days:</span>
            <span className="font-semibold">{stats.totalWorkDays}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Absent:</span>
            <span className="font-semibold text-red-600">{stats.absentDays}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Avg. Hours:</span>
            <div className="flex items-center gap-1">
              <Clock className="h-3 w-3 text-muted-foreground" />
              <span className="font-semibold">{stats.averageWorkHours}</span>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
