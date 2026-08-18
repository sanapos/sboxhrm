import 'dart:async';

import 'package:flutter/material.dart';

import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Thiết lập danh sách ghi chú nhanh trên màn hàng hóa.
class PosSaleQuickNotesListEditor extends StatelessWidget {
  const PosSaleQuickNotesListEditor({
    super.key,
    required this.notes,
    required this.onChanged,
  });

  final List<String> notes;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...notes.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: e.value,
                    decoration: InputDecoration(
                      hintText: tr('VD: Ít đường, Nóng, Mang về…'),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: PosTheme.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) {
                      final next = List<String>.from(notes);
                      next[e.key] = v;
                      onChanged(next);
                    },
                  ),
                ),
                IconButton(
                  tooltip: tr('Xóa'),
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  onPressed: () {
                    final next = List<String>.from(notes)..removeAt(e.key);
                    onChanged(next);
                  },
                ),
              ],
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => onChanged([...notes, '']),
          icon: const Icon(Icons.add, size: 18),
          label: Text(tr('Thêm ghi chú nhanh')),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kiotBlue,
            side: const BorderSide(color: _kiotBlue),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('Ghi chú này hiển thị dạng chip khi bán hàng — có thể chọn nhiều mục.'),
          style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
        ),
      ],
    );
  }
}

/// Chọn nhiều ghi chú nhanh khi bán hàng.
class PosLineQuickNotesPicker extends StatelessWidget {
  const PosLineQuickNotesPicker({
    super.key,
    required this.quickNotes,
    required this.selected,
    required this.onSelectedChanged,
    required this.extraController,
    required this.onExtraChanged,
    this.onAddQuickNote,
  });

  final List<String> quickNotes;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelectedChanged;
  final TextEditingController extraController;
  final VoidCallback onExtraChanged;
  /// Lưu ghi chú thành chip của món (catalog + lần sau gợi ý).
  final Future<void> Function(String note)? onAddQuickNote;

  Future<void> _addQuickNote(BuildContext context) async {
    var text = extraController.text.trim();
    if (text.isEmpty) {
      final ctrl = TextEditingController();
      final typed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Thêm ghi chú nhanh')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(
              hintText: tr('VD: Ít đá, Không cay, Mang về…'),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Hủy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr('Lưu')),
            ),
          ],
        ),
      );
      if (typed == null || typed.isEmpty) return;
      text = typed;
    }
    extraController.clear();
    onExtraChanged();
    final next = Set<String>.from(selected)..add(text);
    onSelectedChanged(next);
    await onAddQuickNote?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr('Ghi chú nhanh'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_addQuickNote(context)),
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr('Thêm ghi chú nhanh'),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: _kiotBlue,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ],
        ),
        if (quickNotes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: quickNotes.map((note) {
              final active = selected.contains(note);
              return FilterChip(
                label: Text(tr(note), style: const TextStyle(fontSize: 12)),
                selected: active,
                showCheckmark: true,
                selectedColor: PosTheme.kiotBlueLight,
                checkmarkColor: _kiotBlue,
                side: BorderSide(
                  color: active ? _kiotBlue : PosTheme.border,
                ),
                onSelected: (v) {
                  final next = Set<String>.from(selected);
                  if (v) {
                    next.add(note);
                  } else {
                    next.remove(note);
                  }
                  onSelectedChanged(next);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 6),
        TextField(
          controller: extraController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: tr(quickNotes.isEmpty
                ? 'Ghi chú dòng hàng'
                : 'Ghi chú khác (tùy chọn)'),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: (_) => onExtraChanged(),
        ),
      ],
    );
  }
}
