// ==========================================
// src/types/index.ts

import { DeviceCommandTypes } from "./device";

// ==========================================
export interface Device {
  id: string;
  serialNumber: string;
  deviceName: string;
  lastOnline?: string;
  isActive: boolean;
  location?: string;
  description?: string;
}

export interface AttendanceLog {
  id: string;
  deviceId: number;
  deviceName: string;
  userId?: number;
  userName: string
  pin: string;
  verifyType?: number;
  attendanceState: number;
  attendanceTime: string;
  workCode?: string;
  createdAt: string;
}

export interface DeviceCommand {
  id: string;
  deviceId: number;
  command: string;
  priority: number;
  status: number;
  responseData?: string;
  errorMessage?: string;
  createdAt: string;
  sentAt?: string;
  completedAt?: string;
  commandType: DeviceCommandTypes
}

export interface DeviceInfo {
  deviceId: string;
  firmwareVersion?: string;
  enrolledUserCount: number;
  fingerprintCount: number;
  attendanceCount: number;
  deviceIp?: string;
  fingerprintVersion?: string;
  faceVersion?: string;
  faceTemplateCount?: string;
  devSupportData?: string;
}

export interface CreateDeviceRequest {
  serialNumber: string;
  deviceName: string;
  location?: string;
  description?: string;
}

export interface SendCommandRequest {
  commandType: string;
  command?: string;
  priority?: number;
}

export interface AppResponse<T> {
  data: T;
  errors: string[];
  isSuccess: boolean;
}

export interface PaginatedResponse<T> {
  items: T[];
  totalCount: number;
  pageNumber: number;
  pageSize: number;
  totalPages: number;
  hasPreviousPage: boolean;
  hasNextPage: boolean;
  previousPageNumber?: number;
  nextPageNumber?: number;
}


export interface PaginationRequest {
  pageNumber: number;
  pageSize: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
}