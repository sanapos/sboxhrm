// ==========================================
// src/hooks/useRoleAccess.ts
// ==========================================
import { useAuth } from '@/contexts/AuthContext'
import { UserRole, ROLE_HIERARCHY, ROLE_PERMISSIONS } from '@/constants/roles'
import { JWT_CLAIMS } from '@/constants/auth'

export const useRoleAccess = () => {
  const { user } = useAuth()

  const getUserRole = (): UserRole | null => {
    if (!user) return null
    const role = user[JWT_CLAIMS.ROLE] as string
    return role as UserRole
  }

  const hasRole = (requiredRole: UserRole): boolean => {
    const userRole = getUserRole()
    if (!userRole) return false
    return userRole === requiredRole
  }

  const hasMinimumRole = (minimumRole: UserRole): boolean => {
    const userRole = getUserRole()
    if (!userRole) return false
    return ROLE_HIERARCHY[userRole] >= ROLE_HIERARCHY[minimumRole]
  }

  const canAccessRoute = (route: string): boolean => {
    const userRole = getUserRole()
    if (!userRole) return false
    
    const allowedRoutes = ROLE_PERMISSIONS[userRole]
    return allowedRoutes.some(allowedRoute => route.startsWith(allowedRoute))
  }

  const isAdmin = (): boolean => {
    return hasRole(UserRole.ADMIN)
  }

  const isManager = (): boolean => {
    return hasRole(UserRole.MANAGER)
  }

  const isEmployee = (): boolean => {
    return hasRole(UserRole.EMPLOYEE)
  }

  const getAllowedRoutes = (): string[] => {
    const userRole = getUserRole()
    if (!userRole) return []
    return ROLE_PERMISSIONS[userRole]
  }

  return {
    getUserRole,
    hasRole,
    hasMinimumRole,
    canAccessRoute,
    isAdmin,
    isManager,
    isEmployee,
    getAllowedRoutes
  }
}
