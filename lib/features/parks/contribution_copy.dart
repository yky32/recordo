import 'package:recordo/features/parks/park.dart';

/// Snackbar copy after UGC contributions.
abstract final class ContributionCopy {
  static String paidSession({required bool cloud}) {
    if (cloud) return '已分享實付 · 多謝';
    return '已記低實付（本機 · 有網會同步）';
  }

  static String priceReport({required bool cloud, Park? park}) {
    final n = park?.ugcConfirms ?? 0;
    if (cloud && n > 0) {
      return '已分享 · 呢個場而家 $n 人報過';
    }
    if (cloud) return '已分享場價 · 多謝';
    return '已更新場價（本機 · 有網會同步）';
  }

  static String priceConfirm({required bool cloud, Park? park}) {
    final n = park?.ugcConfirms ?? 0;
    if (cloud && n > 0) {
      return '多謝確認 · 呢個場 $n 人報過';
    }
    if (cloud) return '多謝 · 已確認，並分享到雲端';
    return '多謝 · 已確認（本機 · 稍後有網會再同步）';
  }
}
