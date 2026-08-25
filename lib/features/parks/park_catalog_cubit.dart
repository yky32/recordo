import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_repository.dart';

class ParkCatalogState {
  const ParkCatalogState({
    this.parks = const [],
    this.selectedId,
    this.loading = true,
    this.userLat,
    this.userLng,
    this.pinLat,
    this.pinLng,
    this.query = '',
    this.totalInDb = 0,
  });

  final List<Park> parks;
  final String? selectedId;
  final bool loading;
  final double? userLat;
  final double? userLng;
  /// Map center pin (drag-to-move target) — sample UX.
  final double? pinLat;
  final double? pinLng;
  final String query;
  /// Full catalog size (OSM+seed), not just nearby window.
  final int totalInDb;

  Park? get selected {
    if (selectedId == null) return null;
    try {
      return parks.firstWhere((e) => e.id == selectedId);
    } catch (_) {
      // Selected may be outside nearby window — look up raw later if needed
      return null;
    }
  }

  ParkCatalogState copyWith({
    List<Park>? parks,
    String? selectedId,
    bool? loading,
    double? userLat,
    double? userLng,
    double? pinLat,
    double? pinLng,
    String? query,
    int? totalInDb,
    bool clearSelected = false,
  }) {
    return ParkCatalogState(
      parks: parks ?? this.parks,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      loading: loading ?? this.loading,
      userLat: userLat ?? this.userLat,
      userLng: userLng ?? this.userLng,
      pinLat: pinLat ?? this.pinLat,
      pinLng: pinLng ?? this.pinLng,
      query: query ?? this.query,
      totalInDb: totalInDb ?? this.totalInDb,
    );
  }
}

class ParkCatalogCubit extends Cubit<ParkCatalogState> {
  ParkCatalogCubit({ParkRepository? repo})
      : _repo = repo ?? ParkRepository(),
        super(const ParkCatalogState());

  final ParkRepository _repo;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    await _repo.ensureLoaded();
    // Open app / resume: always try pull shared prices (no manual refresh needed)
    try {
      await _repo.refreshRemote();
    } catch (_) {}
    final all = _repo.allWithUgc();
    emit(
      state.copyWith(
        parks: _pipeline(all),
        loading: false,
        totalInDb: all.length,
      ),
    );
  }

  void select(String? id) => emit(state.copyWith(selectedId: id));

  void setQuery(String q) {
    emit(
      state.copyWith(
        query: q,
        parks: _pipeline(_repo.allWithUgc(), query: q),
      ),
    );
  }

  void setUserLocation(double lat, double lng) {
    emit(
      state.copyWith(
        userLat: lat,
        userLng: lng,
        pinLat: state.pinLat ?? lat,
        pinLng: state.pinLng ?? lng,
        parks: _pipeline(
          _repo.allWithUgc(),
          pinLat: state.pinLat ?? lat,
          pinLng: state.pinLng ?? lng,
        ),
      ),
    );
  }

  /// Called when user drags map — pin stays center, target moves.
  void setPin(double lat, double lng) {
    emit(
      state.copyWith(
        pinLat: lat,
        pinLng: lng,
        parks: _pipeline(_repo.allWithUgc(), pinLat: lat, pinLng: lng),
      ),
    );
  }

  List<Park> _pipeline(
    List<Park> raw, {
    double? pinLat,
    double? pinLng,
    String? query,
  }) {
    final q = (query ?? state.query).trim().toLowerCase();
    var list = raw;
    if (q.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.district.toLowerCase().contains(q),
          )
          .toList();
    }

    final cLat = pinLat ?? state.pinLat ?? state.userLat;
    final cLng = pinLng ?? state.pinLng ?? state.userLng;
    if (cLat == null || cLng == null) {
      // No location yet — show named / priced first, cap for perf
      final prefer = List<Park>.from(list)
        ..sort((a, b) {
          final ap = a.hasPrice ? 0 : 1;
          final bp = b.hasPrice ? 0 : 1;
          if (ap != bp) return ap.compareTo(bp);
          final an = a.name == '停車場' ? 1 : 0;
          final bn = b.name == '停車場' ? 1 : 0;
          return an.compareTo(bn);
        });
      return prefer.take(q.isEmpty ? 80 : 120).toList();
    }

    final scored = list.map((p) {
      final m = Geolocator.distanceBetween(cLat, cLng, p.lat, p.lng);
      return (p, m);
    }).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    // Cap markers/list for map performance (full DB still searchable)
    final cap = q.isEmpty ? 150 : 200;
    var out = scored.take(cap).map((e) => e.$1).toList();

    // Keep selected in window even if far
    final sel = state.selectedId;
    if (sel != null && !out.any((p) => p.id == sel)) {
      try {
        final p = raw.firstWhere((e) => e.id == sel);
        out = [p, ...out];
      } catch (_) {}
    }
    return out;
  }

  double? distanceMeters(Park p) {
    final cLat = state.pinLat ?? state.userLat;
    final cLng = state.pinLng ?? state.userLng;
    if (cLat == null || cLng == null) return null;
    return Geolocator.distanceBetween(cLat, cLng, p.lat, p.lng);
  }

  static String formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// true = also pushed to shared Supabase DB.
  Future<bool> reportPrice({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    String? priceNote,
    bool confirmOnly = false,
  }) async {
    final cloud = await _repo.reportPrice(
      parkId: parkId,
      hourly: hourly,
      daily: daily,
      night: night,
      priceNote: priceNote,
      confirmOnly: confirmOnly,
    );
    await load();
    select(parkId);
    return cloud;
  }

  /// Pull latest shared UGC prices / new parks from Supabase.
  Future<bool> syncFromCloud() async {
    try {
      await _repo.refreshRemote();
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> reportNewPark({
    required String name,
    required String district,
    String address = '',
    double? lat,
    double? lng,
    double? hourly,
    double? daily,
    double? night,
    double? heightM,
    String note = '',
  }) async {
    final p = await _repo.reportNewPark(
      name: name,
      district: district,
      address: address,
      lat: lat,
      lng: lng,
      hourly: hourly,
      daily: daily,
      night: night,
      heightM: heightM,
      note: note,
    );
    await load();
    select(p.id);
  }

  /// Resolve park by id even if not in nearby window (detail route).
  Park? parkById(String id) => _repo.byId(id);
}
