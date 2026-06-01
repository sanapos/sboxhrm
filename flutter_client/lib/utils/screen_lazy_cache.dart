import 'package:flutter/material.dart';

/// Caches lazily-built route screens by navigation index.
class ScreenLazyCache {
  final Map<int, Widget> _cache = {};

  Widget getOrCreate(int index, Widget Function() create) {
    return _cache.putIfAbsent(index, create);
  }

  void clear() => _cache.clear();
}
