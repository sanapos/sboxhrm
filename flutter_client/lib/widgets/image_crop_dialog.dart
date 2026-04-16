import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Kết quả crop ảnh
class CropResult {
  final List<int> bytes;
  final String fileName;

  CropResult({required this.bytes, required this.fileName});
}

/// Tỉ lệ crop
enum CropAspectRatio {
  square,   // 1:1
  idCard,   // 85.6:53.98 ≈ 1.586
  free,     // tự do
}

/// Dialog cắt ảnh đơn giản
/// Trên web, do không có thư viện crop native, dialog này hiển thị preview
/// và cho phép xác nhận sử dụng ảnh gốc.
class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String fileName;
  final CropAspectRatio aspectRatio;
  final String title;

  const ImageCropDialog({
    super.key,
    required this.imageBytes,
    required this.fileName,
    this.aspectRatio = CropAspectRatio.free,
    this.title = 'Cắt ảnh',
  });

  /// Hiển thị dialog crop ảnh
  static Future<CropResult?> show(
    BuildContext context, {
    required List<int> imageBytes,
    required String fileName,
    CropAspectRatio aspectRatio = CropAspectRatio.free,
    String title = 'Cắt ảnh',
  }) async {
    return showDialog<CropResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImageCropDialog(
        imageBytes: Uint8List.fromList(imageBytes),
        fileName: fileName,
        aspectRatio: aspectRatio,
        title: title,
      ),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  late Uint8List _currentBytes;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.6).clamp(300.0, 700.0);
    final dialogHeight = (size.height * 0.7).clamp(300.0, 600.0);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.crop, color: Colors.blue),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Aspect ratio info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.aspect_ratio, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    _aspectRatioLabel,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Image preview
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[100],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: Center(
                      child: widget.aspectRatio == CropAspectRatio.square
                          ? AspectRatio(
                              aspectRatio: 1.0,
                              child: ClipOval(
                                child: Image.memory(
                                  _currentBytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          : Image.memory(
                              _currentBytes,
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Xem trước ảnh sẽ được sử dụng',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              CropResult(
                bytes: _currentBytes.toList(),
                fileName: widget.fileName,
              ),
            );
          },
          icon: const Icon(Icons.check),
          label: const Text('Sử dụng ảnh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  String get _aspectRatioLabel {
    switch (widget.aspectRatio) {
      case CropAspectRatio.square:
        return 'Tỉ lệ 1:1 (vuông)';
      case CropAspectRatio.idCard:
        return 'Tỉ lệ thẻ CCCD';
      case CropAspectRatio.free:
        return 'Tỉ lệ tự do';
    }
  }
}
