import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_imin_printer.dart';
import 'package:zkteco_flutter_client/utils/pos_local_printers_store.dart';
import 'package:zkteco_flutter_client/utils/pos_printer_auto_detect.dart';
import 'package:zkteco_flutter_client/utils/pos_printer_transport.dart';
import 'package:zkteco_flutter_client/utils/pos_store_printer_mapper.dart';
import 'package:zkteco_flutter_client/models/pos_store_printer.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_usb_printer.dart';

PosUsbDevice _usb(int vid, int pid, String path) => PosUsbDevice(
      deviceName: path,
      vendorId: vid,
      productId: pid,
      deviceId: 1,
      stableId: '$vid:$pid:',
      displayName: 'USB',
    );

List<PosLocalPrinterProfile> _plan({
  List<PosLocalPrinterProfile> existing = const [],
  List<PosUsbDevice> devices = const [],
  bool imin = false,
  String paper = 'K80',
  Set<String> ignored = const {},
}) {
  var n = 0;
  return PosPrinterAutoDetect.planNewProfiles(
    existing: existing,
    devices: devices,
    isSunmiDevice: false,
    sunmiHasCutter: false,
    isIminDevice: imin,
    iminPaperSize: paper,
    ignored: ignored,
    newId: () => 'id${n++}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Khổ giấy iMin', () {
    test('SDK 2.0: lấy theo nhãn loại giấy', () {
      expect(PosIminPrinter.paperMmFromSdk(1, ['80mm', '58mm']), 58);
      expect(PosIminPrinter.paperMmFromSdk(0, ['80mm', '58mm']), 80);
      expect(PosIminPrinter.paperMmFromSdk(-1, ['58mm']), 58);
      expect(PosIminPrinter.paperMmFromSdk(3, ['a', 'b']), isNull);
      expect(PosIminPrinter.paperMmFromSdk(0, const []), isNull);
    });

    test('đoán theo model: M2 / Swift cầm tay 58mm, máy để bàn 80mm', () {
      PosIminInfo i(String model) => PosIminInfo(
            isImin: true,
            sdk: 1,
            model: model,
            buildModel: '',
            connectType: 'USB',
          );
      expect(i('M2-202').looksLike58mm, isTrue);
      expect(i('M2 Pro').looksLike58mm, isTrue);
      expect(i('Swift 2 Pro').looksLike58mm, isTrue);
      expect(i('D4-503').looksLike58mm, isFalse);
      expect(i('Swan 2').looksLike58mm, isFalse);
      expect(i('Falcon 1').looksLike58mm, isFalse);
    });

    test('mã trạng thái: in được với 0 / 8 / chưa rõ', () {
      expect(PosIminPrinter.statusMessage(0), isNull);
      expect(PosIminPrinter.statusMessage(8), isNull);
      expect(PosIminPrinter.statusMessage(-1), isNull);
      expect(PosIminPrinter.statusMessage(7), contains('hết giấy'));
      expect(PosIminPrinter.statusMessage(3), contains('mở nắp'));
    });
  });

  group('Tự nhận máy in iMin', () {
    test('máy iMin → thêm máy in hóa đơn kiểu iMin, đúng khổ', () {
      final r = _plan(imin: true, paper: 'K58');
      expect(r, hasLength(1));
      expect(r.first.id, PosPrinterAutoDetect.iminProfileId);
      expect(r.first.connectionType, PosThermalConnectionType.imin);
      expect(r.first.printerBrand, PosThermalPrinterBrand.imin);
      expect(r.first.paperSize, 'K58');
      expect(r.first.roles, {PosLocalPrinterRoles.saleInvoice});
    });

    test('không phải iMin → không thêm', () {
      expect(_plan(), isEmpty);
    });

    test('đã có / đã xóa / đã có máy hóa đơn khác → không thêm', () {
      const iminProfile = PosLocalPrinterProfile(
          id: 'a', name: 'I', connectionType: PosThermalConnectionType.imin);
      const usbInvoice = PosLocalPrinterProfile(
        id: 'b',
        name: 'USB',
        connectionType: PosThermalConnectionType.usb,
        roles: {PosLocalPrinterRoles.saleInvoice},
      );
      expect(_plan(imin: true, existing: const [iminProfile]), isEmpty);
      expect(_plan(imin: true, ignored: {PosPrinterAutoDetect.iminIgnoreKey}), isEmpty);
      expect(
        _plan(imin: true, existing: const [usbInvoice])
            .where((p) => p.connectionType == PosThermalConnectionType.imin),
        isEmpty,
      );
    });

    test('máy iMin: máy in trong hiện qua USB không thêm trùng; máy USB ngoài vẫn thêm', () {
      final r = _plan(imin: true, devices: [
        _usb(0x0519, 0x2013, '/dev/bus/usb/001/002'), // máy in trong iMin
        _usb(0x0FE6, 0x811E, '/dev/bus/usb/001/003'), // máy USB ngoài
      ]);
      expect(r.map((p) => p.connectionType),
          [PosThermalConnectionType.imin, PosThermalConnectionType.usb]);
    });

    test('máy không phải iMin: cùng VID:PID vẫn là máy in USB bình thường', () {
      final r = _plan(devices: [_usb(0x28E9, 0x028D, '/dev/bus/usb/001/002')]);
      expect(r, hasLength(1));
      expect(r.first.connectionType, PosThermalConnectionType.usb);
    });
  });

  group('Đồng bộ cloud', () {
    test('Imin ↔ PosThermalConnectionType.imin', () {
      final p = PosStorePrinter.fromJson({
        'id': 'x',
        'name': 'Máy in iMin (máy này)',
        'connectionType': 'Imin',
        'printerBrand': 'imin',
        'paperSize': 'K58',
        'isDeviceLocal': true,
      });
      expect(p.isImin, isTrue);
      expect(p.looksLikeReceiptPrinter, isTrue);
      final s = toThermalSettings(p);
      expect(s.connectionType, PosThermalConnectionType.imin);
      expect(s.printerBrand, PosThermalPrinterBrand.imin);
      expect(s.resolvedTextMode, PosThermalTextMode.image);
      expect(thermalToPrinterSaveJson(s, name: 'x')['connectionType'], 'Imin');
    });
  });

  group('Gửi in qua kênh iMin', () {
    final calls = <MethodCall>[];
    var status = 0;

    setUp(() {
      calls.clear();
      status = 0;
      PosIminPrinter.debugAssumeAndroid = true;
      PosIminPrinter.resetCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PosIminPrinter.channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'info':
            return {
              'isImin': true,
              'sdk': 2,
              'model': 'Swan 2',
              'buildModel': 'I23M02',
              'connectType': 'SERVICE',
            };
          case 'print':
            return {'ok': status == 0, 'status': status};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PosIminPrinter.channel, null);
      PosIminPrinter.debugAssumeAndroid = false;
      PosIminPrinter.resetCache();
    });

    test('gửi nguyên ESC/POS, ESC p cuối được gỡ và mở két bằng API iMin', () async {
      final body = [0x1B, 0x40, 0x41, 0x0A, 0x1D, 0x56, 0x42, 0x00];
      final kick = [0x1B, 0x70, 0x00, 0x19, 0xFA];
      final ok = await PosPrinterTransport.send(
        connectionType: PosThermalConnectionType.imin,
        bytes: [...body, ...kick],
      );
      expect(ok, isTrue);
      final print = calls.singleWhere((c) => c.method == 'print');
      final args = print.arguments as Map;
      expect((args['bytes'] as Uint8List).toList(), body);
      expect(args['openDrawer'], isTrue);
    });

    test('hết giấy → báo lỗi, giữ mã trạng thái', () async {
      status = 7;
      final ok = await PosPrinterTransport.send(
        connectionType: PosThermalConnectionType.imin,
        bytes: const [0x1B, 0x40, 0x0A],
      );
      expect(ok, isFalse);
      expect(PosPrinterTransport.lastIminStatus, 7);
      final args = calls.singleWhere((c) => c.method == 'print').arguments as Map;
      expect(args['openDrawer'], isFalse);
    });
  });
}
