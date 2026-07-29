import 'package:flutter/material.dart';

/// Corner radius tokens (controls 8–12, cards 12–16).
abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;

  static BorderRadius get control => BorderRadius.circular(md);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get pill => BorderRadius.circular(999);

  static RoundedRectangleBorder shape([double r = lg]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
}
