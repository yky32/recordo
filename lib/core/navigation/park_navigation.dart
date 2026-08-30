import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open system / Google / Apple Maps navigation to a park.
abstract final class ParkNavigation {
  static Future<void> showChooser(BuildContext context, Park park) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: UberColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: UberColors.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Text('導航去「${park.name}」', style: RType.titleSm()),
                const SizedBox(height: 8),
                if (!kIsWeb && Platform.isIOS)
                  _tile(
                    ctx,
                    icon: Icons.map_outlined,
                    label: 'Apple 地圖',
                    onTap: () => _open(ctx, appleMaps(park)),
                  ),
                _tile(
                  ctx,
                  icon: Icons.navigation_outlined,
                  label: 'Google 地圖',
                  onTap: () => _open(ctx, googleMaps(park)),
                ),
                if (!kIsWeb && Platform.isAndroid)
                  _tile(
                    ctx,
                    icon: Icons.directions_car_outlined,
                    label: '系統導航',
                    onTap: () => _open(ctx, geoUri(park)),
                  ),
                _tile(
                  ctx,
                  icon: Icons.copy_rounded,
                  label: '複製座標',
                  onTap: () async {
                    final s =
                        '${park.lat.toStringAsFixed(6)}, ${park.lng.toStringAsFixed(6)}';
                    await Clipboard.setData(ClipboardData(text: s));
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已複製 $s')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _tile(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: UberColors.white),
      title: Text(label, style: RType.body()),
      trailing: Icon(Icons.chevron_right, color: UberColors.muted),
      onTap: onTap,
    );
  }

  static Future<void> _open(BuildContext ctx, Uri uri) async {
    Navigator.pop(ctx);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && ctx.mounted) {
      // fallback web google
    }
  }

  static Uri appleMapsLatLng(double lat, double lng, String name) {
    final q = Uri.encodeComponent(name);
    return Uri.parse(
      'https://maps.apple.com/?daddr=$lat,$lng&q=$q&dirflg=d',
    );
  }

  static Uri googleMapsLatLng(double lat, double lng) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&travelmode=driving',
    );
  }

  static Future<void> openDriving(
    BuildContext context, {
    required double lat,
    required double lng,
    required String name,
  }) async {
    HapticFeedback.selectionClick();
    if (!kIsWeb && Platform.isIOS) {
      final ok = await launchUrl(
        appleMapsLatLng(lat, lng, name),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    }
    await launchUrl(
      googleMapsLatLng(lat, lng),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Official TD 入錶易. We cannot take payment.
  static const hkeMeterStoreHttps =
      'https://apps.apple.com/hk/app/hkemeter/id1508101096';
  static const hkeMeterStoreItms =
      'itms-apps://itunes.apple.com/app/id1508101096';

  static Future<void> openHkeMeter() async {
    HapticFeedback.selectionClick();
    final itms = Uri.parse(hkeMeterStoreItms);
    final https = Uri.parse(hkeMeterStoreHttps);
    final ok = await launchUrl(itms, mode: LaunchMode.externalApplication);
    if (!ok) {
      await launchUrl(https, mode: LaunchMode.externalApplication);
    }
  }

  static Uri appleMaps(Park p) => appleMapsLatLng(p.lat, p.lng, p.name);

  static Uri googleMaps(Park p) => googleMapsLatLng(p.lat, p.lng);

  static Uri geoUri(Park p) {
    final label = Uri.encodeComponent(p.name);
    return Uri.parse('geo:${p.lat},${p.lng}?q=${p.lat},${p.lng}($label)');
  }
}
