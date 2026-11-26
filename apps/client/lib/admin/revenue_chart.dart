import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../screens/pass_screen.dart' show formatUgx;
import '../theme/tokens.dart';

/// Money taken each day for the last 30 days, as bars: one series, so the
/// title names it and there is no legend. Each day's whole column is its
/// hover and tap target, with a tooltip. The bars are the accent, checked
/// against the card's surface; every figure is in text colours. "Show as
/// table" lists the same days.
class RevenueChart extends StatefulWidget {
  const RevenueChart({super.key, required this.days});

  final List<DayRevenue> days;

  @override
  State<RevenueChart> createState() => _RevenueChartState();
}

class _RevenueChartState extends State<RevenueChart> {
  static const double _height = 140;
  bool _table = false;

  String _day(BuildContext context, DateTime day) =>
      MaterialLocalizations.of(context).formatShortMonthDay(day);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final days = widget.days;
    final most = days.fold<int>(
      0,
      (m, d) => d.revenueUgx > m ? d.revenueUgx : m,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: VeloraColors.textMuted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.xs,
      children: [
        // Wraps on a narrow phone with large text.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.revenueChartTitle,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _table = !_table),
              child: Text(_table ? l.showAsChart : l.showAsTable),
            ),
          ],
        ),
        if (days.isEmpty)
          Text(l.revenueChartEmpty)
        else if (_table)
          _RevenueTable(days: days, day: (d) => _day(context, d))
        else ...[
          Text(
            most == 0 ? l.revenueChartNone : formatUgx(context, most),
            style: muted,
          ),
          SizedBox(
            height: _height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (index, day) in days.indexed)
                  Expanded(
                    child: Tooltip(
                      message: l.revenueChartDay(
                        _day(context, day.day),
                        formatUgx(context, day.revenueUgx),
                        day.completed,
                      ),
                      child: Semantics(
                        label: l.revenueChartDay(
                          _day(context, day.day),
                          formatUgx(context, day.revenueUgx),
                          day.completed,
                        ),
                        excludeSemantics: true,
                        child: Container(
                          // The whole column, not just the bar, is the target.
                          height: _height,
                          color: Colors.transparent,
                          alignment: Alignment.bottomCenter,
                          // A 2px gap between bars.
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : 1,
                            right: index == days.length - 1 ? 0 : 1,
                          ),
                          child: Container(
                            height: most == 0 || day.revenueUgx == 0
                                ? 0
                                : (day.revenueUgx / most * _height).clamp(
                                    2,
                                    _height,
                                  ),
                            decoration: const BoxDecoration(
                              color: VeloraColors.accent,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // The baseline, recessive.
          Container(height: 1, color: VeloraColors.outlineSubtle),
          Row(
            children: [
              Flexible(
                child: Text(_day(context, days.first.day), style: muted),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _day(context, days.last.day),
                  style: muted,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RevenueTable extends StatelessWidget {
  const _RevenueTable({required this.days, required this.day});

  final List<DayRevenue> days;
  final String Function(DateTime) day;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in days.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VeloraSpacing.xxs),
            child: Row(
              children: [
                Expanded(child: Text(day(d.day))),
                Expanded(child: Text(l.paymentsCount(d.completed))),
                Expanded(
                  child: Text(
                    formatUgx(context, d.revenueUgx),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
