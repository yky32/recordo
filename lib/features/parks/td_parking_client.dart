import 'package:dio/dio.dart';
import 'package:recordo/features/parks/td_vacancy.dart';
import 'package:recordo/features/parks/meter_space.dart';

/// Transport Department open data. Always via [Dio].
class TdParkingClient {
  TdParkingClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 25),
                headers: const {'User-Agent': 'recordo/1.0'},
              ),
            );

  final Dio _dio;

  static const basicInfoUrl =
      'https://resource.data.one.gov.hk/td/carpark/basic_info_all.json';
  static const vacancyUrl =
      'https://resource.data.one.gov.hk/td/carpark/vacancy_all.json';
  static const meterOccupancyUrl =
      'https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv';

  DateTime? _occAt;
  Map<String, MeterOccupancy> _occ = const {};

  Future<List<TdHourlyVacancy>> fetchLive() async {
    final basicRes = await _dio.get<dynamic>(basicInfoUrl);
    final vacRes = await _dio.get<dynamic>(vacancyUrl);
    final basic = parseTdBasic(basicRes.data);
    final vacancy = parseTdVacancyMap(vacRes.data);
    return joinTdLive(basic: basic, vacancy: vacancy);
  }

  Future<Map<String, MeterOccupancy>> fetchMeterOccupancy({
    Duration ttl = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();
    if (_occ.isNotEmpty && _occAt != null && now.difference(_occAt!) < ttl) {
      return _occ;
    }
    final res = await _dio.get<String>(
      meterOccupancyUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = res.data ?? '';
    _occ = parseMeterOccupancyCsv(raw);
    _occAt = now;
    return _occ;
  }
}
