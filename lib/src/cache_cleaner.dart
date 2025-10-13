import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Mixin with helpers to clear application temporary/cache directories.
///
/// Use this in widgets that generate temporary files (for example recorded
/// video fragments) to keep the application's cache tidy after producing the
/// final output.
///
/// Example:
///
/// ```dart
/// class MyWidgetState extends State<MyWidget> with CacheCleanerMixin { ... }
/// ```
mixin CacheCleanerMixin {
  bool _clearing = false;
  Future<void> clearAppCache() async {
    if (_clearing) return;
    _clearing = true;
    try {
      final cacheDir = await getTemporaryDirectory();
      await _wipeDir(cacheDir);

      try {
        final extCaches = await getExternalCacheDirectories();
        if (extCaches != null) {
          for (final d in extCaches) {
            await _wipeDir(d);
          }
        }
      } catch (_) {}
    } catch (_) {
    } finally {
      _clearing = false;
    }
  }

  Future<void> _wipeDir(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      final stream = dir.list(followLinks: false);
      await for (final entity in stream) {
        try {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          } else if (entity is Link) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}
