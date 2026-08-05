bool get isAndroid => false;

Future<void> ensureDir(String path) async {}

Future<bool> dirExists(String path) async => false;

bool fileExists(String path) => false;

Future<String?> readStringIfExists(String path) async => null;

Future<void> writeString(String path, String content) async {}

Future<void> writeBytes(String path, List<int> bytes) async {}

Future<List<int>> readBytes(String path) async => <int>[];

Future<DateTime> lastModified(String path) async => DateTime.now();

Future<void> renameFile(String from, String to) async {}

Future<void> deleteFileIfExists(String path) async {}

Future<List<String>> listFiles(String dirPath) async => <String>[];

String basename(String path) {
  final i = path.replaceAll('\\', '/').lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}
