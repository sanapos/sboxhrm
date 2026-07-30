import '../models/pos_store_printer.dart';
import 'pos_barcode_print.dart';
import 'pos_label_printer_settings.dart';
import 'pos_thermal_printer_settings.dart';

/// Chuyển cấu hình máy in cloud → thiết lập thermal local để in.
PosThermalPrinterSettings toThermalSettings(PosStorePrinter printer) {
  PosThermalConnectionType conn;
  switch (printer.connectionType) {
    case 'Lan':
      conn = PosThermalConnectionType.lan;
      break;
    case 'Usb':
      conn = PosThermalConnectionType.usb;
      break;
    case 'Sunmi':
      conn = PosThermalConnectionType.sunmi;
      break;
    default:
      conn = PosThermalConnectionType.bluetooth;
  }

  // Sunmi: luôn brand + UTF-8 — tránh auto→image (chữ rác / giấy trắng dài qua printEscPos).
  final isSunmi = conn == PosThermalConnectionType.sunmi;
  final brand = isSunmi
      ? PosThermalPrinterBrand.sunmi
      : PosThermalPrinterBrand.fromKey(printer.printerBrand?.toLowerCase());
  final textMode = isSunmi
      ? PosThermalTextMode.utf8
      : PosThermalTextMode.fromKey(printer.textMode?.toLowerCase());

  return PosThermalPrinterSettings(
    enabled: true,
    connectionType: conn,
    printerBrand: brand,
    textMode: textMode,
    paperSize: printer.paperSize,
    bluetoothAddress: printer.bluetoothAddress,
    bluetoothName: printer.bluetoothName,
    lanHost: printer.lanHost,
    lanPort: printer.lanPort,
    usbDeviceName: printer.usbDeviceName,
    feedBeforeCut: printer.feedBeforeCut,
    partialCut: printer.partialCut,
    openCashDrawer: printer.openCashDrawer,
    openDrawerCashOnly: printer.openDrawerCashOnly,
    beepOnPrint: printer.beepOnPrint,
  );
}

/// Chuyển máy in tem cloud → thiết lập in tem local.
PosLabelPrinterSettings toLabelSettings(PosStorePrinter printer) {
  PosThermalConnectionType conn;
  switch (printer.connectionType) {
    case 'Lan':
      conn = PosThermalConnectionType.lan;
      break;
    case 'Usb':
      conn = PosThermalConnectionType.usb;
      break;
    case 'Sunmi':
      conn = PosThermalConnectionType.sunmi;
      break;
    default:
      conn = PosThermalConnectionType.bluetooth;
  }

  return PosLabelPrinterSettings(
    enabled: true,
    connectionType: conn,
    protocol: PosLabelPrinterProtocol.fromKey(printer.textMode?.toLowerCase()),
    templateId: printer.paperSize,
    dpi: 203,
    gapMm: printer.feedBeforeCut.clamp(1, 10).toDouble(),
    bluetoothAddress: printer.bluetoothAddress,
    bluetoothName: printer.bluetoothName,
    lanHost: printer.lanHost,
    lanPort: printer.lanPort,
    usbDeviceName: printer.usbDeviceName,
  );
}

Map<String, dynamic> thermalToPrinterSaveJson(
  PosThermalPrinterSettings s, {
  required String name,
  bool isDefault = false,
  int sortOrder = 0,
}) {
  String conn;
  switch (s.connectionType) {
    case PosThermalConnectionType.lan:
      conn = 'Lan';
      break;
    case PosThermalConnectionType.usb:
      conn = 'Usb';
      break;
    case PosThermalConnectionType.sunmi:
      conn = 'Sunmi';
      break;
    default:
      conn = 'Bluetooth';
  }

  return {
    'name': name,
    'connectionType': conn,
    'printerBrand': s.printerBrand.key,
    'paperSize': s.paperSize,
    'textMode': s.textMode.key,
    'bluetoothAddress': s.bluetoothAddress,
    'bluetoothName': s.bluetoothName,
    'lanHost': s.lanHost,
    'lanPort': s.lanPort,
    'usbDeviceName': s.usbDeviceName,
    'feedBeforeCut': s.feedBeforeCut,
    'partialCut': s.partialCut,
    'openCashDrawer': s.openCashDrawer,
    'openDrawerCashOnly': s.openDrawerCashOnly,
    'beepOnPrint': s.beepOnPrint,
    'isDefault': isDefault,
    'sortOrder': sortOrder,
    'isActive': true,
  };
}
