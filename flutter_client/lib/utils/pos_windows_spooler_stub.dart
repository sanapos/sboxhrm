/// Web: không có hàng đợi in Windows.
class PosWindowsSpooler {
  PosWindowsSpooler._();

  static bool get isSupported => false;

  static Future<List<String>> listPrinters() async => const [];

  static Future<String?> defaultPrinter() async => null;

  static Future<bool> canOpen(String printerName) async => false;

  static Future<bool> writeRaw(String printerName, List<int> bytes, {String docName = 'SBOX POS'}) async =>
      false;
}
