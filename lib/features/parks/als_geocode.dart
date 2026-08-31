import 'package:dio/dio.dart';

/// HK Address Lookup Service. Dio only. Rejects coords outside HK.
class AlsHit {
  const AlsHit({required this.lat, required this.lng, this.address = ''});

  final double lat;
  final double lng;
  final String address;
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
    final start = xml.indexOf('SuggestedAddress');
    if (start < 0) return null;
    final next = xml.indexOf('SuggestedAddress', start + 16);
    final first = next < 0 ? xml.substring(start) : xml.substring(start, next);
    final latM = RegExp(r'<Latitude>\s*([0-9.]+)\s*</Latitude>').firstMatch(first);
    final lngM =
        RegExp(r'<Longitude>\s*([0-9.]+)\s*</Longitude>').firstMatch(first);
    if (latM == null || lngM == null) return null;
    final lat = double.tryParse(latM.group(1)!);
    final lng = double.tryParse(lngM.group(1)!);
    if (lat == null || lng == null) return null;
    if (lat < 22.1 || lat > 22.6 || lng < 113.7 || lng > 114.5) return null;
    return AlsHit(lat: lat, lng: lng, address: _label(first));
  }

  static String _label(String xml) {
    String? tag(String name) {
      final m = RegExp('<$name>\\s*([^<]+)\\s*</$name>').firstMatch(xml);
      return m?.group(1)?.trim();
    }

    final street = tag('StreetName');
    final no = tag('BuildingNoFrom');
    final bldg = tag('BuildingName');
    final parts = <String>[
      if (bldg != null && bldg.isNotEmpty) bldg,
      if (street != null && street.isNotEmpty)
        '${no == null || no.isEmpty ? '' : '$no 號'}$street'.trim(),
    ];
    return parts.join(' · ');
  }
}
