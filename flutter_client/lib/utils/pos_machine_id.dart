/// Mã máy do hệ điều hành cấp (hiện chỉ Windows) — xem [readWindowsMachineGuid].
library;

export 'pos_machine_id_stub.dart'
    if (dart.library.ffi) 'pos_machine_id_io.dart';
