export interface DeviceCommandRequest {
  commandType: DeviceCommandTypes;
  priority?: number;
}

export enum DeviceCommandTypes {
  AddDeviceUser,
  DeleteDeviceUser,
  UpdateDeviceUser,
  ClearAttendances,
  ClearDeviceUsers,
  ClearData,
  RestartDevice,
  SyncAttendances,
  SyncDeviceUsers,
  SyncUsers,
  ClearEmployees,
}