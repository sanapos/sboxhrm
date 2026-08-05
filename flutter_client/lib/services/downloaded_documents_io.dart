import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isAndroid => !kIsWeb && Platform.isAndroid;

Future<void> ensureDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) await dir.create(recursive: true);
}

Future<bool> dirExists(String path) async => Directory(path).exists();

bool fileExists(String path) => File(path).existsSync();

Future<String?> readStringIfExists(String path) async {
  final f = File(path);
  if (!await f.exists()) return null;
  return f.readAsString();
}

Future<void> writeString(String path, String content) async {
  await File(path).writeAsString(content);
}

Future<void> writeBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes);
}

Future<List<int>> readBytes(String path) => File(path).readAsBytes();

Future<DateTime> lastModified(String path) => File(path).lastModified();

Future<void> renameFile(String from, String to) async {
  await File(from).rename(to);
}

Future<void> deleteFileIfExists(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}

Future<List<String>> listFiles(String dirPath) async {
  final dir = Directory(dirPath);
  final out = <String>[];
  await for (final entity in dir.list(recursive: false)) {
    if (entity is File) out.add(entity.path);
  }
  return out;
}

String basename(String path) =>
    path.split(Platform.pathSeparator).last;
