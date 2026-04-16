import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PickedImageResult {
  final Uint8List bytes;
  final String name;
  const PickedImageResult(this.bytes, this.name);
}

/// Shows Camera / Gallery bottom sheet on mobile.
/// On web, directly opens file picker (no camera).
Future<List<PickedImageResult>?> pickImagesWithCamera(
  BuildContext context, {
  bool allowMultiple = false,
  List<String>? allowedExtensions,
}) async {
  if (kIsWeb) {
    return _pickFromGallery(
      allowMultiple: allowMultiple,
      allowedExtensions: allowedExtensions,
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
              title: const Text('Chụp ảnh'),
              subtitle: const Text('Sử dụng camera để chụp'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.photo_library, color: Colors.green),
              ),
              title: const Text('Chọn từ thư viện'),
              subtitle: const Text('Chọn ảnh có sẵn trong máy'),
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
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    return [PickedImageResult(Uint8List.fromList(bytes), photo.name)];
  }

  return _pickFromGallery(
    allowMultiple: allowMultiple,
    allowedExtensions: allowedExtensions,
  );
}

Future<List<PickedImageResult>?> _pickFromGallery({
  bool allowMultiple = false,
  List<String>? allowedExtensions,
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
      .map((f) => PickedImageResult(Uint8List.fromList(f.bytes!), f.name))
      .toList();
}
