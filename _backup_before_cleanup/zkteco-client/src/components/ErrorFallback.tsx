// ==========================================
// src/components/ErrorFallback.tsx
// ==========================================
import { AlertCircle, Home, RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'

interface ErrorFallbackProps {
  error?: Error | null
  resetError?: () => void
  title?: string
  description?: string
  showDetails?: boolean
}

export const ErrorFallback = ({
  error,
  resetError,
  title = 'Oops! Something went wrong',
  description = 'We encountered an unexpected error. Please try refreshing the page or contact support if the problem persists.',
  showDetails = true,
}: ErrorFallbackProps) => {
  const handleGoHome = () => {
    window.location.href = '/dashboard'
  }

  const handleRefresh = () => {
    if (resetError) {
      resetError()
    } else {
      window.location.reload()
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="max-w-2xl w-full">
        <CardHeader className="text-center space-y-2">
          <div className="mx-auto w-16 h-16 bg-destructive/10 rounded-full flex items-center justify-center">
            <AlertCircle className="h-8 w-8 text-destructive" />
          </div>
          <CardTitle className="text-2xl">{title}</CardTitle>
          <CardDescription className="text-base">{description}</CardDescription>
        </CardHeader>

        <CardContent className="space-y-4">
          {showDetails && error && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>
                <div className="space-y-2">
                  <div className="font-medium">Error Details:</div>
                  <div className="text-sm font-mono bg-destructive/5 p-3 rounded border border-destructive/20 overflow-auto max-h-40">
                    {error.message}
                  </div>
                  {error.stack && (
                    <details className="text-xs">
                      <summary className="cursor-pointer hover:underline">
                        View Stack Trace
                      </summary>
                      <pre className="mt-2 bg-destructive/5 p-3 rounded border border-destructive/20 overflow-auto max-h-60">
                        {error.stack}
                      </pre>
                    </details>
                  )}
                </div>
              </AlertDescription>
            </Alert>
          )}

          <div className="bg-muted p-4 rounded-lg">
            <h4 className="font-medium mb-2">What can you do?</h4>
            <ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
              <li>Try refreshing the page</li>
              <li>Go back to the home page</li>
              <li>Clear your browser cache</li>
              <li>Contact support if the issue persists</li>
            </ul>
          </div>
        </CardContent>

        <CardFooter className="flex gap-2 justify-center">
          <Button onClick={handleRefresh} variant="default" className="gap-2">
            <RefreshCw className="h-4 w-4" />
            Try Again
          </Button>
          <Button onClick={handleGoHome} variant="outline" className="gap-2">
            <Home className="h-4 w-4" />
            Go to Dashboard
          </Button>
        </CardFooter>
      </Card>
    </div>
  )
}
