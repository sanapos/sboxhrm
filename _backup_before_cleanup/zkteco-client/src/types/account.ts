export interface Account {
    id: string;
    email: string;
    userName: string;
    firstName?: string;
    lastName?: string;
    fullName?: string;
    phoneNumber?: string;
    roles?: string[];
    managerId?: string;
    employeeId?: string;
    managerName?: string;
}

export interface CreateEmployeeAccountRequest {
  email: string
  password: string
  firstName: string
  lastName: string
  phoneNumber?: string
  userName: string
  employeeId: string
}

export interface UpdateEmployeeAccountRequest {
  email: string
  firstName: string
  lastName: string
  phoneNumber?: string
  password?: string
  userName?: string
}