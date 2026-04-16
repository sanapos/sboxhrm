// ==========================================
// src/pages/Profile.tsx
// ==========================================
import { useEffect, useState } from 'react'
import { PageHeader } from '@/components/PageHeader'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { User, Mail, Phone, Calendar, Shield, Users, Loader2 } from 'lucide-react'
import { userService } from '@/services/userService'
import { UserProfile } from '@/types/user'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { PasswordInput, validatePassword } from '@/components/PasswordInput'

export const Profile = () => {
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [isChangingPassword, setIsChangingPassword] = useState(false)
  
  const [formData, setFormData] = useState({
    firstName: '',
    lastName: '',
    phoneNumber: '',
  })

  const [passwordData, setPasswordData] = useState({
    currentPassword: '',
    newPassword: '',
    confirmPassword: '',
  })

  useEffect(() => {
    loadProfile()
  }, [])

  const loadProfile = async () => {
    try {
      setIsLoading(true)
      const response = await userService.getProfile()
      setProfile(response)
      setFormData({
        firstName: response.firstName || '',
        lastName: response.lastName || '',
        phoneNumber: response.phoneNumber || '',
      })
    } catch (error: any) {
      toast.error('Failed to load profile', {
        description: error.message || 'An error occurred while loading your profile',
      })
    } finally {
      setIsLoading(false)
    }
  }

  const handleUpdateProfile = async (e: React.FormEvent) => {
    e.preventDefault()
    
    try {
      setIsSaving(true)
      
      const response = await userService.updateProfile({
        firstName: formData.firstName,
        lastName: formData.lastName,
        phoneNumber: formData.phoneNumber,
      })
      setProfile(response)
      toast.success('Profile updated successfully')
    } catch (error: any) {
      toast.error('Failed to update profile', {
        description: error.message || 'An error occurred while updating your profile',
      })
    } finally {
      setIsSaving(false)
    }
  }

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault()

    if (passwordData.newPassword !== passwordData.confirmPassword) {
      toast.error('Passwords do not match')
      return
    }

    // Validate password requirements
    const passwordError = validatePassword(passwordData.newPassword)
    if (passwordError) {
      toast.error(passwordError)
      return
    }

    try {
      setIsSaving(true)
      
      await userService.updatePassword({
        currentPassword: passwordData.currentPassword,
        newPassword: passwordData.newPassword,
      })
      toast.success('Password changed successfully')
      setPasswordData({
        currentPassword: '',
        newPassword: '',
        confirmPassword: '',
      })
      setIsChangingPassword(false)
    } catch (error: any) {
      toast.error('Failed to change password', {
        description: error.message || 'Please check your current password and try again',
      })
    } finally {
      setIsSaving(false)
    }
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-4rem)]">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="My Profile"
        description="Manage your account information and settings"
      />

      <div className="grid gap-6 md:grid-cols-2">
        {/* Profile Information Card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <User className="w-5 h-5" />
              Profile Information
            </CardTitle>
            <CardDescription>
              Update your personal information
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleUpdateProfile} className="space-y-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="firstName">First Name</Label>
                  <Input
                    id="firstName"
                    value={formData.firstName}
                    onChange={(e) =>
                      setFormData({ ...formData, firstName: e.target.value })
                    }
                    placeholder="Enter first name"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="lastName">Last Name</Label>
                  <Input
                    id="lastName"
                    value={formData.lastName}
                    onChange={(e) =>
                      setFormData({ ...formData, lastName: e.target.value })
                    }
                    placeholder="Enter last name"
                  />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="phoneNumber">Phone Number</Label>
                <div className="relative">
                  <Phone className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
                  <Input
                    id="phoneNumber"
                    value={formData.phoneNumber}
                    onChange={(e) =>
                      setFormData({ ...formData, phoneNumber: e.target.value })
                    }
                    placeholder="Enter phone number"
                    className="pl-10"
                  />
                </div>
              </div>

              <Separator />

              <Button type="submit" disabled={isSaving} className="w-full">
                {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Save Changes
              </Button>
            </form>
          </CardContent>
        </Card>

        {/* Account Details Card */}
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Shield className="w-5 h-5" />
                Account Details
              </CardTitle>
              <CardDescription>
                Your account information and role
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label className="text-muted-foreground">Email</Label>
                <div className="flex items-center gap-2">
                  <Mail className="h-4 w-4 text-muted-foreground" />
                  <span className="font-medium">{profile?.email}</span>
                </div>
              </div>

              <div className="space-y-2">
                <Label className="text-muted-foreground">Username</Label>
                <div className="flex items-center gap-2">
                  <User className="h-4 w-4 text-muted-foreground" />
                  <span className="font-medium">{profile?.userName}</span>
                </div>
              </div>

              <div className="space-y-2">
                <Label className="text-muted-foreground">Roles</Label>
                <div className="flex gap-2 flex-wrap">
                  {profile?.roles.map((role) => (
                    <Badge key={role} variant="secondary">
                      {role}
                    </Badge>
                  ))}
                </div>
              </div>

              {profile?.managerName && (
                <div className="space-y-2">
                  <Label className="text-muted-foreground">Manager</Label>
                  <div className="flex items-center gap-2">
                    <Users className="h-4 w-4 text-muted-foreground" />
                    <span className="font-medium">{profile.managerName}</span>
                  </div>
                </div>
              )}

              <div className="space-y-2">
                <Label className="text-muted-foreground">Member Since</Label>
                <div className="flex items-center gap-2">
                  <Calendar className="h-4 w-4 text-muted-foreground" />
                  <span className="font-medium">
                    {new Date(profile?.created || '').toLocaleDateString()}
                  </span>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Change Password Card */}
      <Card>
        <CardHeader>
          <CardTitle>Change Password</CardTitle>
          <CardDescription>
            Update your password to keep your account secure
          </CardDescription>
        </CardHeader>
        <CardContent>
          {!isChangingPassword ? (
            <Button
              variant="outline"
              onClick={() => setIsChangingPassword(true)}
            >
              Change Password
            </Button>
          ) : (
            <form onSubmit={handleChangePassword} className="space-y-4 max-w-2xl">
              <div className="space-y-2">
                <Label htmlFor="currentPassword">
                  Current Password <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="currentPassword"
                  type="password"
                  value={passwordData.currentPassword}
                  onChange={(e) =>
                    setPasswordData({
                      ...passwordData,
                      currentPassword: e.target.value,
                    })
                  }
                  placeholder="Enter current password"
                  disabled={isSaving}
                  required
                />
              </div>

              <PasswordInput
                password={passwordData.newPassword}
                confirmPassword={passwordData.confirmPassword}
                onPasswordChange={(value) =>
                  setPasswordData({ ...passwordData, newPassword: value })
                }
                onConfirmPasswordChange={(value) =>
                  setPasswordData({ ...passwordData, confirmPassword: value })
                }
                disabled={isSaving}
                passwordLabel="New Password"
                confirmPasswordLabel="Confirm New Password"
                passwordPlaceholder="Enter new password"
                confirmPasswordPlaceholder="Confirm new password"
              />

              <Separator />

              <div className="flex gap-2">
                <Button type="submit" disabled={isSaving}>
                  {isSaving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Update Password
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    setIsChangingPassword(false)
                    setPasswordData({
                      currentPassword: '',
                      newPassword: '',
                      confirmPassword: '',
                    })
                  }}
                  disabled={isSaving}
                >
                  Cancel
                </Button>
              </div>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
