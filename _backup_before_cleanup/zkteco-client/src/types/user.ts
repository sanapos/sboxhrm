// ==========================================
// src/types/user.ts
// ==========================================
export interface UserProfile {
  id: string
  email: string
  userName: string
  firstName?: string
  lastName?: string
  phoneNumber?: string
  roles: string[]
  managerId?: string
  managerName?: string
  created: string
}

export interface UpdateProfileRequest {
  firstName?: string
  lastName?: string
  phoneNumber?: string
}

export interface UpdatePasswordRequest {
  currentPassword: string
  newPassword: string
}
