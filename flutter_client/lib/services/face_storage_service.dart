import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service to download and cache face registration images locally on the device.
/// Works like a face attendance machine - stores reference photos for comparison.
class FaceStorageService {
  final String baseUrl;
  
  FaceStorageService({required this.baseUrl});

  /// Get the local directory for cached face images
  Future<Directory> _getFaceCacheDir(String employeeId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final faceDir = Directory(p.join(appDir.path, 'face_cache', employeeId));
    if (!await faceDir.exists()) {
      await faceDir.create(recursive: true);
    }
    return faceDir;
  }

  /// Download and cache face registration images for an employee.
  /// Returns list of local file paths.
  /// Always re-downloads when the server URL list changes (handles re-registration).
  Future<List<String>> downloadAndCacheFaces(
    String employeeId,
    List<String> serverImageUrls,
  ) async {
    if (serverImageUrls.isEmpty) return [];

    final cacheDir = await _getFaceCacheDir(employeeId);
    
    // Check manifest to detect if server images changed (re-registration)
    final manifestFile = File(p.join(cacheDir.path, '_manifest.txt'));
    final newManifest = serverImageUrls.join('\n');
    bool needsRefresh = true;
    
    if (await manifestFile.exists()) {
      final oldManifest = await manifestFile.readAsString();
      if (oldManifest == newManifest) {
        // Same URLs — check if all files exist
        final existing = <String>[];
        for (int i = 0; i < serverImageUrls.length; i++) {
          final f = File(p.join(cacheDir.path, 'face_$i.jpg'));
          if (await f.exists() && await f.length() > 1000) {
            existing.add(f.path);
          }
        }
        if (existing.length == serverImageUrls.length) {
          debugPrint('Face cache up-to-date: ${existing.length} files');
          return existing;
        }
      }
    }
    
    // URLs changed or files missing — clear old cache and re-download
    if (needsRefresh) {
      debugPrint('Face cache refresh: clearing old files for $employeeId');
      try {
        await for (final entity in cacheDir.list()) {
          if (entity is File) await entity.delete();
        }
      } catch (_) {}
    }

    final cachedPaths = <String>[];

    for (int i = 0; i < serverImageUrls.length; i++) {
      final serverUrl = serverImageUrls[i];
      final fileName = 'face_$i.jpg';
      final localFile = File(p.join(cacheDir.path, fileName));

      try {
        final fullUrl = _resolveUrl(serverUrl);
        final response = await http.get(
          Uri.parse(fullUrl),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 && response.bodyBytes.length > 1000) {
          await localFile.writeAsBytes(response.bodyBytes);
          cachedPaths.add(localFile.path);
          debugPrint('Face cached: $fileName (${response.bodyBytes.length} bytes)');
        } else {
          debugPrint('Face download failed: $fullUrl → ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Face download error: $e');
      }
    }
    
    // Save manifest for future change detection
    if (cachedPaths.isNotEmpty) {
      await manifestFile.writeAsString(newManifest);
    }

    return cachedPaths;
  }

  /// Get cached face image paths for an employee.
  Future<List<String>> getCachedFacePaths(String employeeId) async {
    final cacheDir = await _getFaceCacheDir(employeeId);
    if (!await cacheDir.exists()) return [];

    final files = await cacheDir
        .list()
        .where((f) => f is File && f.path.endsWith('.jpg'))
        .map((f) => f.path)
        .toList();
    
    // Filter out invalid/empty files
    final validFiles = <String>[];
    for (final path in files) {
      final file = File(path);
      if (await file.exists() && await file.length() > 1000) {
        validFiles.add(path);
      }
    }
    return validFiles;
  }

  /// Check if face images are cached for an employee
  Future<bool> hasCachedFaces(String employeeId) async {
    final paths = await getCachedFacePaths(employeeId);
    return paths.isNotEmpty;
  }

  /// Clear cached face images for an employee (when re-registering)
  Future<void> clearCache(String employeeId) async {
    final cacheDir = await _getFaceCacheDir(employeeId);
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      debugPrint('Face cache cleared for $employeeId');
    }
  }

  /// Clear all face caches
  Future<void> clearAllCaches() async {
    final appDir = await getApplicationDocumentsDirectory();
    final faceDir = Directory(p.join(appDir.path, 'face_cache'));
    if (await faceDir.exists()) {
      await faceDir.delete(recursive: true);
    }
  }

  String _resolveUrl(String path) {
    if (path.startsWith('http')) return path;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$baseUrl/$cleanPath';
  }
}
