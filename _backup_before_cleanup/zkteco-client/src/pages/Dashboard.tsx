// ==========================================
// src/pages/Dashboard.tsx
// ==========================================
import { useRoleAccess } from '@/hooks/useRoleAccess'
import { UserRole } from '@/constants/roles'
import { AdminDashboard } from './AdminDashboard'
import { ManagerDashboard } from './ManagerDashboard'
import { EmployeeDashboard } from '@/components/employee-dashboard'
import { useEmployeeDashboard } from '@/hooks/useEmployeeDashboard'
import { useState } from 'react'
import { LoadingSpinner } from '@/components/LoadingSpinner'

export const Dashboard = () => {
  const { getUserRole } = useRoleAccess()
  const userRole = getUserRole()
  const [period, setPeriod] = useState<'week' | 'month' | 'year'>('month')

  // Employee dashboard data
  const { data: employeeData, isLoading: employeeLoading, refetch: refetchEmployee } = useEmployeeDashboard({ period })

  // Show loading while determining role
  if (!userRole) {
    return <LoadingSpinner />
  }

  // Render dashboard based on user role
  switch (userRole) {
    case UserRole.ADMIN:
      return <AdminDashboard />

    case UserRole.MANAGER:
      return <ManagerDashboard />

    case UserRole.EMPLOYEE:
      return (
        <div className="container mx-auto p-6">
          <EmployeeDashboard
            data={employeeData}
            isLoading={employeeLoading}
            onPeriodChange={setPeriod}
            onRefresh={refetchEmployee}
          />
        </div>
      )

    default:
      return (
        <div className="flex items-center justify-center h-screen">
          <div className="text-center">
            <h2 className="text-2xl font-bold mb-2">Access Denied</h2>
            <p className="text-muted-foreground">You don't have permission to view this dashboard.</p>
          </div>
        </div>
      )
  }
}