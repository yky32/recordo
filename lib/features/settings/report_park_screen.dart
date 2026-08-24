import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';

/// UGC: report a new car park (name, place, fees, height).
class ReportParkScreen extends StatefulWidget {
  const ReportParkScreen({super.key});

  @override
  State<ReportParkScreen> createState() => _ReportParkScreenState();
}

class _ReportParkScreenState extends State<ReportParkScreen> {
  final _name = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _hourly = TextEditingController();
  final _daily = TextEditingController();
  final _night = TextEditingController();
  final _height = TextEditingController();
  final _note = TextEditingController();
  bool _useMyLocation = true;
  bool _submitting = false;
  String? _locLabel;

  @override
  void initState() {
    super.initState();
    _probeLocation();
  }

  @override
  void dispose() {
    _name.dispose();
    _district.dispose();
    _address.dispose();
    _hourly.dispose();
    _daily.dispose();
    _night.dispose();
    _height.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _probeLocation() async {
    try {
      final cat = context.read<ParkCatalogCubit>().state;
      if (cat.userLat != null && cat.userLng != null) {
        setState(() {
          _locLabel =
              '${cat.userLat!.toStringAsFixed(5)}, ${cat.userLng!.toStringAsFixed(5)}';
        });
        return;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          );
      if (!mounted) return;
      setState(() {
        _locLabel =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _locLabel = '未能讀取定位 · 仍可提交');
      }
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填停車場名稱')),
      );
      return;
    }
    final cubit = context.read<ParkCatalogCubit>();
    final district =
        _district.text.trim().isEmpty ? '香港' : _district.text.trim();
    final address = _address.text.trim();
    final note = _note.text.trim();
    double? parse(TextEditingController c) => double.tryParse(c.text.trim());
    final hourly = parse(_hourly);
    final daily = parse(_daily);
    final night = parse(_night);
    final heightM = parse(_height);

    setState(() => _submitting = true);

    double? lat;
    double? lng;
    if (_useMyLocation) {
      try {
        final cat = cubit.state;
        if (cat.userLat != null) {
          lat = cat.userLat;
          lng = cat.userLng;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}
    }

    await cubit.reportNewPark(
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

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('多謝 · 已加入地圖（本機 UGC）')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: UberColors.black,
      appBar: AppBar(
        backgroundColor: UberColors.black,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text('報告新停車場', style: RType.titleSm()),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
        children: [
          Text(
            '幫大家加多一個場。資料會即時出現喺你部機嘅地圖；之後可以再同步。',
            style: RType.muted(),
          ),
          const SizedBox(height: 18),
          _label('名稱 *'),
          _field(_name, '例如：時代廣場停車場', textCapitalization: TextCapitalization.words),
          const SizedBox(height: 14),
          _label('地區'),
          _field(_district, '例如：銅鑼灣 / 觀塘'),
          const SizedBox(height: 14),
          _label('地址 / 地標（可空）'),
          _field(_address, '街道或商場名'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: UberColors.elevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.my_location, color: UberColors.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('用我而家位置做座標', style: RType.body()),
                    ),
                    Switch.adaptive(
                      value: _useMyLocation,
                      activeTrackColor: UberColors.accent.withValues(alpha: 0.5),
                      activeThumbColor: UberColors.accent,
                      onChanged: (v) => setState(() => _useMyLocation = v),
                    ),
                  ],
                ),
                if (_locLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(_locLabel!, style: RType.muted()),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('收費（可空 · 知就填）'),
          _field(_hourly, '時租 HK\$', keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _field(_daily, '日泊 HK\$', keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _field(_night, '夜泊 HK\$', keyboard: TextInputType.number),
          const SizedBox(height: 14),
          _label('限高 m（可空）'),
          _field(_height, '例如 2.1', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 14),
          _label('備註（可空）'),
          _field(_note, '例如：假日貴 / 要預繳', maxLines: 3),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: UberColors.white,
                foregroundColor: UberColors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('提交新場'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t, style: RType.label()),
      );

  Widget _field(
    TextEditingController c,
    String hint, {
    TextInputType? keyboard,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      style: RType.body(),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: RType.muted(),
        filled: true,
        fillColor: UberColors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
