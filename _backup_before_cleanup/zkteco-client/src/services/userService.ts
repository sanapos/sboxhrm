// ==========================================
// src/services/userService.ts
// ==========================================
import { UpdatePasswordRequest, UpdateProfileRequest, UserProfile } from '@/types/user'
import { apiService } from './api'

export const userService = {
  getProfile: async () => {
    return await apiService.get<UserProfile>('/api/Accounts/profile')
  },

  updateProfile: async (data: UpdateProfileRequest) => {
    return await apiService.put<UserProfile>('/api/Accounts/profile', data)
  },

  updatePassword: async (data: UpdatePasswordRequest) => {
    return await apiService.put<UserProfile>('/api/Accounts/profile/password', data)
  },
}
