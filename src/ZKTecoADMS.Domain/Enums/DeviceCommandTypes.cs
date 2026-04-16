namespace ZKTecoADMS.Domain.Enums;

public enum DeviceCommandTypes
{
    AddDeviceUser,
    DeleteDeviceUser,
    UpdateDeviceUser,
    ClearAttendances,
    ClearDeviceUsers,
    ClearData,
    RestartDevice,
    SyncAttendances,
    SyncDeviceUsers,
    EnrollFingerprint,      // Đăng ký vân tay - gửi ENROLL_FP
    DeleteFingerprint,      // Xóa vân tay - gửi DELETE_FINGER
    SyncFingerprints,       // Đồng bộ vân tay từ máy
    EnrollFace,             // Đăng ký khuôn mặt
    DeleteFace,             // Xóa khuôn mặt
    SyncFaces,              // Đồng bộ khuôn mặt từ máy
    OpenDoor,               // Mở cửa
    CloseDoor,              // Đóng cửa
    GetDeviceInfo,          // Lấy thông tin thiết bị
}