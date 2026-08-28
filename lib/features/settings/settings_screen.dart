import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/core/theme/theme_controller.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/parks/park_repository.dart';
import 'package:recordo/features/session/session_cubit.dart';
import 'package:recordo/features/settings/settings_cubit.dart';

/// Uber-style settings hub.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearHistory(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: UberColors.elevated,
        title: Text('清除泊車記錄？', style: RType.titleSm()),
        content: Text(
          '只清本機 session 記錄，唔會刪場價同新場 UGC。',
          style: RType.muted(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: RType.body()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '清除',
              style: RType.body().copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<SessionCubit>().clearHistory();
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除記錄')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (prev, next) => prev.snackMessage != next.snackMessage,
      listener: (context, state) {
        final msg = state.snackMessage;
        if (msg == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        context.read<SettingsCubit>().clearSnack();
      },
      builder: (context, prefs) {
        return _SettingsBody(
          haptics: prefs.haptics,
          remindLog: prefs.remindLog,
          onClearHistory: () => _clearHistory(context),
        );
      },
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.haptics,
    required this.remindLog,
    required this.onClearHistory,
  });

  final bool haptics;
  final bool remindLog;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<ParkCatalogCubit>().state;
    final syncSubtitle = !RecordoSupabase.isReady
        ? '要先設定 Supabase'
        : (cat.fromCloud && cat.catalogVersion > 0)
            ? '本機 v${cat.catalogVersion} · ${cat.totalInDb} 個 · 有新版本先下載'
            : '未下載雲端場庫 · 而家用本機後備';
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
        title: Text('設定', style: RType.titleSm()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _SectionLabel('貢獻 · UGC'),
          _SettingsCard(
            children: [
              _NavRow(
                icon: Icons.add_location_alt_outlined,
                title: '報告新停車場',
                subtitle: '名稱 · 位置 · 收費 · 限高',
                highlight: true,
                onTap: () => context.push('/settings/report-park'),
              ),
              _NavRow(
                icon: Icons.price_change_outlined,
                title: '我點更新場價？',
                subtitle: '地圖揀場 → 詳情 → 改收費',
                onTap: () {
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (ctx) => const _UpdatePriceHowToSheet(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('記錄'),
          _SettingsCard(
            children: [
              _NavRow(
                icon: Icons.receipt_long_rounded,
                title: '泊車記錄',
                subtitle: '本月合計 · 過往 session',
                onTap: () => context.push('/history'),
              ),
              _NavRow(
                icon: Icons.delete_outline_rounded,
                title: '清除泊車記錄',
                subtitle: '本機資料',
                destructive: true,
                onTap: onClearHistory,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('外觀'),
          _SettingsCard(
            children: [
              ListenableBuilder(
                listenable: ThemeController.instance,
                builder: (context, _) {
                  final mode = ThemeController.instance.mode;
                  final label = switch (mode) {
                    ThemeMode.light => '淺色',
                    ThemeMode.system => '跟系統',
                    ThemeMode.dark => '深色（預設）',
                  };
                  return Column(
                    children: [
                      _NavRow(
                        icon: Icons.dark_mode_outlined,
                        title: '主題',
                        subtitle: label,
                        onTap: () async {
                          // cycle dark → light → system → dark
                          final next = switch (mode) {
                            ThemeMode.dark => ThemeMode.light,
                            ThemeMode.light => ThemeMode.system,
                            ThemeMode.system => ThemeMode.dark,
                          };
                          await ThemeController.instance.setMode(next);
                        },
                      ),
                      _ToggleRow(
                        icon: Icons.wb_sunny_outlined,
                        title: '淺色模式',
                        subtitle: 'Uber light · 地圖改浅底',
                        value: !ThemeController.instance.isDark,
                        onChanged: (v) {
                          ThemeController.instance.setMode(
                            v ? ThemeMode.light : ThemeMode.dark,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('偏好'),
          _SettingsCard(
            children: [
              _ToggleRow(
                icon: Icons.vibration_rounded,
                title: '觸感回饋',
                value: haptics,
                onChanged: (v) =>
                    context.read<SettingsCubit>().setHaptics(v),
              ),
              _ToggleRow(
                icon: Icons.notifications_none_rounded,
                title: '提醒記低泊車',
                subtitle: '泊車約 90 分鐘後提醒你填收費',
                value: remindLog,
                onChanged: (v) =>
                    context.read<SettingsCubit>().setRemindLog(v),
              ),
            ],
          ),
          SizedBox(height: 22),
          _SectionLabel('關於 Recordo'),
          _SettingsCard(
            children: [
              _NavRow(
                icon: Icons.info_outline_rounded,
                title: '呢個 app 做咩',
                subtitle: '免費 · 司機報價 · 一掣記低',
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: UberColors.elevated,
                      title: Text('Recordo', style: RType.titleSm()),
                      content: Text(
                        '香港停車場收費同泊車記帳。\n'
                        '價錢由用家更新，唔係場方官方 API。\n'
                        '免費，唔賣訂閱。',
                        style: RType.body(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('知道'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              _NavRow(
                icon: Icons.mail_outline_rounded,
                title: '意見 / 問題',
                subtitle: 'hello@recordo.app',
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: 'hello@recordo.app'),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已複製 email')),
                    );
                  }
                },
              ),
              _NavRow(
                icon: Icons.privacy_tip_outlined,
                title: '私隱',
                subtitle: '資料主要存在你部機',
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: UberColors.elevated,
                      title: Text('私隱', style: RType.titleSm()),
                      content: Text(
                        '泊車記錄、UGC 場價、你報嘅新場，而家都存在本機。\n'
                        '定位只用嚟顯示附近場，唔會上傳帳戶。',
                        style: RType.body(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.tag, color: UberColors.muted, size: 22),
                    SizedBox(width: 14),
                    Expanded(child: Text('版本', style: RType.body())),
                    Text('1.0.0', style: RType.muted()),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      color: RecordoSupabase.isReady
                          ? UberColors.accent
                          : UberColors.muted,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('雲端場庫', style: RType.body()),
                          Text(
                            RecordoSupabase.isReady
                                ? '本機場庫 · 有網先同雲對 version'
                                : '未設定 · 用 OSM 後備',
                            style: RType.muted(),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      RecordoSupabase.isReady ? '已連' : '本機',
                      style: RType.muted(),
                    ),
                  ],
                ),
              ),
              _NavRow(
                icon: Icons.sync_rounded,
                title: '檢查場庫更新',
                subtitle: syncSubtitle,
                onTap: () async {
                  if (!RecordoSupabase.isReady) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('呢個 build 未接雲端 · 見 docs/SUPABASE.md'),
                      ),
                    );
                    return;
                  }
                  HapticFeedback.selectionClick();
                  final result =
                      await context.read<ParkCatalogCubit>().syncFromCloud();
                  if (!context.mounted) return;
                  final msg = switch (result) {
                    CatalogSyncResult.updated => '已下載最新場庫 · 可以離線用',
                    CatalogSyncResult.unchanged => '場庫已係最新 · 繼續用本機',
                    CatalogSyncResult.offline => '無網絡或未連雲端 · 繼續用本機',
                  };
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('Recordo · 香港泊車 · 免費', style: RType.muted()),
          ),
        ],
      ),
    );
  }
}

/// Uber-style how-to sheet for updating park prices.
class _UpdatePriceHowToSheet extends StatelessWidget {
  const _UpdatePriceHowToSheet();

  static const _steps = <(IconData, String, String)>[
    (
      Icons.map_outlined,
      '地圖揀場',
      '列表或 pin 揀你泊緊／想報嘅停車場',
    ),
    (
      Icons.chevron_right_rounded,
      '入詳情',
      '撳列尾「>」或 pin 後開場詳情',
    ),
    (
      Icons.price_change_outlined,
      '確認或改收費',
      '「價錢仍然啱」一撳確認 · 或「改收費」填時／日／夜／備註',
    ),
    (
      Icons.timer_outlined,
      '泊完順手分享',
      '結束計時填實付 HK\$ · 分享金額同時間 · 唔會改場價',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: UberColors.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: UberColors.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: UberColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.price_change_rounded,
                      color: UberColors.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('更新場價', style: RType.titleSm()),
                        const SizedBox(height: 2),
                        Text(
                          '司機報價 · 幫大家知真實收費',
                          style: RType.muted(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < _steps.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _HowToStep(
                  index: i + 1,
                  icon: _steps[i].$1,
                  title: _steps[i].$2,
                  body: _steps[i].$3,
                  isLast: i == _steps.length - 1,
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: UberColors.ctaFill,
                    foregroundColor: UberColors.ctaOnFill,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: const Text('知喇'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowToStep extends StatelessWidget {
  const _HowToStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLast,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: UberColors.elevated2,
                shape: BoxShape.circle,
                border: Border.all(
                  color: UberColors.accent.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: RType.label().copyWith(
                  color: UberColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: UberColors.hairline.withValues(alpha: 0.8),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: UberColors.elevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: UberColors.hairline.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: UberColors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RType.body()),
                      const SizedBox(height: 4),
                      Text(body, style: RType.muted()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: RType.label()),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: UberColors.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UberColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 52,
                color: UberColors.hairline,
              ),
          ],
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.highlight = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool highlight;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Colors.redAccent
        : (highlight ? UberColors.accent : UberColors.white);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RType.body().copyWith(
                      color: destructive ? Colors.redAccent : null,
                      fontWeight: highlight ? FontWeight.w600 : null,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: RType.muted()),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: UberColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: UberColors.white, size: 22),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: RType.body()),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: RType.muted()),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: UberColors.accent.withValues(alpha: 0.5),
            activeThumbColor: UberColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
