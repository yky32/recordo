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

  Park? get selected {
    if (selectedId == null) return null;
    try {
      return parks.firstWhere((e) => e.id == selectedId);
    } catch (_) {
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
    );
  }
}

class ParkCatalogCubit extends Cubit<ParkCatalogState> {
  ParkCatalogCubit({ParkRepository? repo})
      : _repo = repo ?? ParkRepository(),
        super(const ParkCatalogState());

  final ParkRepository _repo;

  void load() {
    emit(state.copyWith(loading: true));
    emit(state.copyWith(parks: _pipeline(_repo.allWithUgc()), loading: false));
  }

  void select(String? id) => emit(state.copyWith(selectedId: id));

  void setQuery(String q) {
    emit(state.copyWith(query: q, parks: _pipeline(_repo.allWithUgc(), query: q)));
  }

  void setUserLocation(double lat, double lng) {
    emit(state.copyWith(
      userLat: lat,
      userLng: lng,
      pinLat: state.pinLat ?? lat,
      pinLng: state.pinLng ?? lng,
      parks: _pipeline(
        _repo.allWithUgc(),
        pinLat: state.pinLat ?? lat,
        pinLng: state.pinLng ?? lng,
      ),
    ));
  }

  /// Called when user drags map — pin stays center, target moves.
  void setPin(double lat, double lng) {
    emit(state.copyWith(
      pinLat: lat,
      pinLng: lng,
      parks: _pipeline(_repo.allWithUgc(), pinLat: lat, pinLng: lng),
    ));
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
    if (cLat == null || cLng == null) return List.of(list);

    final scored = list.map((p) {
      final m = Geolocator.distanceBetween(cLat, cLng, p.lat, p.lng);
      return (p, m);
    }).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return scored.map((e) => e.$1).toList();
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

  Future<void> reportPrice({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    bool confirmOnly = false,
  }) async {
    await _repo.reportPrice(
      parkId: parkId,
      hourly: hourly,
      daily: daily,
      night: night,
      confirmOnly: confirmOnly,
    );
    load();
    select(parkId);
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
    load();
    select(p.id);
  }
}
