import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/cash_transaction.dart';
import 'package:sbox_pos/utils/pos_einvoice_qr.dart';
import 'package:sbox_pos/utils/pos_thermal_bitmap.dart';
import 'package:sbox_pos/utils/pos_vietqr_helper.dart';

/// Ma trận ô QR đúng theo thư viện (true = đen).
List<List<bool>> _matrix(String data) {
  final qr = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium);
  const probe = 100000.0;
  final rowH = qr.make(data, width: probe, height: probe).whereType<BarcodeBar>().first.height;
  final n = (probe / rowH).round();
  final m = List.generate(n, (_) => List.filled(n, false));
  for (final e in qr.make(data, width: n.toDouble(), height: n.toDouble()).whereType<BarcodeBar>()) {
    if (!e.black) continue;
    final y = e.top.round();
    for (var x = e.left.round(); x < (e.left + e.width).round(); x++) {
      m[y][x] = true;
    }
  }
  return m;
}

class _Bitmap {
  _Bitmap(this.w, this.h, this.ink);
  final int w;
  final int h;
  final List<bool> ink;
  bool at(int x, int y) => ink[y * w + x];
}

Future<_Bitmap> _pngBitmap(Uint8List png) async {
  final frame = await (await ui.instantiateImageCodec(png)).getNextFrame();
  final img = frame.image;
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  return _Bitmap(img.width, img.height, [for (var i = 0; i < rgba.length; i += 4) rgba[i] < 128]);
}

/// Khối GS v 0 → đúng các điểm gửi xuống máy in.
_Bitmap _rasterBitmap(List<int> bytes) {
  final bpr = bytes[4] + (bytes[5] << 8);
  final rows = bytes[6] + (bytes[7] << 8);
  final ink = <bool>[];
  for (var p = 8; p < 8 + bpr * rows; p++) {
    for (var bit = 7; bit >= 0; bit--) {
      ink.add((bytes[p] >> bit) & 1 == 1);
    }
  }
  return _Bitmap(bpr * 8, rows, ink);
}

/// Tìm mã QR trong ảnh: mọi điểm của mọi ô phải đúng màu (dưới mã có thể bị cắt hàng trắng cuối).
bool _hasExactQr(_Bitmap b, List<List<bool>> m, int module) {
  final side = m.length * module;
  bool matchAt(int ox, int oy) {
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (b.at(ox + x, oy + y) != m[y ~/ module][x ~/ module]) return false;
      }
    }
    return true;
  }

  for (var oy = 0; oy + side <= b.h; oy++) {
    for (var ox = 0; ox + side <= b.w; ox++) {
      if (b.at(ox, oy) && matchAt(ox, oy)) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final account = BankAccount(
    id: 'b1',
    accountName: 'CUA HANG QA',
    accountNumber: '0071000123456',
    bankCode: '970436',
    bankName: 'Vietcombank',
  );
  final url = account.generateVietQRUrl(amount: 1250000, description: 'POS HD270920260001');
  final payload = PosVietQrHelper.emvPayloadFromImageUrl(url)!;

  test('chuỗi sinh tại máy trùng từng ký tự với mã img.vietqr.io (đọc từ ảnh tải về 04/11/2026)', () {
    expect(
      PosVietQrHelper.emvPayload(
        bankBin: '970436',
        accountNumber: '0123456789',
        amount: 150000,
        description: 'POS DH0001',
      ),
      '00020101021238540010A00000072701240006970436011001234567890208QRIBFTTA530370454061500005802VN62140810POS DH000163046C5D',
    );
  });

  test('mã NH không phải BIN → dùng ảnh mạng như cũ', () {
    final vcb = BankAccount(
      id: 'b2',
      accountName: 'A',
      accountNumber: '123',
      bankCode: 'VCB',
      bankName: 'Vietcombank',
    ).generateVietQRUrl(amount: 1000);
    expect(PosVietQrHelper.emvPayloadFromImageUrl(vcb), isNull);
  });

  test('ảnh QR: mỗi ô đúng số nguyên điểm, ô đen và ô trắng rộng như nhau', () async {
    final m = _matrix(payload);
    expect(m.length, 49); // chuỗi VietQR thường gặp: version 8
    for (final (size, module) in [(240, 4), (300, 5), (400, 7)]) {
      final b = await _pngBitmap((await posQrPngBytes(payload, size: size))!);
      expect(b.w, size);
      expect(_hasExactQr(b, m, module), isTrue, reason: 'size=$size');
    }
  });

  test('máy LAN/USB (GS v 0): QR đúng lưới điểm ở các cỡ mẫu in', () async {
    final m = _matrix(payload);
    for (final (size, module) in [(300, 5), (400, 7)]) {
      final raster = await PosThermalBitmapEncoder.networkPngToEscPos(url, maxWidth: size);
      expect(_hasExactQr(_rasterBitmap(raster!), m, module), isTrue, reason: 'size=$size');
    }
  });

  test('Sunmi (ảnh căn giữa khổ giấy): QR đúng lưới điểm', () async {
    final m = _matrix(payload);
    for (final (paper, module) in [(384, 5), (576, 7)]) {
      final png = await PosThermalBitmapEncoder.qrCenteredOnPaper(url, paperDots: paper);
      final b = await _pngBitmap(png!);
      expect(b.w, paper);
      expect(_hasExactQr(b, m, module), isTrue, reason: 'paper=$paper');
    }
  });
}
