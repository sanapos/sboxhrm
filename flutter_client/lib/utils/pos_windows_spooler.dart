/// Máy in trên Windows: in ESC/POS thô qua hàng đợi in của Windows (winspool, kiểu dữ liệu RAW).
///
/// Máy in nhiệt USB trên Windows được cài như một máy in có driver (driver hãng, hoặc
/// «Generic / Text Only»). Không mở thẳng cổng USB như Android — gửi byte thô qua spooler,
/// driver chuyển nguyên vẹn xuống máy in (giữ lệnh cắt giấy, mở két, cỡ chữ…).
library;

export 'pos_windows_spooler_stub.dart' if (dart.library.ffi) 'pos_windows_spooler_ffi.dart';
