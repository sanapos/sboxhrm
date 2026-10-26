import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_local_printers_store.dart';
import 'package:zkteco_flutter_client/utils/pos_printer_auto_detect.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_usb_printer.dart';

PosUsbDevice usb({
  required String path,
  int vid = 0x0416,
  int pid = 0x5011,
  String? product,
  String? serial,
}) =>
    PosUsbDevice(
      deviceName: path,
      vendorId: vid,
      productId: pid,
      deviceId: 1,
      stableId: '$vid:$pid:${serial ?? ''}',
      displayName: product ?? 'USB',
      productName: product,
      serialNumber: serial,
    );

List<PosLocalPrinterProfile> plan({
  List<PosLocalPrinterProfile> existing = const [],
  List<PosUsbDevice> devices = const [],
  bool sunmi = false,
  bool cutter = false,
  Set<String> ignored = const {},
}) {
  var n = 0;
  return PosPrinterAutoDetect.planNewProfiles(
    existing: existing,
    devices: devices,
    isSunmiDevice: sunmi,
    sunmiHasCutter: cutter,
    ignored: ignored,
    newId: () => 'id${n++}',
  );
}

void main() {
  group('Sunmi', () {
    test('máy cầm tay (không dao cắt) → máy hóa đơn K58', () {
      final r = plan(sunmi: true);
      expect(r, hasLength(1));
      expect(r.first.connectionType, PosThermalConnectionType.sunmi);
      expect(r.first.paperSize, 'K58');
      expect(r.first.roles, {PosLocalPrinterRoles.saleInvoice});
    });

    test('Sunmi T2 có dao cắt → K80', () {
      expect(plan(sunmi: true, cutter: true).first.paperSize, 'K80');
    });

    test('đã có máy Sunmi / đã xóa / đã có máy hóa đơn khác → không thêm', () {
      const sunmiProfile = PosLocalPrinterProfile(
          id: 'a', name: 'S', connectionType: PosThermalConnectionType.sunmi);
      const lanInvoice = PosLocalPrinterProfile(
          id: 'b', name: 'LAN', connectionType: PosThermalConnectionType.lan, lanHost: '1.2.3.4');
      expect(plan(sunmi: true, existing: [sunmiProfile]), isEmpty);
      expect(plan(sunmi: true, ignored: {PosPrinterAutoDetect.sunmiIgnoreKey}), isEmpty);
      expect(plan(sunmi: true, existing: [lanInvoice]), isEmpty);
    });
  });

  group('USB', () {
    test('máy nhiệt cắm vào → máy hóa đơn K80, nhận hãng Xprinter', () {
      final r = plan(devices: [usb(path: '/dev/bus/usb/001/005', product: 'XP-80C')]);
      expect(r, hasLength(1));
      expect(r.first.kind, PosLocalPrinterKind.receipt);
      expect(r.first.paperSize, 'K80');
      expect(r.first.roles, {PosLocalPrinterRoles.saleInvoice});
      expect(r.first.printerBrand, PosThermalPrinterBrand.xprinter);
      expect(r.first.usbDeviceName, '1046:20497:|/dev/bus/usb/001/005');
    });

    test('máy tem (XP-365B) → máy in tem 50×30', () {
      final r = plan(devices: [usb(path: '/dev/bus/usb/001/006', product: 'XP-365B')]);
      expect(r.first.kind, PosLocalPrinterKind.label);
      expect(r.first.labelTemplateId, 'roll_1_50x30');
      expect(r.first.roles.contains(PosLocalPrinterRoles.barcodeLabel), isTrue);
      expect(r.first.roles.contains(PosLocalPrinterRoles.saleInvoice), isFalse);
    });

    test('đã có máy hóa đơn → máy nhiệt thứ hai làm máy bếp', () {
      final r = plan(devices: [
        usb(path: '/dev/bus/usb/001/005', product: 'XP-80C'),
        usb(path: '/dev/bus/usb/001/007', vid: 0x28E9, pid: 0x0289, product: 'ZY-80'),
      ]);
      expect(r, hasLength(2));
      expect(r[0].roles, {PosLocalPrinterRoles.saleInvoice});
      expect(r[1].roles.contains(PosLocalPrinterRoles.kitchenSlip), isTrue);
    });

    test('rút ra cắm cổng khác (không serial) → không tạo máy trùng', () {
      const existing = PosLocalPrinterProfile(
        id: 'x',
        name: 'Máy in Xprinter (USB)',
        connectionType: PosThermalConnectionType.usb,
        usbDeviceName: '1046:20497:|/dev/bus/usb/001/005',
      );
      final r = plan(existing: [existing], devices: [usb(path: '/dev/bus/usb/002/009')]);
      expect(r, isEmpty);
      final m = PosUsbPrinter.matchProfilesExclusive(
        [(id: 'x', savedRaw: existing.usbDeviceName)],
        [usb(path: '/dev/bus/usb/002/009')],
      );
      expect(m['x']?.deviceName, '/dev/bus/usb/002/009');
    });

    test('máy đã xóa tay (cùng VID/PID) → không tự thêm lại', () {
      expect(
        plan(devices: [usb(path: '/dev/bus/usb/001/005')], ignored: {'1046:20497'}),
        isEmpty,
      );
    });

    test('bỏ máy quét mã (HID) / không có cổng in', () {
      final hid = PosUsbDevice(
        deviceName: '/dev/bus/usb/001/003',
        vendorId: 0x05E0,
        productId: 0x1200,
        deviceId: 3,
        stableId: '1504:4608:',
        displayName: 'Scanner',
        isHid: true,
        canPrint: false,
      );
      expect(plan(devices: [hid]), isEmpty);
    });
  });

  test('định danh USB bỏ đường dẫn cổng', () {
    expect(
      PosLocalPrintersStore.usbIdentity('1046:20497:|/dev/bus/usb/001/005'),
      PosLocalPrintersStore.usbIdentity('1046:20497:|/dev/bus/usb/002/009'),
    );
  });
}
