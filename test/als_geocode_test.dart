import 'package:flutter_test/flutter_test.dart';
import 'package:recordo/features/parks/als_geocode.dart';

void main() {
  test('ALS first SuggestedAddress inside HK', () {
    const xml = '''
<AddressLookupResult>
  <SuggestedAddress>
    <Address>
      <PremisesAddress>
        <StreetName>廣東道</StreetName>
        <BuildingNoFrom>3</BuildingNoFrom>
        <GeospatialInformation>
          <Latitude>22.2971</Latitude>
          <Longitude>114.1682</Longitude>
        </GeospatialInformation>
      </PremisesAddress>
    </Address>
  </SuggestedAddress>
</AddressLookupResult>
''';
    final hit = AlsGeocodeClient.parseXml(xml);
    expect(hit, isNotNull);
    expect(hit!.lat, closeTo(22.2971, 0.0001));
    expect(hit.lng, closeTo(114.1682, 0.0001));
    expect(hit.address, contains('廣東道'));
  });

  test('ALS outside HK bbox is rejected', () {
    const xml = '''
<SuggestedAddress>
  <Latitude>31.2304</Latitude>
  <Longitude>121.4737</Longitude>
</SuggestedAddress>
''';
    expect(AlsGeocodeClient.parseXml(xml), isNull);
  });

  test('ALS empty is null', () {
    expect(AlsGeocodeClient.parseXml('<AddressLookupResult/>'), isNull);
  });
}
