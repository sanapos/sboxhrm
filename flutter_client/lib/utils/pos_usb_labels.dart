import 'pos_thermal_printer_settings.dart';
import 'pos_usb_printer.dart';

/// Tên cổng USB dễ đọc (thay vì `/dev/bus/usb/001/007`).
class PosUsbLabels {
  PosUsbLabels._();

  static String portLabel(String? deviceName) {
    final raw = (deviceName ?? '').trim();
    if (raw.isEmpty) return 'Cổng USB';
    final m = RegExp(r'/bus/usb/(\d+)/(\d+)\s*$', caseSensitive: false)
        .firstMatch(raw);
    if (m != null) {
      final bus = int.tryParse(m.group(1)!) ?? 0;
      final addr = int.tryParse(m.group(2)!) ?? 0;
      return 'Cổng USB $bus-$addr';
    }
    final m2 = RegExp(r'usb/(\d+)/(\d+)', caseSensitive: false).firstMatch(raw);
    if (m2 != null) {
      final bus = int.tryParse(m2.group(1)!) ?? 0;
      final addr = int.tryParse(m2.group(2)!) ?? 0;
      return 'Cổng USB $bus-$addr';
    }
    if (raw.startsWith('/dev/')) {
      return 'Cổng USB ${raw.split('/').last}';
    }
    return raw;
  }

  static String brandLabel({
    required int vendorId,
    required int productId,
    String? manufacturer,
    String? product,
  }) {
    final blob =
        '${manufacturer ?? ''} ${product ?? ''}'.toLowerCase();
    if (blob.contains('xprinter') || blob.contains('xp-')) {
      return _productOr('Xprinter', product);
    }
    if (blob.contains('zywell') || blob.contains('zp-')) {
      return _productOr('Zywell', product);
    }
    if (blob.contains('hprt') || blob.contains('pos80') || blob.contains('tp80')) {
      return _productOr('HPRT', product);
    }
    if (blob.contains('epson')) return _productOr('Epson', product);
    if (blob.contains('sunmi')) return _productOr('Sunmi', product);
    if (blob.contains('rongta') || blob.contains('rp80')) {
      return _productOr('Rongta', product);
    }

    switch (vendorId) {
      case 0x0FE6:
      case 0x2D84:
        return _productOr('HPRT', product);
      case 0x28E9:
        return _productOr('Zywell', product);
      case 0x0416:
      case 0x0483:
      case 0x1FC9:
        return _productOr('Xprinter', product);
      case 0x04B8:
        return _productOr('Epson', product);
      case 0x0525:
      case 0x2730:
        return _productOr('Sunmi', product);
      default:
        final p = (product ?? '').trim();
        if (p.isNotEmpty) return p;
        final m = (manufacturer ?? '').trim();
        if (m.isNotEmpty) return m;
        return 'USB nhiệt';
    }
  }

  static PosThermalPrinterBrand? brandEnum({
    required int vendorId,
    String? manufacturer,
    String? product,
  }) {
    final blob = '${manufacturer ?? ''} ${product ?? ''}'.toLowerCase();
    if (blob.contains('xprinter') || blob.contains('xp-')) {
      return PosThermalPrinterBrand.xprinter;
    }
    if (blob.contains('zywell') || blob.contains('zp-')) {
      return PosThermalPrinterBrand.zywell;
    }
    if (blob.contains('hprt')) return PosThermalPrinterBrand.hprt;
    if (blob.contains('epson')) return PosThermalPrinterBrand.epson;
    if (blob.contains('sunmi')) return PosThermalPrinterBrand.sunmi;
    switch (vendorId) {
      case 0x0FE6:
      case 0x2D84:
        return PosThermalPrinterBrand.hprt;
      case 0x28E9:
        return PosThermalPrinterBrand.zywell;
      case 0x0416:
      case 0x0483:
      case 0x1FC9:
        return PosThermalPrinterBrand.xprinter;
      case 0x04B8:
        return PosThermalPrinterBrand.epson;
      default:
        return null;
    }
  }

  static String title(PosUsbDevice d) {
    final brand = brandLabel(
      vendorId: d.vendorId,
      productId: d.productId,
      manufacturer: d.manufacturerName,
      product: d.productName,
    );
    return '$brand · ${portLabel(d.deviceName)}';
  }

  static String subtitle(PosUsbDevice d) {
    final bits = <String>[
      if (!d.hasPermission) 'chưa cấp quyền',
      if ((d.serialNumber ?? '').trim().isNotEmpty)
        'SN ${d.serialNumber!.trim()}',
    ];
    return bits.isEmpty ? 'Máy in USB' : bits.join(' · ');
  }

  /// Nhãn khi đã lưu `stableId|deviceName` mà chưa khớp máy sống.
  static String fromSavedRaw(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'Chưa chọn cổng USB';
    final ref = PosUsbSavedRef.parse(s);
    if ((ref.deviceName ?? '').isNotEmpty) {
      return portLabel(ref.deviceName);
    }
    return s.contains('|') ? s.split('|').last : s;
  }

  static String _productOr(String brand, String? product) {
    final p = (product ?? '').trim();
    if (p.isEmpty) return brand;
    if (p.toLowerCase().contains(brand.toLowerCase())) return p;
    return '$brand $p';
  }
}
