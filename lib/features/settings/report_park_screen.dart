import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/parks/price_guard.dart';
import 'package:recordo/features/parks/sign_ocr.dart';

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
  bool _ocrBusy = false;
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
    final cat = context.read<ParkCatalogCubit>();
    final cached = cat.state;
    if (cached.userLat != null && cached.userLng != null) {
      setState(() {
        _locLabel =
            '${cached.userLat!.toStringAsFixed(5)}, ${cached.userLng!.toStringAsFixed(5)}';
      });
      return;
    }
    final result = await cat.resolveUserLocation(requestPermission: false);
    if (!mounted) return;
    setState(() {
      _locLabel = result.ok
          ? '${result.lat!.toStringAsFixed(5)}, ${result.lng!.toStringAsFixed(5)}'
          : (result.error ?? '未能讀取定位 · 仍可提交');
    });
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
      final loc = await cubit.resolveUserLocation(updateCatalog: true);
      if (loc.ok) {
        lat = loc.lat;
        lng = loc.lng;
      }
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

  Future<void> _scanSign() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: UberColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('影收費牌'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('由相簿上載'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (file == null || !mounted) return;

    setState(() => _ocrBusy = true);
    try {
      final raw = await SignOcr.recognizeFile(file.path);
      if (!mounted) return;
      final guess = SignOcr.parse(raw);
      await _confirmHourly(guess);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? '讀唔到收費牌')),
        );
      }
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _confirmHourly(SignOcrGuess guess) async {
    final hourlyCtl = TextEditingController(
      text: guess.hourly?.toStringAsFixed(0) ?? '',
    );
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UberColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('預填時租', style: RType.titleSm()),
              const SizedBox(height: 6),
              Text(
                '唔當官方。確認之後先寫入時租，名稱同座標你自己填。相唔會上傳。',
                style: RType.muted(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hourlyCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '時租 HKD',
                  prefixText: r'$',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('確認預填'),
              ),
            ],
          ),
        );
      },
    );
    final hourlyText = hourlyCtl.text;
    hourlyCtl.dispose();
    if (ok != true || !mounted) return;
    final hourly = PriceGuard.clampHourly(double.tryParse(hourlyText));
    if (hourly == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('讀唔到時租 · 可以手填')),
      );
      return;
    }
    setState(() => _hourly.text = hourly.toStringAsFixed(0));
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
          icon: Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text('報告新停車場', style: RType.titleSm()),
        actions: [
          IconButton(
            tooltip: '影收費牌預填時租',
            onPressed: _ocrBusy ? null : _scanSign,
            icon: _ocrBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
        children: [
          Text(
            '幫大家加多一個場。資料會即時出現喺你部機嘅地圖；之後可以再同步。',
            style: RType.muted(),
          ),
          SizedBox(height: 18),
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
              border: Border.all(color: UberColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.my_location, color: UberColors.accent, size: 20),
                    SizedBox(width: 10),
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
                  SizedBox(height: 6),
                  Text(_locLabel!, style: RType.muted()),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('收費（可空 · 知就填 · 可影牌預填時租）'),
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
                backgroundColor: UberColors.ctaFill,
                foregroundColor: UberColors.ctaOnFill,
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
        border: UberColors.fieldOutline(),
        enabledBorder: UberColors.fieldOutline(),
        focusedBorder: UberColors.fieldOutline(focused: true),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
