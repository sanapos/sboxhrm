
// ==========================================
// src/contexts/AuthContext.tsx
// ==========================================
import React, { createContext, useContext, useEffect, useState } from 'react';
import { authService } from '@/services/authService';
import { toast } from 'sonner';
import type { AuthUser, AuthContextType } from '@/types/auth';
import Cookies from 'js-cookie';
import { jwtDecode } from 'jwt-decode';
import { ACCESSTOKEN_KEY, REFRESHTOKEN_KEY, JWT_CLAIMS } from '@/constants/auth';

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const accessToken = Cookies.get(ACCESSTOKEN_KEY);
      
      if (accessToken) {
        parseUserFromAccessToken(accessToken);
      }
    } catch (error) {
      Cookies.remove(ACCESSTOKEN_KEY);
    } finally {
      setIsLoading(false);
    }
  };

  const login = async (email: string, password: string) => {
    try {
      const response = await authService.login(email, password);
      Cookies.set(ACCESSTOKEN_KEY, response.accessToken);
      Cookies.set(REFRESHTOKEN_KEY, response.refreshToken);
      parseUserFromAccessToken(response.accessToken);
    } catch (error: any) {
      toast.error('Login failed', { description: error.message });
      throw error;
    }
  };

  const parseUserFromAccessToken = (token: string): void => {
    const currentUser = jwtDecode<AuthUser>(token);
    setUser(currentUser);
  }

  const logout = async () => {
    try {
      Cookies.remove(ACCESSTOKEN_KEY);
      Cookies.remove(REFRESHTOKEN_KEY);
      await authService.logout();
      setUser(null);
    } catch (error) {
      toast.error('Logout failed');
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: !!user,
        isLoading,
        login,
        logout,
        applicationUserId: String(user?.[JWT_CLAIMS.NAME_IDENTIFIER]) || null,
        isManager: user?.[JWT_CLAIMS.ROLE] === 'Manager',
        isHourlyEmployee: user?.[JWT_CLAIMS.EMPLOYMENT_TYPE] === 'Hourly',
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
