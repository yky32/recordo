import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/price_verification.dart';

/// Curated HK lots — demo prices are unverified until gate-checked (Phase A).
final List<Park> hkSeedParks = [
  // HK Island
  Park(id: 'ts_causeway', name: '時代廣場停車場', district: '銅鑼灣', lat: 22.2783, lng: 114.1827, hourlyHkd: 32, dailyHkd: 250, nightHkd: 120, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'lee_garden_1', name: '利園一期停車場', district: '銅鑼灣', lat: 22.2789, lng: 114.1845, hourlyHkd: 34, dailyHkd: 270, heightM: 2.0, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'lee_garden_3', name: '利園三期停車場', district: '銅鑼灣', lat: 22.2795, lng: 114.1858, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'vp_cwb', name: '維多利亞公園停車場', district: '銅鑼灣', lat: 22.2825, lng: 114.189, hourlyHkd: 26, dailyHkd: 180, nightHkd: 90, heightM: 2.0, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'hysan_place', name: '希慎廣場停車場', district: '銅鑼灣', lat: 22.2798, lng: 114.1839, hourlyHkd: 30, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'world_trade', name: '世貿中心停車場', district: '銅鑼灣', lat: 22.2806, lng: 114.1852, hourlyHkd: 28, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'ifc_central', name: 'IFC 商場停車場', district: '中環', lat: 22.2855, lng: 114.158, hourlyHkd: 30, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'landmarks', name: '置地廣場停車場', district: '中環', lat: 22.2812, lng: 114.1578, hourlyHkd: 32, heightM: 2.0, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'pacific_place_adm', name: '太古廣場停車場', district: '金鐘', lat: 22.2776, lng: 114.1655, hourlyHkd: 30, dailyHkd: 240, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'queensway', name: '金鐘廊停車場', district: '金鐘', lat: 22.2788, lng: 114.1648, hourlyHkd: 28, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'taikoo_place', name: '太古坊停車場', district: '鰂魚涌', lat: 22.2865, lng: 114.211, hourlyHkd: 24, heightM: 2.2, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'cityplaza', name: '太古城中心停車場', district: '太古城', lat: 22.2868, lng: 114.2175, hourlyHkd: 20, dailyHkd: 140, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'aberdeen', name: '香港仔中心停車場', district: '香港仔', lat: 22.2485, lng: 114.1555, hourlyHkd: 16, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'cyberport', name: '數碼港停車場', district: '薄扶林', lat: 22.2615, lng: 114.1302, hourlyHkd: 18, heightM: 2.3, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'repulse_bay', name: '淺水灣停車場', district: '淺水灣', lat: 22.2365, lng: 114.197, hourlyHkd: 22, source: 'seed', priceProvenance: PriceProvenance.seed),

  // Kowloon
  Park(id: 'hc_tst', name: '海港城停車場', district: '尖沙咀', lat: 22.295, lng: 114.168, hourlyHkd: 28, dailyHkd: 220, heightM: 2.2, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'k11_musea', name: 'K11 MUSEA 停車場', district: '尖沙咀', lat: 22.2942, lng: 114.1745, hourlyHkd: 30, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'i_square', name: '國際廣場停車場', district: '尖沙咀', lat: 22.2972, lng: 114.1722, hourlyHkd: 26, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'k11_art', name: 'K11 Art Mall 停車場', district: '尖沙咀', lat: 22.2978, lng: 114.174, hourlyHkd: 27, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'elements_wkr', name: '圓方停車場', district: '西九龍', lat: 22.3045, lng: 114.1615, hourlyHkd: 26, heightM: 2.2, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'icc', name: '環球貿易廣場停車場', district: '西九龍', lat: 22.3033, lng: 114.1601, hourlyHkd: 28, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'china_hk_city', name: '中港城停車場', district: '尖沙咀', lat: 22.2998, lng: 114.1678, hourlyHkd: 25, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'festival_kln', name: '又一城停車場', district: '九龍塘', lat: 22.337, lng: 114.174, hourlyHkd: 22, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'apm_kt', name: 'apm 停車場', district: '觀塘', lat: 22.312, lng: 114.225, hourlyHkd: 18, heightM: 2.0, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'mega_box', name: 'MegaBox 停車場', district: '九龍灣', lat: 22.3198, lng: 114.2085, hourlyHkd: 17, dailyHkd: 100, heightM: 2.3, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'telford', name: '德福廣場停車場', district: '九龍灣', lat: 22.3235, lng: 114.2135, hourlyHkd: 16, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'langham_place', name: '朗豪坊停車場', district: '旺角', lat: 22.3182, lng: 114.1685, hourlyHkd: 24, heightM: 2.0, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'mk_gov', name: '旺角政府合署停車場', district: '旺角', lat: 22.3205, lng: 114.171, hourlyHkd: 20, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'plaza_hollywood', name: '荷里活廣場停車場', district: '鑽石山', lat: 22.3408, lng: 114.202, hourlyHkd: 18, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'whampoa', name: '黃埔天地停車場', district: '紅磡', lat: 22.3048, lng: 114.1895, hourlyHkd: 18, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'kai_tak', name: '啟德商場停車場', district: '啟德', lat: 22.3305, lng: 114.1995, hourlyHkd: 15, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'v_walk', name: 'V Walk 停車場', district: '深水埗', lat: 22.3285, lng: 114.1525, hourlyHkd: 16, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),

  // NT
  Park(id: 'ntp_shatin', name: '新城市廣場停車場', district: '沙田', lat: 22.382, lng: 114.188, hourlyHkd: 15, dailyHkd: 90, heightM: 2.4, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'ntp_p3', name: '新城市廣場三期停車場', district: '沙田', lat: 22.3835, lng: 114.1895, hourlyHkd: 15, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'st_town_hall', name: '沙田大會堂停車場', district: '沙田', lat: 22.3812, lng: 114.187, hourlyHkd: 14, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'yoho_yl', name: 'YOHO Mall 停車場', district: '元朗', lat: 22.445, lng: 114.036, hourlyHkd: 12, heightM: 2.4, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'tko_plaza', name: '將軍澳廣場停車場', district: '將軍澳', lat: 22.3105, lng: 114.262, hourlyHkd: 14, heightM: 2.2, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'popcorn', name: 'PopCorn 停車場', district: '將軍澳', lat: 22.3078, lng: 114.2605, hourlyHkd: 15, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'tko_sports', name: '將軍澳運動場停車場', district: '將軍澳', lat: 22.3135, lng: 114.268, hourlyHkd: 12, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'maritime', name: '青衣城停車場', district: '青衣', lat: 22.3585, lng: 114.1075, hourlyHkd: 14, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'citygate', name: '東薈城停車場', district: '東涌', lat: 22.2895, lng: 113.9415, hourlyHkd: 16, dailyHkd: 100, heightM: 2.3, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'tm_plaza', name: '屯門市廣場停車場', district: '屯門', lat: 22.3915, lng: 113.9775, hourlyHkd: 12, heightM: 2.2, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'gold_coast', name: '黃金海岸停車場', district: '屯門', lat: 22.372, lng: 113.993, hourlyHkd: 18, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'mos_town', name: '新港城中心停車場', district: '馬鞍山', lat: 22.4255, lng: 114.231, hourlyHkd: 13, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'taipo_mega', name: '大埔超級城停車場', district: '大埔', lat: 22.4525, lng: 114.1675, hourlyHkd: 14, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'fanling', name: '粉嶺名都停車場', district: '粉嶺', lat: 22.4935, lng: 114.1395, hourlyHkd: 12, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'tw_plaza', name: '荃灣廣場停車場', district: '荃灣', lat: 22.3715, lng: 114.1165, hourlyHkd: 15, heightM: 2.1, source: 'seed', priceProvenance: PriceProvenance.seed),
  Park(id: 'nan_fung', name: '南豐中心停車場', district: '荃灣', lat: 22.3738, lng: 114.1178, hourlyHkd: 14, source: 'seed', priceProvenance: PriceProvenance.seed),
];
