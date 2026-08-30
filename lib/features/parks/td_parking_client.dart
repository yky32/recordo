import 'package:dio/dio.dart';
import 'package:recordo/features/parks/td_vacancy.dart';

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

  Future<List<TdHourlyVacancy>> fetchLive() async {
    final basicRes = await _dio.get<dynamic>(basicInfoUrl);
    final vacRes = await _dio.get<dynamic>(vacancyUrl);
    final basic = parseTdBasic(basicRes.data);
    final vacancy = parseTdVacancyMap(vacRes.data);
    return joinTdLive(basic: basic, vacancy: vacancy);
  }
}
