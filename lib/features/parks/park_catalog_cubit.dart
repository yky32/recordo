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
    this.catalogVersion = 0,
    this.fromCloud = false,
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
  /// Full catalog size, not just nearby window.
  final int totalInDb;
  final int catalogVersion;
  final bool fromCloud;

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
    int? catalogVersion,
    bool? fromCloud,
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
      catalogVersion: catalogVersion ?? this.catalogVersion,
      fromCloud: fromCloud ?? this.fromCloud,
    );
  }
}

class ParkCatalogCubit extends Cubit<ParkCatalogState> {
  ParkCatalogCubit({ParkRepository? repo})
      : _repo = repo ?? ParkRepository(),
        super(const ParkCatalogState());

  final ParkRepository _repo;

  void _emitCatalog({bool loading = false}) {
    final all = _repo.allWithUgc();
    emit(
      state.copyWith(
        parks: _pipeline(all),
        loading: loading,
        totalInDb: all.length,
        catalogVersion: _repo.catalogVersion,
        fromCloud: _repo.playingFromCloudSnapshot,
      ),
    );
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    await _repo.loadLocalFirst();
    _emitCatalog();
    final result = await _repo.syncIfRemoteNewer();
    if (result == CatalogSyncResult.updated) {
      _emitCatalog();
    }
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
    _emitCatalog();
    select(parkId);
    return cloud;
  }

  /// Check cloud version; dump only if newer.
  Future<CatalogSyncResult> syncFromCloud({bool force = false}) async {
    try {
      final result = await _repo.syncIfRemoteNewer(force: force);
      _emitCatalog();
      return result;
    } catch (_) {
      return CatalogSyncResult.offline;
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
    _emitCatalog();
    select(p.id);
  }

  /// Resolve park by id even if not in nearby window (detail route).
  Park? parkById(String id) => _repo.byId(id);
}
