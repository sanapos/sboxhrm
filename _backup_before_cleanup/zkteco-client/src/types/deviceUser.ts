import { Employee } from "./employee";

export interface CurrentSalaryProfile {
  id: string;
  salaryProfileId: string;
  profileName: string;
  rate: number;
  currency: string;
  rateTypeName: string;
  effectiveDate: string;
  isActive: boolean;
}

export interface CreateDeviceUserRequest {
    employeeId: string;
    pin: string;
    name: string;
    cardNumber?: string;
    password?: string;
    privilege?: number;
    deviceId?: string;
}

export interface UpdateDeviceUserRequest {
    userId: string
    pin: string;
    name: string;
    cardNumber?: string;
    password?: string;
    privilege?: number;
    department?: string;
    deviceId: string;
}

export interface DeviceUser {
  id: string;
  pin: string;
  name: string;
  password: string;
  cardNumber: string;
  department: string;
  isActive: boolean;
  privilege: 0 | 1 | 2 | 14;
  createdAt: string;
  updatedAt: string;
  deviceId: string;
  deviceName?: string;
  employee?: Employee
}
