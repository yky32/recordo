import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/parks/sync_outbox.dart';

/// Resume → version check + outbox flush, throttled.
class CatalogLifecycle extends StatefulWidget {
  const CatalogLifecycle({super.key, required this.child});

  final Widget child;

  @override
  State<CatalogLifecycle> createState() => _CatalogLifecycleState();
}

class _CatalogLifecycleState extends State<CatalogLifecycle>
    with WidgetsBindingObserver {
  DateTime? _lastResumeSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (!resumeShouldSync(_lastResumeSync, now)) return;
    _lastResumeSync = now;
    context.read<ParkCatalogCubit>().syncFromCloud();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
