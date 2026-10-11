/// Bản build: `--dart-define=SBOX_APP=kds` → app SBOX KDS (chỉ màn hình bếp, mã ứng dụng riêng
/// sbox.sana.vn.kds — cài song song với SBOX POS). Mặc định là SBOX POS đầy đủ.
const String kSboxAppVariant = String.fromEnvironment('SBOX_APP');
const bool kSboxKdsApp = kSboxAppVariant == 'kds';
