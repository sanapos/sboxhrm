
// ==========================================
// src/services/authService.ts
// ==========================================
import { apiService } from './api';
import type { AuthUser, ForgotPasswordResponse, LoginResponse } from '@/types/auth';

export const authService = {
  login: async (userName: string, password: string): Promise<LoginResponse> => {

    return await apiService.post<LoginResponse>('/api/auth/login', { userName, password });
  },

  logout: async (): Promise<void> => {
    return apiService.post('/api/auth/logout');
  },

  getCurrentUser: async (): Promise<AuthUser> => {
    return apiService.get<AuthUser>('/api/auth/me/me');
  },

  refreshToken: async (): Promise<LoginResponse> => {
    // return apiService.post<{ token: string }>('/api/auth/refresh');
    return null as any;
  },
  forgotPassword: async (email: string): Promise<ForgotPasswordResponse> => {
    // For demo purposes - replace with actual API endpoint
    // return apiService.post<ForgotPasswordResponse>('/api/auth/forgot-password', { email });
    
    // Mock forgot password for demo
    await new Promise(resolve => setTimeout(resolve, 1500));
    
    // Simulate checking if email exists
    if (email.includes('@')) {
      return {
        message: 'Password reset link has been sent to your email',
        success: true,
      };
    }
    
    throw new Error('Invalid email address');
  },

  resetPassword: async (token: string, password: string): Promise<ForgotPasswordResponse> => {
    // return apiService.post<ForgotPasswordResponse>('/api/auth/reset-password', { token, password });
    
    // Mock reset password for demo
    await new Promise(resolve => setTimeout(resolve, 1500));
    
    if (token && password.length >= 8) {
      return {
        message: 'Password has been reset successfully',
        success: true,
      };
    }
    
    throw new Error('Invalid reset token or password');
  },

  verifyResetToken: async (token: string): Promise<boolean> => {
    // return apiService.get<{ valid: boolean }>(`/api/auth/verify-reset-token/${token}`);
    
    // Mock token verification
    await new Promise(resolve => setTimeout(resolve, 500));
    return token.length > 10; // Simple mock validation
  },
};
