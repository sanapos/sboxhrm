
// ==========================================
// src/App.tsx
// ==========================================
import { Routes, Route, Navigate } from 'react-router-dom'
import { ProtectedRoute } from './components/ProtectedRoute'
import { RoleProtectedRoute } from './components/RoleProtectedRoute'
import { RouteErrorBoundary } from './components/RouteErrorBoundary'
import { MainLayout } from './layouts/MainLayout'
import { Login } from './pages/auth/Login'
import { Dashboard } from './pages/Dashboard'
import { Devices } from './pages/Devices'
import { DeviceUsers } from './pages/DeviceUsers'
import { Attendance } from './pages/Attendance'
import { Reports } from './pages/Reports'
import { Settings } from './pages/Settings'
import { DeviceCommands } from './pages/DeviceCommands'
import { ForgotPassword } from './pages/auth/ForgotPassword'
import { ResetPassword } from './pages/auth/ResetPassword'
import { MyShifts } from './pages/MyShifts'
import { Leaves } from './pages/Leaves'
import { ShiftManagement } from './pages/ShiftManagement'
import { Profile } from './pages/Profile'
import { UserRole } from './constants/roles'
import EmployeeDashboardDemo from './pages/EmployeeDashboardDemo'
import { MonthlyAttendanceSummary } from './pages/MonthlyAttendanceSummary'
import { Benefits } from './pages/Benifits'
import { Payslips } from './pages/Payslips'
import Employees from './pages/Employees'
import GoogleSheetsPage from './pages/GoogleSheetsPage'
// HRM Features
import AdvanceRequests from './pages/AdvanceRequests'
import AttendanceCorrections from './pages/AttendanceCorrections'
import Notifications from './pages/Notifications'
import HrmSettings from './pages/HrmSettings'

function App() {
  return (
    <RouteErrorBoundary>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/forgot-password" element={<ForgotPassword />} />
        <Route path="/reset-password" element={<ResetPassword />} />
        <Route path="/demo-dashboard" element={<EmployeeDashboardDemo />} />
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <MainLayout />
            </ProtectedRoute>
          }
        >
        <Route index element={<Navigate to="/dashboard" replace />} />
        
        {/* Routes accessible by all authenticated users */}
        <Route path="dashboard" element={<Dashboard />} />
        <Route path="settings" element={<Settings />} />
        <Route path="profile" element={<Profile />} />
        
        {/* Employee can only access attendance (their own) */}
        <Route path="attendance" element={<Attendance />} />
        <Route path="attendance-summary" element={<MonthlyAttendanceSummary />} />
        
        {/* Employee can access their shifts */}
        <Route
          path="my-shifts"
          element={
            <RoleProtectedRoute requiredRole={UserRole.EMPLOYEE}>
              <MyShifts />
            </RoleProtectedRoute>
          }
        />

        <Route
          path="leaves"
          element={
            <RoleProtectedRoute requiredRole={UserRole.EMPLOYEE}>
              <Leaves />
            </RoleProtectedRoute>
          }
        />

        {/* Payslips - accessible by all authenticated users */}
        <Route path="payslips" element={<Payslips />} />
        
        {/* Manager and Admin only routes */}
        
        <Route
          path="shifts"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <ShiftManagement />
            </RoleProtectedRoute>
          }
          
        />
        <Route
          path="devices"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <Devices />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="device-commands"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <DeviceCommands />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="device-users"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <DeviceUsers />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="reports"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <Reports />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="salary-profiles"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <Benefits />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="employees"
          element={
            <RoleProtectedRoute requiredRole={UserRole.MANAGER}>
              <Employees />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="google-sheets"
          element={
            <RoleProtectedRoute requiredRole={UserRole.ADMIN}>
              <GoogleSheetsPage />
            </RoleProtectedRoute>
          }
        />

        {/* HRM Features - All authenticated users */}
        <Route
          path="advance-requests"
          element={
            <RoleProtectedRoute requiredRole={UserRole.EMPLOYEE}>
              <AdvanceRequests />
            </RoleProtectedRoute>
          }
        />
        <Route
          path="attendance-corrections"
          element={
            <RoleProtectedRoute requiredRole={UserRole.EMPLOYEE}>
              <AttendanceCorrections />
            </RoleProtectedRoute>
          }
        />
        <Route path="notifications" element={<Notifications />} />

        {/* HRM Settings - Admin only */}
        <Route
          path="hrm-settings"
          element={
            <RoleProtectedRoute requiredRole={UserRole.ADMIN}>
              <HrmSettings />
            </RoleProtectedRoute>
          }
        />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    </RouteErrorBoundary>
  )
}

export default App