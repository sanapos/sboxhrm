// ==========================================
// src/components/RouteErrorBoundary.tsx
// ==========================================
import { useNavigate, useLocation } from 'react-router-dom'
import { ErrorBoundary } from './ErrorBoundary'
import { ErrorFallback } from './ErrorFallback'
import { ReactNode } from 'react'

interface RouteErrorBoundaryProps {
  children: ReactNode
  fallbackTitle?: string
  fallbackDescription?: string
}

/**
 * Error Boundary wrapper that has access to React Router hooks
 * Use this to wrap routes that need navigation in error fallback
 */
export const RouteErrorBoundary = ({ 
  children, 
  fallbackTitle,
  fallbackDescription 
}: RouteErrorBoundaryProps) => {
  const navigate = useNavigate()
  const location = useLocation()

  const handleError = (error: Error) => {
    // Log error with route context
    console.error('Error in route:', location.pathname, error)
    
    // You can add error reporting here
    // e.g., Sentry.captureException(error, { tags: { route: location.pathname } })
  }

  const handleReset = () => {
    // Navigate to a safe route when resetting
    navigate('/dashboard', { replace: true })
  }

  return (
    <ErrorBoundary
      fallback={
        <ErrorFallback
          title={fallbackTitle}
          description={fallbackDescription}
          resetError={handleReset}
        />
      }
      onError={handleError}
    >
      {children}
    </ErrorBoundary>
  )
}
