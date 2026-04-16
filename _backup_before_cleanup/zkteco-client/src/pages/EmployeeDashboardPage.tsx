import { useState } from "react";
import { EmployeeDashboard } from "@/components/employee-dashboard";
import { EmployeeDashboardData } from "@/types/employee-dashboard";

// This is a sample page showing how to use the EmployeeDashboard component
// Replace this with actual API calls to fetch real data

export const EmployeeDashboardPage = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [period, setPeriod] = useState<'week' | 'month' | 'year'>('month');

  // Mock data - Replace with actual API call
  const mockData: EmployeeDashboardData = {
    todayShift: {
      id: "1",
      startTime: new Date().toISOString().split('T')[0] + "T09:00:00",
      endTime: new Date().toISOString().split('T')[0] + "T17:00:00",
      description: "Regular shift - Main Office",
      status: 1,
      totalHours: 8,
      isToday: true,
    },
    nextShift: {
      id: "2",
      startTime: new Date(Date.now() + 86400000).toISOString().split('T')[0] + "T09:00:00",
      endTime: new Date(Date.now() + 86400000).toISOString().split('T')[0] + "T17:00:00",
      description: "Regular shift - Main Office",
      status: 0,
      totalHours: 8,
      isToday: false,
    },
    currentAttendance: {
      id: "1",
      checkInTime: new Date().toISOString().split('T')[0] + "T09:15:00",
      checkOutTime: null,
      workHours: 4.5,
      status: 'checked-in',
      isLate: true,
      isEarlyOut: false,
      lateMinutes: 15,
    },
    attendanceStats: {
      totalWorkDays: 22,
      presentDays: 20,
      absentDays: 2,
      lateCheckIns: 3,
      earlyCheckOuts: 1,
      attendanceRate: 90.91,
      punctualityRate: 85.0,
      averageWorkHours: "8.2",
      period: period,
    },
  };

  const handlePeriodChange = (newPeriod: 'week' | 'month' | 'year') => {
    setPeriod(newPeriod);
    // TODO: Fetch data for the new period
    console.log('Period changed to:', newPeriod);
  };

  const handleRefresh = () => {
    setIsLoading(true);
    // TODO: Fetch fresh data
    setTimeout(() => setIsLoading(false), 1000);
  };

  return (
    <div className="container mx-auto p-6">
      <EmployeeDashboard
        data={mockData}
        isLoading={isLoading}
        onPeriodChange={handlePeriodChange}
        onRefresh={handleRefresh}
      />
    </div>
  );
};

export default EmployeeDashboardPage;
