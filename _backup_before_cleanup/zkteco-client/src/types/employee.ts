import { Account } from "./account";

export interface Employee {
  id: string;
  // Identity Information
  employeeCode: string;
  firstName: string;
  lastName: string;
  fullName?: string;
  gender?: string;
  dateOfBirth?: string;
  photoUrl?: string;
  nationalIdNumber?: string;
  nationalIdIssueDate?: string;
  nationalIdIssuePlace?: string;

  // Contact Information
  phoneNumber?: string;
  personalEmail?: string;
  companyEmail: string;
  permanentAddress?: string;
  temporaryAddress?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;

  // Work Information
  department?: string;
  position?: string;
  level?: string;
  employmentType: number;
  joinDate?: string;
  probationEndDate?: string;
  workStatus?: string;
  resignationDate?: string;
  resignationReason?: string;

  // ZKTeco Integration
  pin?: string;
  cardNumber?: string;
  deviceId?: string;
  applicationUserId?: string;
  
  // Account Information
  hasAccount?: boolean;
  account?: Account
}

export interface CreateEmployeeRequest {
  employeeCode: string;
  firstName: string;
  lastName: string;
  gender?: string;
  dateOfBirth?: null | string;
  photoUrl?: string;
  nationalIdNumber?: string;
  nationalIdIssueDate?: null | string;
  nationalIdIssuePlace?: null | string;
  phoneNumber?: string;
  personalEmail?: string;
  companyEmail?: string;
  permanentAddress?: string;
  temporaryAddress?: string;
  emergencyContactName?: string;
  emergencyContactPhone?: string;
  department?: string;
  position?: string;
  level?: string;
  employmentType: number;
  joinDate?: string | null;
  probationEndDate?: string | null;
  workStatus: number;
  pin?: string;
  cardNumber?: string;
  deviceId?: string;
  applicationUserId?: string;

  hasAccount?: boolean;
}

export interface UpdateEmployeeRequest extends CreateEmployeeRequest {
  id: string;
  resignationDate?: string | null;
  resignationReason?: string | null;
}


export enum EmploymentTypes {
  Hourly = 0,
  Monthly = 1,
}