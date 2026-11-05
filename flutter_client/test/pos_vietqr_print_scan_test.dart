import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/cash_transaction.dart';
import 'package:zkteco_flutter_client/utils/pos_einvoice_qr.dart';
import 'package:zkteco_flutter_client/utils/pos_print_code_lines.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_bitmap.dart';
import 'package:zkteco_flutter_client/utils/pos_vietqr_helper.dart';

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

/// Các khối GS v 0 ghép thành một ảnh — đúng các điểm gửi xuống máy in.
_Bitmap _rasterBitmap(List<int> bytes) {
  final ink = <bool>[];
  var w = 0;
  var i = 0;
  while (i + 8 <= bytes.length) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
      final bpr = bytes[i + 4] + (bytes[i + 5] << 8);
      final rows = bytes[i + 6] + (bytes[i + 7] << 8);
      w = bpr * 8;
      var p = i + 8;
      for (var k = 0; k < bpr * rows; k++, p++) {
        for (var bit = 7; bit >= 0; bit--) {
          ink.add((bytes[p] >> bit) & 1 == 1);
        }
      }
      i = p;
    } else {
      i++;
    }
  }
  return _Bitmap(w, ink.length ~/ w, ink);
}

/// Tìm mã QR trong ảnh: mọi điểm của mọi ô phải đúng màu, viền trắng đủ 4 ô
/// (mép dưới có thể bị cắt hàng trắng cuối ảnh — ngoài ảnh coi như giấy trắng).
bool _hasExactQr(_Bitmap b, List<List<bool>> m, int module) {
  final side = m.length * module;
  final q = module * 4;
  bool matchAt(int ox, int oy) {
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (b.at(ox + x, oy + y) != m[y ~/ module][x ~/ module]) return false;
      }
    }
    for (var y = oy - q; y < oy + side + q && y < b.h; y++) {
      for (var x = ox - q; x < ox + side + q; x++) {
        final inside = x >= ox && x < ox + side && y >= oy && y < oy + side;
        if (!inside && b.at(x, y)) return false;
      }
    }
    return true;
  }

  for (var oy = q; oy + side <= b.h; oy++) {
    for (var ox = q; ox + side + q <= b.w; ox++) {
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

  test('ảnh QR: mỗi ô đúng số nguyên điểm, ô đen và ô trắng rộng như nhau', () async {
    final m = _matrix(payload);
    expect(m.length, 49); // chuỗi VietQR thường gặp: version 8
    for (final (size, module) in [(240, 4), (260, 4), (300, 5), (400, 7)]) {
      final b = await _pngBitmap((await posQrPngBytes(payload, size: size))!);
      expect(b.w, size);
      expect(_hasExactQr(b, m, module), isTrue, reason: 'size=$size');
    }
  });

  group('bill in ra (GS v 0): QR giữ đúng lưới điểm ở mọi vị trí dòng', () {
    for (final (paper, size, module) in [(384, 300, 5), (576, 300, 5), (576, 400, 7)]) {
      for (final pad in [0.0, 1.0, 3.0, 7.0]) {
        test('khổ $paper điểm, cỡ $size, lệch dòng $pad', () async {
          final lines = await posPrintCodeStepLines(
            PosPrintCompiledQr(imageUrl: url, size: size, caption: 'Quét VietQR thanh toán', amountText: '1.250.000'),
            paperDots: paper,
          );
          final raster = await PosThermalBitmapEncoder.receiptToRaster(
            [
              PosReceiptImageLine(text: 'Cửa hàng QA', bold: true, center: true, fontSize: 24, spaceBefore: pad),
              const PosReceiptImageLine(text: 'Tổng cộng', rightText: '1.250.000', fontSize: 23),
              ...lines,
            ],
            paperDots: paper,
          );
          expect(_hasExactQr(_rasterBitmap(raster!), _matrix(payload), module), isTrue);
        });
      }
    }
  });

  test('lối in không mẫu V2: QR vẽ đúng khổ, không co ảnh làm vỡ ô', () async {
    final raster = await PosThermalBitmapEncoder.networkPngToEscPos(url, maxWidth: 336);
    expect(_hasExactQr(_rasterBitmap(raster!), _matrix(payload), 5), isTrue);
  });

  test('mã HĐĐT («qrdata:») cũng đúng lưới', () async {
    const data = 'https://www.meinvoice.vn/tra-cuu/?sc=L4CXU6X0W0';
    final raster = await PosThermalBitmapEncoder.networkPngToEscPos(posInlineQrUrl(data), maxWidth: 260);
    final m = _matrix(data);
    expect(_hasExactQr(_rasterBitmap(raster!), m, 260 ~/ (m.length + 8)), isTrue);
  });
}
