// ==========================================
// src/services/api.ts
// ==========================================
import axios, { AxiosInstance, AxiosError } from 'axios';
import Cookies from 'js-cookie';
import { toast } from 'sonner';
import { AppResponse } from '../types/index';
import { ACCESSTOKEN_KEY, REFRESHTOKEN_KEY } from '@/constants/auth';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080';

class ApiService {
  private client: AxiosInstance;
  private isRefreshing = false;
  private failedQueue: Array<{
    resolve: (value?: any) => void;
    reject: (error?: any) => void;
  }> = [];

  constructor() {
    this.client = axios.create({
      baseURL: API_BASE_URL,
      headers: {
        'Content-Type': 'application/json',
      },
      timeout: 30000,
    });

    this.setupInterceptors();
  }

  private processQueue(error: any, token: string | null = null) {
    this.failedQueue.forEach((prom) => {
      if (error) {
        prom.reject(error);
      } else {
        prom.resolve(token);
      }
    });

    this.failedQueue = [];
  }

  private async refreshAccessToken(): Promise<string> {
    const refreshToken = Cookies.get(REFRESHTOKEN_KEY);
    
    if (!refreshToken) {
      throw new Error('No refresh token available');
    }

    const response = await axios.post<AppResponse<{ accessToken: string; refreshToken: string }>>(
      `${API_BASE_URL}/api/auth/refresh`,
      { refreshToken },
      {
        headers: {
          'Content-Type': 'application/json',
        },
      }
    );

    if (response.data.isSuccess) {
      const { accessToken, refreshToken: newRefreshToken } = response.data.data;
      Cookies.set(ACCESSTOKEN_KEY, accessToken);
      Cookies.set(REFRESHTOKEN_KEY, newRefreshToken);
      return accessToken;
    }

    throw new Error('Failed to refresh token');
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Add auth token if exists
        const token = Cookies.get(ACCESSTOKEN_KEY);
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        
        // Don't set Content-Type for FormData - let browser set it with boundary
        if (config.data instanceof FormData) {
          delete config.headers['Content-Type'];
        }
        
        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const originalRequest = error.config as any;

        // If error is 401 and we haven't tried to refresh yet
        if (error.response?.status === 401 && !originalRequest._retry) {
          if (this.isRefreshing) {
            // If already refreshing, queue this request
            return new Promise((resolve, reject) => {
              this.failedQueue.push({ resolve, reject });
            })
              .then((token) => {
                originalRequest.headers.Authorization = `Bearer ${token}`;
                return this.client(originalRequest);
              })
              .catch((err) => {
                return Promise.reject(err);
              });
          }

          originalRequest._retry = true;
          this.isRefreshing = true;

          try {
            const newToken = await this.refreshAccessToken();
            this.isRefreshing = false;
            this.processQueue(null, newToken);
            
            originalRequest.headers.Authorization = `Bearer ${newToken}`;
            return this.client(originalRequest);
          } catch (refreshError) {
            this.isRefreshing = false;
            this.processQueue(refreshError, null);
            
            // Clear tokens and redirect to login
            Cookies.remove(ACCESSTOKEN_KEY);
            Cookies.remove(REFRESHTOKEN_KEY);
            
            toast.error('Session expired', { description: 'Please login again' });
            
            // Redirect to login page
            if (window.location.pathname !== '/login') {
              window.location.href = '/login';
            }
            
            return Promise.reject(refreshError);
          }
        }

        this.handleError(error);
        return Promise.reject(error);
      }
    );
  }

  private handleError(error: AxiosError) {
    if (error.response) {
      const status = error.response.status;
      const message = (error.response.data as any)?.message || error.message;

      switch (status) {
        case 400:
          toast.error('Bad Request', { description: message });
          break;
        case 401:
          toast.error('Unauthorized', { description: 'Please login again' });
          // Handle logout
          break;
        case 403:
          toast.error('Forbidden', { description: 'You don\'t have permission' });
          break;
        case 404:
          toast.error('Not Found', { description: message });
          break;
        case 415:
          toast.error('Unsupported Media Type', { 
            description: 'Invalid file format or content type' 
          });
          break;
        case 500:
          toast.error('Server Error', { description: 'Something went wrong' });
          break;
        default:
          toast.error('Error', { description: message });
      }
    } else if (error.request) {
      toast.error('Network Error', { 
        description: 'Cannot connect to server' 
      });
    } else {
      toast.error('Error', { description: error.message });
    }
  }

  // Generic methods
  async get<T>(url: string, params?: any): Promise<T> {
    const response = await this.client.get<AppResponse<T>>(url, { params });
    if(response.data.isSuccess === false){
      throw new Error(response.data.errors.join(', '));
    }
    return response.data.data;
  }

  async post<T>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.post<AppResponse<T>>(url, data, config);
    const resData = response.data;
    if(resData.isSuccess === false){
      throw new Error(resData.errors.join(', '));
    }

    return resData.data;
  }

  async put<T>(url: string, data?: any, config?: any): Promise<T> {
    const response = await this.client.put<AppResponse<T>>(url, data, config);
    if(response.data.isSuccess === false){
      throw new Error(response.data.errors.join(', '));
    }
    return response.data.data;
  }

  async delete<T>(url: string, data?: any): Promise<T> {
    const response = await this.client.delete<AppResponse<T>>(url, { data });
    if(response.data.isSuccess === false){
      throw new Error(response.data.errors.join(', '));
    }
    return response.data.data;
  }
}

export const apiService = new ApiService();

export const buildQueryParams = (params: Record<string, any>): string => {
  const query = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      query.append(key, String(value));
    }
  });
  return query.toString();
};