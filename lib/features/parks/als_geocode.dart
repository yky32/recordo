import 'package:dio/dio.dart';

/// HK Address Lookup Service. Dio only. Rejects coords outside HK.
class AlsHit {
  const AlsHit({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class AlsGeocodeClient {
  AlsGeocodeClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {'User-Agent': 'recordo/1.0'},
                responseType: ResponseType.plain,
              ),
            );

  final Dio _dio;

  static const _url = 'https://www.als.gov.hk/lookup';

  Future<AlsHit?> lookup(String query) async {
    final q = query.trim();
    if (q.length < 2) return null;
    final res = await _dio.get<String>(
      _url,
      queryParameters: {'q': q},
    );
    return parseXml(res.data ?? '');
  }

  /// First SuggestedAddress only. Outside HK bbox → null.
  static AlsHit? parseXml(String xml) {
    if (!xml.contains('SuggestedAddress')) return null;
    final latM = RegExp(r'<Latitude>\s*([0-9.]+)\s*</Latitude>').firstMatch(xml);
    final lngM =
        RegExp(r'<Longitude>\s*([0-9.]+)\s*</Longitude>').firstMatch(xml);
    if (latM == null || lngM == null) return null;
    final lat = double.tryParse(latM.group(1)!);
    final lng = double.tryParse(lngM.group(1)!);
    if (lat == null || lng == null) return null;
    if (lat < 22.1 || lat > 22.6 || lng < 113.7 || lng > 114.5) return null;
    return AlsHit(lat: lat, lng: lng);
  }
}
