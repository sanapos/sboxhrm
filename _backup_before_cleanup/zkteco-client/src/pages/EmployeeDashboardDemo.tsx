import { EmployeeDashboard } from "@/components/employee-dashboard";
import { EmployeeDashboardData } from "@/types/employee-dashboard";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

// Demo component showing different states of the Employee Dashboard

export const EmployeeDashboardDemo = () => {
  // Mock data with active shift and checked-in status
  const mockDataActive: EmployeeDashboardData = {
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
      startTime: new Date(Date.now() + 86400000).toISOString().split('T')[0] + "T10:00:00",
      endTime: new Date(Date.now() + 86400000).toISOString().split('T')[0] + "T18:00:00",
      description: "Regular shift - Branch Office",
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
      period: 'month',
    },
  };

  // Mock data with completed shift
  const mockDataCompleted: EmployeeDashboardData = {
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
      checkInTime: new Date().toISOString().split('T')[0] + "T08:55:00",
      checkOutTime: new Date().toISOString().split('T')[0] + "T16:50:00",
      workHours: 7.92,
      status: 'checked-out',
      isLate: false,
      isEarlyOut: true,
      earlyOutMinutes: 10,
    },
    attendanceStats: {
      totalWorkDays: 22,
      presentDays: 22,
      absentDays: 0,
      lateCheckIns: 0,
      earlyCheckOuts: 2,
      attendanceRate: 100,
      punctualityRate: 95.45,
      averageWorkHours: "8.1",
      period: 'month',
    },
  };

  // Mock data with no shifts or attendance
  const mockDataEmpty: EmployeeDashboardData = {
    todayShift: null,
    nextShift: null,
    currentAttendance: null,
    attendanceStats: {
      totalWorkDays: 0,
      presentDays: 0,
      absentDays: 0,
      lateCheckIns: 0,
      earlyCheckOuts: 0,
      attendanceRate: 0,
      punctualityRate: 0,
      averageWorkHours: "0",
      period: 'month',
    },
  };

  return (
    <div className="container mx-auto p-6">
      <h1 className="text-4xl font-bold mb-6">Employee Dashboard Demo</h1>
      
      <Tabs defaultValue="active" className="w-full">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="active">Active Shift (Late)</TabsTrigger>
          <TabsTrigger value="completed">Completed Shift (Early Out)</TabsTrigger>
          <TabsTrigger value="empty">No Data</TabsTrigger>
        </TabsList>
        
        <TabsContent value="active" className="mt-6">
          <EmployeeDashboard data={mockDataActive} />
        </TabsContent>
        
        <TabsContent value="completed" className="mt-6">
          <EmployeeDashboard data={mockDataCompleted} />
        </TabsContent>
        
        <TabsContent value="empty" className="mt-6">
          <EmployeeDashboard data={mockDataEmpty} />
        </TabsContent>
      </Tabs>
    </div>
  );
};

export default EmployeeDashboardDemo;
