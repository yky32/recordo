import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/features/parks/park.dart';

/// Remote UGC via Supabase. Safe no-op if not configured / offline.
class SupabaseParkRemote {
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
          confirms: m['ugc_confirms'] as int? ?? 1,
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
          source: 'ugc-remote',
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> insertPriceReport({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    bool confirmOnly = false,
  }) async {
    final c = RecordoSupabase.client;
    if (c == null) return false;
    try {
      await c.from('price_reports').insert({
        'park_id': parkId,
        'hourly_hkd': hourly,
        'daily_hkd': daily,
        'night_hkd': night,
        'confirm_only': confirmOnly,
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
    this.confirms = 1,
    this.updatedAt,
  });

  final double? hourly;
  final double? daily;
  final double? night;
  final int confirms;
  final DateTime? updatedAt;
}
