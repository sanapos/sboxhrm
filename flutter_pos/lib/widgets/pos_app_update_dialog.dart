import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../services/pos_app_update_service.dart';
import 'pos/pos_theme.dart';

/// Dialog cập nhật APK trong app (Android 6+ / không Play Store).
Future<void> showPosAppUpdateDialog(
  BuildContext context, {
  required PosAndroidRelease release,
  String? currentVersion,
  bool barrierDismissible = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible && !release.forceUpdate,
    builder: (ctx) => _PosAppUpdateDialog(
      release: release,
      currentVersion: currentVersion,
    ),
  );
}

/// Kiểm tra cập nhật sau login; hiện dialog nếu có bản mới.
Future<void> maybePromptPosAppUpdate(BuildContext context) async {
  final release = await PosAppUpdateService.checkForUpdate();
  if (release == null || !context.mounted) return;
  final info = await PosAppUpdateService.currentPackage();
  if (!context.mounted) return;
  await showPosAppUpdateDialog(
    context,
    release: release,
    currentVersion: '${info.version} (${info.buildNumber})',
    barrierDismissible: !release.forceUpdate,
  );
}

class _PosAppUpdateDialog extends StatefulWidget {
  const _PosAppUpdateDialog({
    required this.release,
    this.currentVersion,
  });

  final PosAndroidRelease release;
  final String? currentVersion;

  @override
  State<_PosAppUpdateDialog> createState() => _PosAppUpdateDialogState();
}

class _PosAppUpdateDialogState extends State<_PosAppUpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    final err = await PosAppUpdateService.downloadAndInstall(
      widget.release,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final sizeMb = r.apkBytes != null
        ? (r.apkBytes! / (1024 * 1024)).toStringAsFixed(1)
        : null;

    return AlertDialog(
      title: Text(tr('Có bản SBOX POS mới')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Phiên bản ${r.versionName} (${r.versionCode})'
              '${widget.currentVersion != null ? '\nHiện tại: ${widget.currentVersion}' : ''}'
              '${sizeMb != null ? '\nDung lượng: ~$sizeMb MB' : ''}',
            ),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          if ((r.releaseNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              tr(r.releaseNotes!.trim()),
              style: const TextStyle(
                fontSize: 13,
                color: PosTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 && _progress < 1 ? _progress : null,
              color: PosTheme.kiotBlue,
            ),
            const SizedBox(height: 6),
            Text(
              tr('Đang tải… ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              tr(_error!),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
        ],
      ),
      actions: [
        if (!r.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Để sau')),
          ),
        FilledButton.icon(
          onPressed: _downloading ? null : _download,
          style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
          icon: const Icon(Icons.system_update_alt, size: 18),
          label: Text(tr(_downloading ? 'Đang tải…' : 'Tải & cài đặt')),
        ),
      ],
    );
  }
}
