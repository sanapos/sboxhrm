import { useState } from "react";
import { TodayShiftCard } from "./TodayShiftCard";
import { NextShiftCard } from "./NextShiftCard";
import { CurrentAttendanceCard } from "./CurrentAttendanceCard";
import { AttendanceStatsCard } from "./AttendanceStatsCard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Calendar, RefreshCw } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { EmployeeDashboardData } from "@/types/employee-dashboard";

interface EmployeeDashboardProps {
  data?: EmployeeDashboardData;
  isLoading?: boolean;
  onPeriodChange?: (period: 'week' | 'month' | 'year') => void;
  onRefresh?: () => void;
}

export const EmployeeDashboard = ({
  data,
  isLoading = false,
  onPeriodChange,
  onRefresh,
}: EmployeeDashboardProps) => {
  const [selectedPeriod, setSelectedPeriod] = useState<'week' | 'month' | 'year'>('month');

  const handlePeriodChange = (value: string) => {
    const period = value as 'week' | 'month' | 'year';
    setSelectedPeriod(period);
    onPeriodChange?.(period);
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold tracking-tight">My Dashboard</h2>
          <p className="text-muted-foreground">
            Track your shifts, attendance, and performance
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Select value={selectedPeriod} onValueChange={handlePeriodChange}>
            <SelectTrigger className="w-[150px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="week">This Week</SelectItem>
              <SelectItem value="month">This Month</SelectItem>
              <SelectItem value="year">This Year</SelectItem>
            </SelectContent>
          </Select>
          {onRefresh && (
            <Button
              variant="outline"
              size="icon"
              onClick={onRefresh}
              disabled={isLoading}
            >
              <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
            </Button>
          )}
        </div>
      </div>

      {/* Shift Cards Row */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <TodayShiftCard shift={data?.todayShift || null} isLoading={isLoading} />
        <NextShiftCard shift={data?.nextShift || null} isLoading={isLoading} />
        <CurrentAttendanceCard 
          attendance={data?.currentAttendance || null} 
          isLoading={isLoading} 
        />
      </div>

      {/* Stats Card */}
      <div className="grid gap-4">
        <AttendanceStatsCard 
          stats={data?.attendanceStats || null} 
          isLoading={isLoading} 
        />
      </div>

      {/* Quick Actions */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Quick Actions</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" className="flex items-center gap-2">
              <Calendar className="h-4 w-4" />
              Request Time Off
            </Button>
            <Button variant="outline" className="flex items-center gap-2">
              <Calendar className="h-4 w-4" />
              View My Shifts
            </Button>
            <Button variant="outline" className="flex items-center gap-2">
              <Calendar className="h-4 w-4" />
              View Attendance History
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
