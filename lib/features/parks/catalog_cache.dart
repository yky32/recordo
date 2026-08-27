import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:recordo/features/parks/park.dart';

/// On-disk catalog snapshot. Play local; replace only when version is newer.
class CatalogDump {
  const CatalogDump({
    required this.version,
    required this.parks,
    this.parkCount,
    this.updatedAt,
    this.pricesUpdatedAt,
  });

  final int version;
  final List<Park> parks;
  final int? parkCount;
  final DateTime? updatedAt;
  final DateTime? pricesUpdatedAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'parkCount': parkCount ?? parks.length,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'pricesUpdatedAt': pricesUpdatedAt?.toUtc().toIso8601String(),
        'parks': parks.map((p) => p.toJson()).toList(),
      };

  static CatalogDump? parse(dynamic raw) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final list = m['parks'] as List? ?? const [];
    final parks = <Park>[];
    for (final e in list) {
      if (e is! Map) continue;
      parks.add(Park.fromJson(Map<String, dynamic>.from(e)));
    }
    final version = jsonInt(m['version']);
    if (parks.isEmpty && version <= 0) return null;
    return CatalogDump(
      version: version,
      parks: parks,
      parkCount: jsonInt(m['parkCount'], parks.length),
      updatedAt: m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt'].toString())
          : null,
      pricesUpdatedAt: m['pricesUpdatedAt'] != null
          ? DateTime.tryParse(m['pricesUpdatedAt'].toString())
          : null,
    );
  }
}

class CatalogMeta {
  const CatalogMeta({required this.version, this.pricesUpdatedAt});
  final int version;
  final DateTime? pricesUpdatedAt;
}

enum CatalogSyncResult { offline, unchanged, updated }

class CatalogCache {
  CatalogCache({Directory? directory}) : _override = directory;

  final Directory? _override;

  Future<Directory> _dir() async {
    final override = _override;
    if (override != null) return override;
    final root = await getApplicationSupportDirectory();
    final d = Directory('${root.path}/catalog');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}/parks_v1.json');
  }

  Future<CatalogDump?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      return CatalogDump.parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(CatalogDump dump) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(dump.toJson()), flush: true);
    if (await f.exists()) {
      await f.delete();
    }
    await tmp.rename(f.path);
  }
}

/// True when the local snapshot is missing or older than cloud.
bool catalogNeedsDump({
  required int localVersion,
  required int remoteVersion,
  required int localCount,
}) {
  if (localCount <= 0) return true;
  return remoteVersion > localVersion;
}
