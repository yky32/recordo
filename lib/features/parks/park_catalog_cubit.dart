import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_repository.dart';

class ParkCatalogState {
  const ParkCatalogState({
    this.parks = const [],
    this.selectedId,
    this.loading = true,
  });

  final List<Park> parks;
  final String? selectedId;
  final bool loading;

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
    bool clearSelected = false,
  }) {
    return ParkCatalogState(
      parks: parks ?? this.parks,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      loading: loading ?? this.loading,
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
    final parks = _repo.allWithUgc();
    emit(state.copyWith(parks: parks, loading: false));
  }

  void select(String? id) => emit(state.copyWith(selectedId: id));

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
}
