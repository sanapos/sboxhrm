// ==========================================
// src/components/PasswordInput.tsx
// ==========================================
import { useState } from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { CheckCircle2, Circle } from 'lucide-react'

interface PasswordInputProps {
  password: string
  confirmPassword: string
  onPasswordChange: (password: string) => void
  onConfirmPasswordChange: (confirmPassword: string) => void
  disabled?: boolean
  showRequirements?: boolean
  isOptional?: boolean
  passwordLabel?: string
  confirmPasswordLabel?: string
  passwordPlaceholder?: string
  confirmPasswordPlaceholder?: string
  passwordError?: string
  confirmPasswordError?: string
}

export const validatePassword = (password: string): string | null => {
  if (!password) return null
  
  if (password.length < 8) {
    return 'Password must be at least 8 characters'
  }
  
  if (!/[0-9]/.test(password)) {
    return 'Password must contain at least one digit'
  }
  
  if (!/[a-z]/.test(password)) {
    return 'Password must contain at least one lowercase letter'
  }
  
  if (!/[A-Z]/.test(password)) {
    return 'Password must contain at least one uppercase letter'
  }
  
  if (!/[^a-zA-Z0-9]/.test(password)) {
    return 'Password must contain at least one special character'
  }
  
  return null
}

export const PasswordInput = ({
  password,
  confirmPassword,
  onPasswordChange,
  onConfirmPasswordChange,
  disabled = false,
  showRequirements = true,
  isOptional = false,
  passwordLabel = 'Password',
  confirmPasswordLabel = 'Confirm Password',
  passwordPlaceholder = '••••••••',
  confirmPasswordPlaceholder = '••••••••',
  passwordError,
  confirmPasswordError,
}: PasswordInputProps) => {
  const [showPasswordRequirements, setShowPasswordRequirements] = useState(false)

  // Password requirements state
  const passwordRequirements = {
    minLength: password.length >= 8,
    hasUppercase: /[A-Z]/.test(password),
    hasLowercase: /[a-z]/.test(password),
    hasDigit: /[0-9]/.test(password),
    hasSpecial: /[^a-zA-Z0-9]/.test(password),
  }

  return (
    <>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label htmlFor="password">
            {passwordLabel} {!isOptional && <span className="text-destructive">*</span>}
            {isOptional && <span className="text-sm text-muted-foreground">(leave blank to keep current)</span>}
          </Label>
          <Input
            id="password"
            type="password"
            placeholder={passwordPlaceholder}
            value={password}
            onChange={(e) => onPasswordChange(e.target.value)}
            onFocus={() => showRequirements && setShowPasswordRequirements(true)}
            disabled={disabled}
            className={passwordError ? 'border-destructive' : ''}
            required={!isOptional}
          />
          {passwordError && (
            <p className="text-sm text-destructive">{passwordError}</p>
          )}
        </div>

        <div className="space-y-2">
          <Label htmlFor="confirmPassword">
            {confirmPasswordLabel} {!isOptional && <span className="text-destructive">*</span>}
          </Label>
          <Input
            id="confirmPassword"
            type="password"
            placeholder={confirmPasswordPlaceholder}
            value={confirmPassword}
            onChange={(e) => onConfirmPasswordChange(e.target.value)}
            disabled={disabled}
            className={confirmPasswordError ? 'border-destructive' : ''}
            required={!isOptional}
          />
          {confirmPasswordError && (
            <p className="text-sm text-destructive">{confirmPasswordError}</p>
          )}
        </div>
      </div>

      {showRequirements && (showPasswordRequirements || password) && (
        <div className="space-y-2 text-xs bg-muted/30 p-3 rounded-lg border border-border/50">
          <p className="font-semibold text-foreground mb-2">Password must contain:</p>
          <div className="space-y-1.5">
            <div className="flex items-center gap-2">
              {passwordRequirements.minLength ? (
                <CheckCircle2 className="w-4 h-4 text-green-600 dark:text-green-500 flex-shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
              <span className={passwordRequirements.minLength ? 'text-green-600 dark:text-green-500' : 'text-muted-foreground'}>
                At least 8 characters
              </span>
            </div>
            <div className="flex items-center gap-2">
              {passwordRequirements.hasUppercase ? (
                <CheckCircle2 className="w-4 h-4 text-green-600 dark:text-green-500 flex-shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
              <span className={passwordRequirements.hasUppercase ? 'text-green-600 dark:text-green-500' : 'text-muted-foreground'}>
                One uppercase letter (A-Z)
              </span>
            </div>
            <div className="flex items-center gap-2">
              {passwordRequirements.hasLowercase ? (
                <CheckCircle2 className="w-4 h-4 text-green-600 dark:text-green-500 flex-shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
              <span className={passwordRequirements.hasLowercase ? 'text-green-600 dark:text-green-500' : 'text-muted-foreground'}>
                One lowercase letter (a-z)
              </span>
            </div>
            <div className="flex items-center gap-2">
              {passwordRequirements.hasDigit ? (
                <CheckCircle2 className="w-4 h-4 text-green-600 dark:text-green-500 flex-shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
              <span className={passwordRequirements.hasDigit ? 'text-green-600 dark:text-green-500' : 'text-muted-foreground'}>
                One digit (0-9)
              </span>
            </div>
            <div className="flex items-center gap-2">
              {passwordRequirements.hasSpecial ? (
                <CheckCircle2 className="w-4 h-4 text-green-600 dark:text-green-500 flex-shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-muted-foreground flex-shrink-0" />
              )}
              <span className={passwordRequirements.hasSpecial ? 'text-green-600 dark:text-green-500' : 'text-muted-foreground'}>
                One special character (!@#$%^&*)
              </span>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
