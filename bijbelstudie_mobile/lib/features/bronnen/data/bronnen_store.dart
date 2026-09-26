import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where fetched Bronnen payloads live on the device: one JSON document per
/// key (`index`, `work.<slug>`).
///
/// Its own small file store rather than a row in the chapter cache: that cache
/// evicts by size, and a catechism someone reads on the train must still be
/// there next month. A whole work is a few hundred KB at most, so plain files
/// are enough; no schema, nothing to migrate.
abstract class BronnenStore {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> body);
}

class FileBronnenStore implements BronnenStore {
  FileBronnenStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;
  Directory? _dir;

  Future<Directory> _open() async {
    final cached = _dir;
    if (cached != null) return cached;
    final dir = Directory(p.join((await _root()).path, 'bronnen'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Slugs are kebab-case already; this only keeps a hostile or odd key from
  /// ever naming a path outside the folder.
  static String fileNameFor(String key) =>
      '${key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.json';

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final file = File(p.join((await _open()).path, fileNameFor(key)));
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      // A torn or unreadable file is the same as no file: fetch again.
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> body) async {
    try {
      final dir = await _open();
      final target = File(p.join(dir.path, fileNameFor(key)));
      // Write beside, then rename: a crash mid-write never leaves half a work.
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(body), flush: true);
      await temp.rename(target.path);
    } catch (_) {
      // Nothing cached means the next open fetches again; not worth a failure.
    }
  }
}
