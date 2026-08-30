import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/features/parks/catalog_cache.dart';
import 'package:recordo/features/parks/community_paid_session.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/meter_street.dart';

/// Cloud catalog + UGC writes. Safe no-op if not configured / offline.
class SupabaseParkRemote {
  Future<CatalogMeta?> fetchCatalogMeta() async {
    final c = RecordoSupabase.client;
    if (c == null) return null;
    try {
      final row = await c
          .from('catalog_meta')
          .select('version,prices_updated_at')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return null;
      final pricesRaw = row['prices_updated_at'];
      return CatalogMeta(
        version: jsonInt(row['version']),
        pricesUpdatedAt: pricesRaw != null
            ? DateTime.tryParse(pricesRaw.toString())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<int?> fetchCatalogVersion() async {
    return (await fetchCatalogMeta())?.version;
  }

  /// Single dump of the full catalog. Falls back to paged `parks` select.
  Future<CatalogDump?> fetchCatalogDump() async {
    final c = RecordoSupabase.client;
    if (c == null) return null;
    try {
      final raw = await c.rpc('catalog_dump');
      final dump = CatalogDump.parse(raw);
      if (dump != null && dump.parks.isNotEmpty) return dump;
    } catch (_) {}
    return _fetchCatalogPaged();
  }

  Future<List<MeterStreet>> fetchMetersDump() async {
    final c = RecordoSupabase.client;
    if (c == null) return const [];
    try {
      final raw = await c.rpc('meters_dump');
      final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (map == null) return const [];
      final list = map['meters'] as List? ?? const [];
      final out = <MeterStreet>[];
      for (final e in list) {
        if (e is! Map) continue;
        final m = MeterStreet.tryParse(Map<String, dynamic>.from(e));
        if (m != null) out.add(m);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Parks whose price_updated_at is after [since] (inclusive pad 1s).
  Future<List<Park>> fetchPricePatch({DateTime? since}) async {
    final c = RecordoSupabase.client;
    if (c == null) return const [];
    try {
      const page = 1000;
      final parks = <Park>[];
      var from = 0;
      while (true) {
        var q = c
            .from('parks')
            .select(
              'id,name,district,lat,lng,height_m,hourly_hkd,daily_hkd,night_hkd,price_note,ugc_confirms,price_updated_at,source,price_verification_status,price_verified_at,price_provenance,tariff,ev',
            )
            .not('price_updated_at', 'is', null);
        if (since != null) {
          q = q.gt('price_updated_at', since.toUtc().toIso8601String());
        }
        final rows = await q.order('id').range(from, from + page - 1);
        final list = (rows as List)
            .whereType<Map>()
            .map((e) => Park.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        parks.addAll(list);
        if (list.length < page) break;
        from += page;
        if (from > 20000) break;
      }
      return parks;
    } catch (_) {
      return const [];
    }
  }

  Future<CatalogDump?> _fetchCatalogPaged() async {
    final c = RecordoSupabase.client;
    if (c == null) return null;
    try {
      const page = 1000;
      final parks = <Park>[];
      var from = 0;
      while (true) {
        final rows = await c
            .from('parks')
            .select(
              'id,name,district,lat,lng,height_m,hourly_hkd,daily_hkd,night_hkd,price_note,ugc_confirms,price_updated_at,source,price_verification_status,price_verified_at,price_provenance,tariff,ev',
            )
            .order('id')
            .range(from, from + page - 1);
        final list = (rows as List)
            .whereType<Map>()
            .map((e) => Park.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        parks.addAll(list);
        if (list.length < page) break;
        from += page;
        if (from > 20000) break;
      }
      if (parks.isEmpty) return null;
      final version = await fetchCatalogVersion() ?? 1;
      return CatalogDump(version: version, parks: parks, parkCount: parks.length);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, RemoteParkPrice>> fetchPrices() async {
    final c = RecordoSupabase.client;
    if (c == null) return {};
    try {
      final rows = await c.from('park_prices').select();
      final out = <String, RemoteParkPrice>{};
      for (final row in rows as List) {
        final m = Map<String, dynamic>.from(row as Map);
        final id = m['park_id'] as String?;
        if (id == null) continue;
        out[id] = RemoteParkPrice(
          hourly: (m['hourly_hkd'] as num?)?.toDouble(),
          daily: (m['daily_hkd'] as num?)?.toDouble(),
          night: (m['night_hkd'] as num?)?.toDouble(),
          priceNote: (m['price_note'] as String?)?.trim() ?? '',
          confirms: m['ugc_confirms'] as int? ?? 0,
          updatedAt: m['price_updated_at'] != null
              ? DateTime.tryParse(m['price_updated_at'] as String)
              : null,
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<List<Park>> fetchUgcParks() async {
    final c = RecordoSupabase.client;
    if (c == null) return const [];
    try {
      final rows = await c
          .from('parks_ugc')
          .select()
          .order('created_at', ascending: false)
          .limit(500);
      return (rows as List).map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        return Park(
          id: m['id'] as String,
          name: m['name'] as String? ?? '未命名',
          district: m['district'] as String? ?? '香港',
          lat: (m['lat'] as num).toDouble(),
          lng: (m['lng'] as num).toDouble(),
          heightM: (m['height_m'] as num?)?.toDouble(),
          priceNote: (m['note'] as String?)?.trim() ?? '',
          source: 'ugc-remote',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> insertPaidSession({
    required String parkId,
    required double amountHkd,
    required int durationMinutes,
  }) async {
    final c = RecordoSupabase.client;
    if (c == null) return false;
    if (!await RecordoSupabase.ensureSignedIn()) return false;
    try {
      await c.from('paid_sessions').insert({
        'park_id': parkId,
        'amount_hkd': amountHkd,
        'duration_minutes': durationMinutes,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> insertCohortEvent({
    required String installId,
    required String event,
    String? parkId,
    double? amountHkd,
    int? durationMinutes,
    bool? sharePaid,
    bool? cloudOk,
  }) async {
    final c = RecordoSupabase.client;
    if (c == null) return false;
    if (!await RecordoSupabase.ensureSignedIn()) return false;
    try {
      await c.from('cohort_events').insert({
        'install_id': installId,
        'event': event,
        if (parkId != null && parkId.isNotEmpty) 'park_id': parkId,
        'amount_hkd': ?amountHkd,
        'duration_minutes': ?durationMinutes,
        'share_paid': ?sharePaid,
        'cloud_ok': ?cloudOk,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<CommunityPaidSession>> fetchPaidSessions(
    String parkId, {
    int limit = 8,
  }) async {
    final c = RecordoSupabase.client;
    if (c == null || parkId.trim().isEmpty) return const [];
    try {
      final rows = await c
          .from('paid_sessions')
          .select('amount_hkd,duration_minutes,created_at')
          .eq('park_id', parkId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .whereType<Map>()
          .map((e) => CommunityPaidSession.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> insertPriceReport({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    String? priceNote,
    bool confirmOnly = false,
    int? unitMinutes,
    double? unitAmount,
    double? offpeakAmount,
  }) async {
    final c = RecordoSupabase.client;
    if (c == null) return false;
    if (!await RecordoSupabase.ensureSignedIn()) return false;
    try {
      await c.from('price_reports').insert({
        'park_id': parkId,
        'hourly_hkd': hourly,
        'daily_hkd': daily,
        'night_hkd': night,
        'price_note': priceNote,
        'confirm_only': confirmOnly,
        'unit_minutes': ?unitMinutes,
        'unit_amount': ?unitAmount,
        'offpeak_amount': ?offpeakAmount,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> insertUgcPark(Park p, {String? note, String? address}) async {
    final c = RecordoSupabase.client;
    if (c == null) return false;
    try {
      await c.from('parks_ugc').upsert({
        'id': p.id,
        'name': p.name,
        'district': p.district,
        'address': address,
        'lat': p.lat,
        'lng': p.lng,
        'height_m': p.heightM,
        'note': note,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

class RemoteParkPrice {
  const RemoteParkPrice({
    this.hourly,
    this.daily,
    this.night,
    this.priceNote = '',
    this.confirms = 0,
    this.updatedAt,
  });

  final double? hourly;
  final double? daily;
  final double? night;
  final String priceNote;
  final int confirms;
  final DateTime? updatedAt;
}
