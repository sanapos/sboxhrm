import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/comm_v2.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_comment_input.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_common.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_post.dart';
import 'package:zkteco_flutter_client/widgets/quill_a11y.dart';

/// Ô bình luận / ô soạn bài Truyền thông với Trợ năng và công cụ tự động.
SemanticsNode? _byId(WidgetTester tester, String id) {
  SemanticsNode? hit;
  bool visit(SemanticsNode n) {
    if (n.getSemanticsData().identifier == id) {
      hit = n;
      return false;
    }
    n.visitChildren(visit);
    return hit == null;
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return hit;
}

void main() {
  group('CommCommentField', () {
    late TextEditingController ctrl;
    late FocusNode focus;
    late int sent;

    Future<void> pump(WidgetTester tester) async {
      ctrl = TextEditingController();
      focus = FocusNode();
      sent = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CommCommentField(
            controller: ctrl,
            focusNode: focus,
            onSend: () => sent++,
            decoration: const InputDecoration(hintText: 'Viết bình luận…'),
          ),
        ),
      ));
    }

    testWidgets('mã định danh và nhãn vẫn còn khi ô đã có chữ', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Xin chào');
      await tester.pump();
      final node = _byId(tester, 'comm-comment-input');
      expect(node, isNotNull);
      final data = node!.getSemanticsData();
      // ignore: deprecated_member_use
      expect(data.hasFlag(SemanticsFlag.isTextField), isTrue, reason: 'mã định danh phải nằm trên chính ô nhập');
      expect(data.label, contains('Ô bình luận'));
      expect(data.value, 'Xin chào');
      expect(data.customSemanticsActionIds, isNotEmpty);
      handle.dispose();
    });

    testWidgets('Enter gửi, Shift+Enter không gửi', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
      expect(ctrl.text, 'abc');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sent, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(sent, 2);
    });

    testWidgets('nút hành động trên bàn phím ảo gửi', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, 1);
    });

    testWidgets('hành động Trợ năng «Gửi bình luận»', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      final node = _byId(tester, 'comm-comment-input')!;
      final id = node.getSemanticsData().customSemanticsActionIds!.first;
      tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.customAction, id);
      expect(sent, 1);
      handle.dispose();
    });
  });

  group('QuillA11y', () {
    late quill.QuillController ctrl;

    Future<SemanticsNode> pump(WidgetTester tester, String text) async {
      ctrl = quill.QuillController(
        document: text.isEmpty ? quill.Document() : (quill.Document()..insert(0, text)),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final focus = FocusNode();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [quill.FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: QuillA11y(
            controller: ctrl,
            focusNode: focus,
            identifier: 'comm-post-body',
            label: 'Nội dung bài viết',
            hint: 'Viết nội dung…',
            child: quill.QuillEditor(
              controller: ctrl,
              focusNode: focus,
              scrollController: ScrollController(),
              config: const quill.QuillEditorConfig(scrollable: false, expands: false),
            ),
          ),
        ),
      ));
      return _byId(tester, 'comm-post-body')!;
    }

    void setText(WidgetTester tester, SemanticsNode node, String text) =>
        tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.setText, text);

    testWidgets('là ô nhập chữ có lệnh Dán và Đặt chữ', (tester) async {
      final handle = tester.ensureSemantics();
      final node = await pump(tester, '');
      final data = node.getSemanticsData();
      // ignore: deprecated_member_use
      expect(data.hasFlag(SemanticsFlag.isTextField), isTrue);
      expect(data.hasAction(SemanticsAction.setText), isTrue);
      expect(data.hasAction(SemanticsAction.paste), isTrue);
      expect(data.label, 'Nội dung bài viết');
      expect(data.hint, 'Viết nội dung…');
      handle.dispose();
    });

    testWidgets('Đặt chữ vào ô trống', (tester) async {
      final handle = tester.ensureSemantics();
      final node = await pump(tester, '');
      setText(tester, node, 'Thông báo nghỉ lễ');
      await tester.pump();
      expect(quillPlainText(ctrl.document), 'Thông báo nghỉ lễ');
      expect(_byId(tester, 'comm-post-body')!.getSemanticsData().value, 'Thông báo nghỉ lễ');
      handle.dispose();
    });

    testWidgets('Đặt chữ không xoá nội dung đang có, giữ định dạng', (tester) async {
      final handle = tester.ensureSemantics();
      final node = await pump(tester, 'Xin chào');
      ctrl.formatText(0, 8, quill.Attribute.bold);

      // Công cụ nối thêm: chỉ chèn phần mới vào cuối.
      setText(tester, node, 'Xin chào mọi người');
      expect(quillPlainText(ctrl.document), 'Xin chào mọi người');
      expect(ctrl.document.toDelta().first.attributes, {'bold': true});

      // Chữ khác hẳn: chèn tại con trỏ, không xoá.
      ctrl.updateSelection(const TextSelection.collapsed(offset: 0), quill.ChangeSource.local);
      setText(tester, node, 'A ');
      expect(quillPlainText(ctrl.document), 'A Xin chào mọi người');

      // Chuỗi rỗng / trùng: không làm gì.
      setText(tester, node, '');
      setText(tester, node, 'A Xin chào mọi người');
      expect(quillPlainText(ctrl.document), 'A Xin chào mọi người');
      handle.dispose();
    });

    testWidgets('Dán qua Trợ năng chèn chữ từ bộ nhớ tạm', (tester) async {
      final handle = tester.ensureSemantics();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'chữ dán'};
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        return null;
      });
      final node = await pump(tester, '');
      tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.paste);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(quillPlainText(ctrl.document), 'chữ dán');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      handle.dispose();
    });
  });

  testWidgets('bong bóng bình luận hiện ảnh, ẩn dòng chữ rỗng', (tester) async {
    final c = CommComment.fromJson({
      'id': 'x',
      'userId': 'u',
      'userName': 'Lan',
      'content': '',
      'images': ['/stores/a/uploads/communications/1.jpg', '/stores/a/uploads/communications/2.jpg'],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    expect(c.images.length, 2);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommCommentBubble(comment: c))));
    await tester.pump();
    expect(find.byType(CommImageGrid), findsOneWidget);
    expect(find.byType(RichText).evaluate().where((e) => (e.widget as RichText).text.toPlainText().isEmpty), isEmpty);
  });
}
