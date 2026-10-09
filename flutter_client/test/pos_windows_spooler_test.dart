import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_usb_printer.dart';
import 'package:zkteco_flutter_client/utils/pos_windows_spooler.dart';

/// Hàng đợi in Windows (winspool) gọi thật — chỉ chạy trên máy Windows.
void main() {
  final onWindows = Platform.isWindows;

  test('Liệt kê máy in Windows + mở được máy in', () async {
    final printers = await PosWindowsSpooler.listPrinters();
    // Windows luôn có ít nhất máy in ảo (Microsoft Print to PDF / XPS).
    expect(printers, isNotEmpty);
    expect(await PosWindowsSpooler.canOpen(printers.first), isTrue);
    expect(await PosWindowsSpooler.canOpen('Không có máy in này 123'), isFalse);
    final def = await PosWindowsSpooler.defaultPrinter();
    if (def != null) expect(printers, contains(def));
  }, skip: !onWindows);

  test('Cổng USB trên Windows = máy in đã cài, khớp lại theo tên đã lưu', () async {
    final list = await PosUsbPrinter.listDevices();
    expect(list, isNotEmpty);
    final first = list.first;
    expect(first.stableId, 'win:${first.deviceName}');
    expect(first.hasPermission, isTrue);
    expect(PosUsbPrinter.matchInList(list, first.savedRef)?.deviceName, first.deviceName);
    expect(PosUsbPrinter.matchInList(list, first.stableId)?.deviceName, first.deviceName);
    expect(PosUsbPrinter.matchInList(list, first.deviceName)?.deviceName, first.deviceName);
    expect(await PosUsbPrinter.probeDevice(stableId: first.stableId), isTrue);
    expect(PosThermalConnectionType.usb.label, 'Máy in Windows (USB)');
  }, skip: !onWindows);

  test('Không gửi byte rỗng / máy in không tồn tại', () async {
    expect(await PosWindowsSpooler.writeRaw('Không có máy in này 123', [0x1B, 0x40]), isFalse);
    expect(await PosWindowsSpooler.writeRaw('x', const []), isFalse);
  }, skip: !onWindows);
}
