import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/main.dart';

void main() {
  testWidgets('App boots', (tester) async {
    await tester.pumpWidget(const SboxPosApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
