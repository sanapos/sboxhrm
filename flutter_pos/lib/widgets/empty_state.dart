import 'package:flutter/material.dart';
import '../utils/app_error_utils.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? Colors.grey[600];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: effectiveIconColor!.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: effectiveIconColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr(title),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                tr(description!),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(tr(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String title;
  final String? description;
  final VoidCallback? onRetry;
  final IconData? icon;
  final Color? iconColor;

  const ErrorState({
    super.key,
    this.title = 'Đã xảy ra lỗi',
    this.description,
    this.onRetry,
    this.icon,
    this.iconColor,
  });

  factory ErrorState.fromError(
    Object error, {
    VoidCallback? onRetry,
  }) {
    final info = AppErrorUtils.fromException(error);
    return ErrorState(
      title: info.title,
      description: info.message,
      onRetry: onRetry,
      icon: info.kind == AppErrorKind.network
          ? Icons.wifi_off_rounded
          : Icons.error_outline,
      iconColor: info.kind == AppErrorKind.network
          ? const Color(0xFFF59E0B)
          : Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = icon ?? Icons.error_outline;
    final effectiveIconColor = iconColor ?? Colors.red;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: effectiveIconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                effectiveIcon,
                size: 64,
                color: effectiveIconColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tr(title),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                tr(description!),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr('Thử lại')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoDataState extends StatelessWidget {
  final String? message;
  final IconData? icon;

  const NoDataState({
    super.key,
    this.message,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon ?? Icons.inbox_outlined,
      title: 'Không có dữ liệu',
      description: message ?? 'Chưa có dữ liệu nào được thêm vào',
    );
  }
}

class NoSearchResultState extends StatelessWidget {
  final String? searchTerm;
  final VoidCallback? onClear;

  const NoSearchResultState({
    super.key,
    this.searchTerm,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off,
                size: 64,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 24),
            Text(tr('Không tìm thấy kết quả'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr(searchTerm != null
                  ? 'Không tìm thấy kết quả cho "$searchTerm"'
                  : 'Không có kết quả phù hợp với tiêu chí tìm kiếm'),
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (onClear != null) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: Text(tr('Xóa bộ lọc')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
