/// HK districts for UGC identity edit. Chip list — no free-typed junk.
const hkDistricts = <String>[
  '銅鑼灣',
  '灣仔',
  '跑馬地',
  '金鐘',
  '中環',
  '上環',
  '西環',
  '北角',
  '鰂魚涌',
  '太古城',
  '筲箕灣',
  '柴灣',
  '香港仔',
  '薄扶林',
  '淺水灣',
  '赤柱',
  '尖沙咀',
  '佐敦',
  '油麻地',
  '旺角',
  '大角咀',
  '深水埗',
  '長沙灣',
  '荔枝角',
  '美孚',
  '九龍塘',
  '黃大仙',
  '鑽石山',
  '觀塘',
  '牛頭角',
  '九龍灣',
  '紅磡',
  '土瓜灣',
  '啟德',
  '西九龍',
  '沙田',
  '大埔',
  '粉嶺',
  '上水',
  '元朗',
  '屯門',
  '天水圍',
  '荃灣',
  '葵涌',
  '青衣',
  '將軍澳',
  '西貢',
  '東涌',
  '馬鞍山',
];

String? clampParkName(String raw) {
  final n = raw.replaceAll('\n', ' ').trim();
  if (n.length < 2 || n.length > 40) return null;
  return n;
}

String? clampDistrict(String raw) {
  final d = raw.trim();
  if (hkDistricts.contains(d)) return d;
  return null;
}
