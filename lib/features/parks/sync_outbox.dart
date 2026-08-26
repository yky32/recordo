import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/supabase_park_remote.dart';

const kSyncOutboxMax = 80;
const kResumeSyncMin = Duration(seconds: 30);

bool resumeShouldSync(DateTime? last, DateTime now) {
  if (last == null) return true;
  return now.difference(last) >= kResumeSyncMin;
}

class SyncJob {
  const SyncJob({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  /// `price` or `park`.
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory SyncJob.fromJson(Map<String, dynamic> m) {
    final raw = m['payload'];
    return SyncJob(
      id: m['id'] as String? ?? 'job-${m.hashCode}',
      type: m['type'] as String? ?? 'price',
      payload: raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
      createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}

List<SyncJob> enqueueJob(
  List<SyncJob> queue,
  SyncJob job, {
  int max = kSyncOutboxMax,
}) {
  final next = [...queue, job];
  if (next.length <= max) return next;
  return next.sublist(next.length - max);
}

class SyncOutbox {
  List<SyncJob> read() {
    return Bootstrap.store
        .getJsonList(StorageKeys.syncOutbox)
        .map(SyncJob.fromJson)
        .toList();
  }

  Future<void> _write(List<SyncJob> jobs) {
    return Bootstrap.store.setJson(
      StorageKeys.syncOutbox,
      jobs.map((e) => e.toJson()).toList(),
    );
  }

  Future<void> enqueue(SyncJob job) async {
    await _write(enqueueJob(read(), job));
  }

  int get pendingCount => read().length;

  Future<int> flush(SupabaseParkRemote remote) async {
    final jobs = read();
    if (jobs.isEmpty) return 0;
    final kept = <SyncJob>[];
    var sent = 0;
    for (final job in jobs) {
      final ok = await _send(remote, job);
      if (ok) {
        sent++;
      } else {
        kept.add(job);
      }
    }
    await _write(kept);
    return sent;
  }

  Future<bool> _send(SupabaseParkRemote remote, SyncJob job) async {
    final p = job.payload;
    if (job.type == 'park') {
      return remote.insertUgcPark(
        Park(
          id: p['id'] as String? ?? job.id,
          name: p['name'] as String? ?? '未命名',
          district: p['district'] as String? ?? '香港',
          lat: jsonDouble(p['lat']) ?? 22.3193,
          lng: jsonDouble(p['lng']) ?? 114.1694,
          heightM: jsonDouble(p['heightM']),
          source: 'ugc-new',
        ),
        note: p['note'] as String? ?? '',
        address: p['address'] as String? ?? '',
      );
    }
    return remote.insertPriceReport(
      parkId: p['parkId'] as String? ?? '',
      hourly: jsonDouble(p['hourly']),
      daily: jsonDouble(p['daily']),
      night: jsonDouble(p['night']),
      priceNote: p['priceNote'] as String?,
      confirmOnly: p['confirmOnly'] == true,
    );
  }
}
