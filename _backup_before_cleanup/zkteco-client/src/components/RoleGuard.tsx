// ==========================================
// src/components/RoleGuard.tsx
// ==========================================
import { useRoleAccess } from '@/hooks/useRoleAccess'
import { UserRole } from '@/constants/roles'

interface RoleGuardProps {
  children: React.ReactNode
  allowedRoles?: UserRole[]
  requiredRole?: UserRole
  fallback?: React.ReactNode
}

/**
 * Component to conditionally render content based on user roles.
 * 
 * @example
 * // Show content only for Admin
 * <RoleGuard allowedRoles={[UserRole.ADMIN]}>
 *   <AdminOnlyButton />
 * </RoleGuard>
 * 
 * @example
 * // Show content for Manager and above
 * <RoleGuard requiredRole={UserRole.MANAGER}>
 *   <ManagerFeature />
 * </RoleGuard>
 */
export const RoleGuard: React.FC<RoleGuardProps> = ({
  children,
  allowedRoles,
  requiredRole,
  fallback = null
}) => {
  const { getUserRole, hasMinimumRole } = useRoleAccess()
  const userRole = getUserRole()

  if (!userRole) {
    return <>{fallback}</>
  }

  // Check if user has one of the allowed roles
  if (allowedRoles && !allowedRoles.includes(userRole)) {
    return <>{fallback}</>
  }

  // Check if user has minimum required role
  if (requiredRole && !hasMinimumRole(requiredRole)) {
    return <>{fallback}</>
  }

  return <>{children}</>
}
