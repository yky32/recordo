import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:recordo/core/location/user_location.dart';
import 'package:recordo/features/parks/community_paid_session.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_tariff.dart';
import 'package:recordo/features/parks/park_rank.dart';
import 'package:recordo/features/parks/park_repository.dart';
import 'package:recordo/features/parks/td_parking_client.dart';
import 'package:recordo/features/parks/td_vacancy.dart';

class ParkCatalogState {
  const ParkCatalogState({
    this.parks = const [],
    this.restParks = const [],
    this.showRestParks = false,
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
    this.communityPaidByPark = const {},
    this.communityPaidLoading = const {},
    this.tdVacancyByParkId = const {},
  });

  final List<Park> parks;
  /// Unpriced / demoted lots collapsed in the home sheet.
  final List<Park> restParks;
  final bool showRestParks;
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
  final Map<String, List<CommunityPaidSession>> communityPaidByPark;
  final Set<String> communityPaidLoading;
  /// TD participating lots only. Never written into catalog_dump.
  final Map<String, TdHourlyVacancy> tdVacancyByParkId;

  bool get isSearching => query.trim().isNotEmpty;

  List<CommunityPaidSession> communityPaidFor(String parkId) =>
      communityPaidByPark[parkId] ?? const [];

  bool communityPaidLoadingFor(String parkId) =>
      communityPaidLoading.contains(parkId);

  TdHourlyVacancy? tdVacancyFor(String parkId) => tdVacancyByParkId[parkId];

  /// Featured + collapsed remainder — for map pins in the current window.
  List<Park> get allWindowParks => [...parks, ...restParks];

  Park? get selected {
    if (selectedId == null) return null;
    for (final list in [parks, restParks]) {
      try {
        return list.firstWhere((e) => e.id == selectedId);
      } catch (_) {}
    }
    return null;
  }

  ParkCatalogState copyWith({
    List<Park>? parks,
    List<Park>? restParks,
    bool? showRestParks,
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
    Map<String, List<CommunityPaidSession>>? communityPaidByPark,
    Set<String>? communityPaidLoading,
    Map<String, TdHourlyVacancy>? tdVacancyByParkId,
    bool clearSelected = false,
  }) {
    return ParkCatalogState(
      parks: parks ?? this.parks,
      restParks: restParks ?? this.restParks,
      showRestParks: showRestParks ?? this.showRestParks,
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
      communityPaidByPark: communityPaidByPark ?? this.communityPaidByPark,
      communityPaidLoading: communityPaidLoading ?? this.communityPaidLoading,
      tdVacancyByParkId: tdVacancyByParkId ?? this.tdVacancyByParkId,
    );
  }
}

class ParkCatalogCubit extends Cubit<ParkCatalogState> {
  ParkCatalogCubit({ParkRepository? repo, TdParkingClient? td})
      : _repo = repo ?? ParkRepository(),
        _td = td ?? TdParkingClient(),
        super(const ParkCatalogState());

  final ParkRepository _repo;
  final TdParkingClient _td;

  void _emitCatalog({bool loading = false}) {
    final all = _repo.allWithUgc();
    final piped = _pipeline(all);
    emit(
      state.copyWith(
        parks: piped.featured,
        restParks: piped.rest,
        showRestParks: false,
        loading: loading,
        totalInDb: all.length,
        catalogVersion: _repo.catalogVersion,
        fromCloud: _repo.playingFromCloudSnapshot,
      ),
    );
  }

  void toggleRestParks() {
    emit(state.copyWith(showRestParks: !state.showRestParks));
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    await _repo.loadLocalFirst();
    _emitCatalog();
    final result = await _repo.syncIfRemoteNewer();
    await _repo.flushOutbox();
    if (result == CatalogSyncResult.updated) {
      _emitCatalog();
    }
    await refreshTdVacancy();
  }

  Future<void> refreshTdVacancy() async {
    try {
      final live = await _td.fetchLive();
      if (isClosed) return;
      final mapped = matchTdToParks(parks: _repo.allWithUgc(), live: live);
      emit(state.copyWith(tdVacancyByParkId: mapped));
    } catch (_) {
      // Participating feed is optional — keep catalog.
    }
  }

  void select(String? id) => emit(state.copyWith(selectedId: id));

  /// Map pin tap — re-rank sheet so the pin is row 0, then list can scroll to it.
  void selectFromMap(String id) {
    emit(state.copyWith(selectedId: id));
    _emitCatalog();
  }

  void setQuery(String q) {
    final piped = _pipeline(_repo.allWithUgc(), query: q);
    emit(
      state.copyWith(
        query: q,
        parks: piped.featured,
        restParks: piped.rest,
        showRestParks: q.trim().isNotEmpty,
      ),
    );
  }

  void setUserLocation(double lat, double lng) {
    final piped = _pipeline(
      _repo.allWithUgc(),
      pinLat: state.pinLat ?? lat,
      pinLng: state.pinLng ?? lng,
    );
    emit(
      state.copyWith(
        userLat: lat,
        userLng: lng,
        pinLat: state.pinLat ?? lat,
        pinLng: state.pinLng ?? lng,
        parks: piped.featured,
        restParks: piped.rest,
      ),
    );
  }

  /// Called when user drags map — pin stays center, target moves.
  void setPin(double lat, double lng) {
    final piped = _pipeline(_repo.allWithUgc(), pinLat: lat, pinLng: lng);
    emit(
      state.copyWith(
        pinLat: lat,
        pinLng: lng,
        parks: piped.featured,
        restParks: piped.rest,
      ),
    );
  }

  ({List<Park> featured, List<Park> rest}) _pipeline(
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

    final sorted = List<Park>.from(list)
      ..sort(
        (a, b) => compareParksForDisplay(
          a,
          b,
          centerLat: cLat,
          centerLng: cLng,
        ),
      );

    if (q.isNotEmpty) {
      return (featured: sorted, rest: const []);
    }

    final cap = 150;
    var window = sorted.take(cap).toList();

    final sel = state.selectedId;
    Park? selectedPark;
    if (sel != null) {
      for (final p in raw) {
        if (p.id == sel) {
          selectedPark = p;
          break;
        }
      }
      if (selectedPark != null && !window.any((p) => p.id == sel)) {
        window = [selectedPark, ...window];
      }
    }

    final split = splitFeaturedRest(window, searching: false);
    return pinSelectedToFront(
      featured: split.featured,
      rest: split.rest,
      selectedId: sel,
      fallback: selectedPark,
    );
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

  /// Cached catalog coords, else one-shot Geolocator lookup.
  Future<UserLocationResult> resolveUserLocation({
    bool requestPermission = true,
    bool updateCatalog = false,
  }) async {
    if (state.userLat != null && state.userLng != null) {
      return UserLocationResult(lat: state.userLat, lng: state.userLng);
    }
    final result = await UserLocationResolver.resolve(
      requestPermission: requestPermission,
    );
    if (updateCatalog && result.ok) {
      setUserLocation(result.lat!, result.lng!);
    }
    return result;
  }

  /// true = also pushed to shared Supabase DB.
  Future<bool> reportPrice({
    required String parkId,
    double? hourly,
    double? daily,
    double? night,
    String? priceNote,
    bool confirmOnly = false,
    int? unitMinutes,
    double? unitAmount,
    double? offpeakAmount,
    ParkTariff? tariff,
  }) async {
    final cloud = await _repo.reportPrice(
      parkId: parkId,
      hourly: hourly,
      daily: daily,
      night: night,
      priceNote: priceNote,
      confirmOnly: confirmOnly,
      unitMinutes: unitMinutes,
      unitAmount: unitAmount,
      offpeakAmount: offpeakAmount,
      tariff: tariff,
    );
    _emitCatalog();
    select(parkId);
    return cloud;
  }

  /// Share real payment to community table (not hourly price).
  Future<bool> reportPaidSession({
    required String parkId,
    required double amountHkd,
    required int durationMinutes,
  }) async {
    final cloud = await _repo.reportPaidSession(
      parkId: parkId,
      amountHkd: amountHkd,
      durationMinutes: durationMinutes,
    );
    if (cloud) {
      await loadCommunityPaid(parkId);
    }
    return cloud;
  }

  Future<void> loadCommunityPaid(String parkId, {int limit = 8}) async {
    if (parkId.trim().isEmpty) return;
    emit(
      state.copyWith(
        communityPaidLoading: {...state.communityPaidLoading, parkId},
      ),
    );
    final rows = await _repo.fetchCommunityPaidSessions(parkId, limit: limit);
    if (isClosed) return;
    final nextLoading = Set<String>.from(state.communityPaidLoading)
      ..remove(parkId);
    final nextMap =
        Map<String, List<CommunityPaidSession>>.from(state.communityPaidByPark);
    nextMap[parkId] = rows;
    emit(
      state.copyWith(
        communityPaidByPark: nextMap,
        communityPaidLoading: nextLoading,
      ),
    );
  }

  /// Check cloud version; dump only if newer.
  Future<CatalogSyncResult> syncFromCloud({bool force = false}) async {
    try {
      final result = await _repo.syncIfRemoteNewer(force: force);
      await _repo.flushOutbox();
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
