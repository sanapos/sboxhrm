import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../utils/pos_html_print.dart';
import '../widgets/notification_overlay.dart';

/// Xuất / chia sẻ báo giá: Excel, Word, PDF (in), Zalo, Email, Facebook.
class PosQuoteExport {
  PosQuoteExport._();

  static Future<void> exportExcel(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
  }) async {
    final bytes = await ApiService().downloadPosQuoteExport(
      quoteId,
      'excel',
      includeImages: includeImages,
    );
    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không tạo file Excel'),
      );
      return;
    }
    final name = 'BaoGia_$quoteNo.xlsx';
    await saveAndOpenFileBytes(
      bytes,
      name,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    NotificationOverlayManager().showSuccess(
      title: 'Đã xuất Excel',
      message: name,
    );
  }

  static Future<void> exportWord(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
  }) async {
    final bytes = await ApiService().downloadPosQuoteExport(
      quoteId,
      'word',
      includeImages: includeImages,
    );
    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không tạo file Word'),
      );
      return;
    }
    final name = 'BaoGia_$quoteNo.doc';
    await saveAndOpenFileBytes(bytes, name, 'application/msword');
    NotificationOverlayManager().showSuccess(
      title: 'Đã xuất Word',
      message: name,
    );
  }

  static Future<void> exportPdf(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    bool includeImages = false,
  }) async {
    final html = await ApiService().fetchPosQuoteExportHtml(
      quoteId,
      includeImages: includeImages,
    );
    if (!context.mounted) return;
    if (html == null || html.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không xuất được',
        message: tr('Không mở xem trước in PDF'),
      );
      return;
    }
    await showPosHtmlPrintDialog(
      context,
      title: 'BÁO GIÁ $quoteNo',
      htmlDocument: html,
      a4Paper: true,
    );
  }

  static Future<void> shareQuote(
    BuildContext context, {
    required String quoteId,
    required String quoteNo,
    required String customerName,
    required String channel,
    bool includeImages = false,
  }) async {
    final bytes = await ApiService().downloadPosQuoteExport(
      quoteId,
      'word',
      includeImages: includeImages,
    );
    final summary =
        'Báo giá $quoteNo — $customerName\nVui lòng xem file đính kèm.';
    final name = 'BaoGia_$quoteNo.doc';
    final fileBytes = bytes == null ? null : Uint8List.fromList(bytes);

    switch (channel) {
      case 'email':
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
            subject: 'Báo giá $quoteNo',
          );
        } else {
          final uri = Uri.parse(
            'mailto:?subject=${Uri.encodeComponent('Báo giá $quoteNo')}'
            '&body=${Uri.encodeComponent(summary)}',
          );
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'zalo':
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
          );
        } else {
          final uri = Uri.parse(
              'https://zalo.me/share?url=${Uri.encodeComponent(summary)}');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'facebook':
        final uri = Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?quote=${Uri.encodeComponent(summary)}',
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        break;
      default:
        if (fileBytes != null && fileBytes.isNotEmpty) {
          await Share.shareXFiles(
            [
              XFile.fromData(
                fileBytes,
                name: name,
                mimeType: 'application/msword',
              ),
            ],
            text: summary,
          );
        } else {
          await Share.share(summary);
        }
    }
  }
}
