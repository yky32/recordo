import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uber-style settings hub.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _haptics = true;
  bool _remindLog = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _haptics = prefs.getBool(StorageKeys.prefHaptics) ?? true;
      _remindLog = prefs.getBool(StorageKeys.prefRemindLog) ?? false;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _clearHistory() async {
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
    if (ok != true || !mounted) return;
    await Bootstrap.store.remove(StorageKeys.sessions);
    await Bootstrap.store.remove(StorageKeys.activeSession);
    HapticFeedback.mediumImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除記錄')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    backgroundColor: UberColors.elevated,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (ctx) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: UberColors.hairline,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('更新場價', style: RType.title()),
                          const SizedBox(height: 12),
                          Text(
                            '1. 地圖列表揀一個場\n'
                            '2. 撳「>」入詳情\n'
                            '3.「價錢仍然啱」或「改收費」\n'
                            '4. 泊完填 HK\$ 可順手更新',
                            style: RType.body(),
                          ),
                        ],
                      ),
                    ),
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
                onTap: _clearHistory,
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
                value: _haptics,
                onChanged: (v) {
                  setState(() => _haptics = v);
                  _setBool(StorageKeys.prefHaptics, v);
                },
              ),
              _ToggleRow(
                icon: Icons.notifications_none_rounded,
                title: '提醒記低泊車',
                subtitle: '之後版本 · 而家預留',
                value: _remindLog,
                onChanged: (v) {
                  setState(() => _remindLog = v);
                  _setBool(StorageKeys.prefRemindLog, v);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('通知稍後版本先上')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
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
                    const Icon(Icons.tag, color: UberColors.muted, size: 22),
                    const SizedBox(width: 14),
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
                    Expanded(child: Text('雲端 UGC', style: RType.body())),
                    Text(
                      RecordoSupabase.isReady ? 'Supabase 已連' : '本機 only',
                      style: RType.muted(),
                    ),
                  ],
                ),
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
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(
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
            const SizedBox(width: 14),
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
            const Icon(Icons.chevron_right_rounded, color: UberColors.muted),
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
          const SizedBox(width: 14),
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
