import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:recordo/app/theme/recordo_theme.dart';
import 'package:recordo/app/theme/uber_colors.dart';
import 'package:recordo/features/session/session_cubit.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · HH:mm');
    return Scaffold(
      backgroundColor: UberColors.black,
      appBar: AppBar(title: Text('記錄', style: RType.titleSm())),
      body: BlocBuilder<SessionCubit, SessionState>(
        builder: (context, state) {
          final items = state.history;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '未有記錄\n返地圖右滑開始計時。',
                  textAlign: TextAlign.center,
                  style: RType.muted(),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: UberColors.elevated,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text('本月', style: RType.muted()),
                    const Spacer(),
                    Text(
                      'HK\$${state.monthTotal.toStringAsFixed(0)}',
                      style: RType.title(),
                    ),
                  ],
                ),
              ),
              ...items.map((s) {
                final mins = s.elapsed.inMinutes;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: UberColors.elevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.parkName ?? '泊車',
                              style: RType.body(),
                            ),
                            Text(
                              '${fmt.format(s.startedAt.toLocal())} · ${mins}m',
                              style: RType.muted(),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        s.amountHkd == null
                            ? '—'
                            : 'HK\$${s.amountHkd!.toStringAsFixed(0)}',
                        style: RType.titleSm(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
