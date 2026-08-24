import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import 'image_compress.dart';

class PickedImageResult {
  final Uint8List bytes;
  final String name;
  const PickedImageResult(this.bytes, this.name);
}

/// Bottom sheet: Chụp ảnh / Chọn thư viện (mobile). Web → file picker.
Future<PickedImageResult?> pickSingleImageWithCamera(
  BuildContext context, {
  List<String>? allowedExtensions,
  int maxEdge = 1200,
  int jpegQuality = 78,
}) async {
  final list = await pickImagesWithCamera(
    context,
    allowMultiple: false,
    allowedExtensions: allowedExtensions,
    maxEdge: maxEdge,
    jpegQuality: jpegQuality,
  );
  if (list == null || list.isEmpty) return null;
  return list.first;
}

/// Shows Camera / Gallery bottom sheet on mobile.
/// On web, directly opens file picker (no camera).
Future<List<PickedImageResult>?> pickImagesWithCamera(
  BuildContext context, {
  bool allowMultiple = false,
  List<String>? allowedExtensions,
  int maxEdge = 1200,
  int jpegQuality = 78,
}) async {
  if (kIsWeb) {
    return _pickFromGallery(
      allowMultiple: allowMultiple,
      allowedExtensions: allowedExtensions,
      maxEdge: maxEdge,
      jpegQuality: jpegQuality,
    );
  }

  final source = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.camera_alt, color: Colors.blue),
              ),
              title: Text(tr('Chụp ảnh')),
              subtitle: Text(tr('Sử dụng camera để chụp')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.photo_library, color: Colors.green),
              ),
              title: Text(tr('Chọn từ thư viện')),
              subtitle: Text(tr('Chọn ảnh có sẵn trong máy')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );

  if (source == null) return null;

  if (source == 'camera') {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxEdge.toDouble(),
      maxHeight: maxEdge.toDouble(),
      imageQuality: jpegQuality,
    );
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    final compressed = compressImageBytes(
      Uint8List.fromList(bytes),
      maxEdge: maxEdge,
      jpegQuality: jpegQuality,
    );
    return [
      PickedImageResult(compressed, jpegFileName(photo.name)),
    ];
  }

  return _pickFromGallery(
    allowMultiple: allowMultiple,
    allowedExtensions: allowedExtensions,
    maxEdge: maxEdge,
    jpegQuality: jpegQuality,
  );
}

Future<List<PickedImageResult>?> _pickFromGallery({
  bool allowMultiple = false,
  List<String>? allowedExtensions,
  int maxEdge = 1200,
  int jpegQuality = 78,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: allowedExtensions != null ? FileType.custom : FileType.image,
    allowedExtensions: allowedExtensions,
    allowMultiple: allowMultiple,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  return result.files
      .where((f) => f.bytes != null)
      .map((f) {
        final raw = Uint8List.fromList(f.bytes!);
        final compressed = compressImageBytes(
          raw,
          maxEdge: maxEdge,
          jpegQuality: jpegQuality,
        );
        final name = compressed.length < raw.length
            ? jpegFileName(f.name)
            : f.name;
        return PickedImageResult(compressed, name);
      })
      .toList();
}
