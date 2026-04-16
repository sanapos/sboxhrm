// ==========================================
// src/components/RoleProtectedRoute.tsx
// ==========================================
import { Navigate } from 'react-router-dom'
import { useRoleAccess } from '@/hooks/useRoleAccess'
import { UserRole } from '@/constants/roles'

interface RoleProtectedRouteProps {
  children: React.ReactNode
  allowedRoles?: UserRole[]
  requiredRole?: UserRole
}

export const RoleProtectedRoute: React.FC<RoleProtectedRouteProps> = ({
  children,
  allowedRoles,
  requiredRole
}) => {
  const { getUserRole, hasMinimumRole } = useRoleAccess()
  const userRole = getUserRole()

  if (!userRole) {
    return <Navigate to="/login" replace />
  }

  // Check if user has one of the allowed roles
  if (allowedRoles && !allowedRoles.includes(userRole)) {
    return <Navigate to="/dashboard" replace />
  }

  // Check if user has minimum required role
  if (requiredRole && !hasMinimumRole(requiredRole)) {
    return <Navigate to="/dashboard" replace />
  }

  return <>{children}</>
}
