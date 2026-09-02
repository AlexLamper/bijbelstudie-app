import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/admin_repository.dart';
import '../domain/admin_entities.dart';

/// Small shared pieces of the admin screen: Dutch number/date formatting, the
/// metric tiles, the day-series bar chart and the error state.
///
/// Formatting is hand-rolled rather than `intl`: the app does not depend on
/// that package, and the admin screen only needs `nl-NL` thousands separators
/// and short dates.

/// A count, or an em dash when the server could not read it. Null is
/// "unknown" — it must never render as 0, which reads as a real measurement.
String adminNumber(num? value) {
  if (value == null) return '—';
  final whole = value.round().abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  return buffer.toString();
}

/// A euro amount with two decimals, Dutch style: `€ 1.234,50`.
String adminEuro(double? value) {
  if (value == null) return '—';
  final cents = (value * 100).round();
  final euros = cents ~/ 100;
  final rest = (cents % 100).abs().toString().padLeft(2, '0');
  return '€ ${adminNumber(euros)},$rest';
}

/// A percentage with at most one decimal: `12,4%`.
String adminPercent(double? value) {
  if (value == null) return '—';
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
  return '$text%';
}

const _months = [
  'jan',
  'feb',
  'mrt',
  'apr',
  'mei',
  'jun',
  'jul',
  'aug',
  'sep',
  'okt',
  'nov',
  'dec',
];

/// `3 mrt 2025`, or an em dash.
String adminDate(DateTime? date) {
  if (date == null) return '—';
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// `3 mrt` — the axis label under the bar chart.
String adminShortDate(String isoDay) {
  final parsed = DateTime.tryParse(isoDay);
  if (parsed == null) return isoDay;
  return '${parsed.day} ${_months[parsed.month - 1]}';
}

/// `zojuist`, `4 min geleden`, `3 dagen geleden`, then a plain date — the same
/// ladder the website's recent-signups list uses.
String adminRelative(DateTime? date) {
  if (date == null) return '—';
  final minutes = DateTime.now().difference(date).inMinutes;
  if (minutes < 1) return 'zojuist';
  if (minutes < 60) return '$minutes min geleden';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours u geleden';
  final days = hours ~/ 24;
  if (days < 30) return '$days ${days == 1 ? 'dag' : 'dagen'} geleden';
  return adminDate(date);
}

/// A labelled figure. [delta] is the small "+12" suffix under the value.
class AdminMetricTile extends StatelessWidget {
  const AdminMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.icon,
    this.tint,
  });

  final String label;
  final String value;
  final String? delta;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppTheme.teal;
    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.overline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTheme.statNumber),
          if (delta != null) ...[
            const SizedBox(height: 4),
            Text(
              delta!,
              style: AppTheme.caption.copyWith(color: AppTheme.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label/value line inside a card — the funnel and billing rows.
class AdminStatRow extends StatelessWidget {
  const AdminStatRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.showRule = true,
  });

  final String label;
  final String value;

  /// Paints the value in the warning colour — used for the figures that mean
  /// something is wrong (betaalproblemen, gemiste webhooks).
  final bool emphasis;

  final bool showRule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showRule
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outline)),
            )
          : null,
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.bodyMuted)),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTheme.bodyStrong.copyWith(
              color: emphasis ? AppTheme.flame : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// A day-series as plain bars, the phone version of the website's chart.
///
/// Only the first and last day are labelled: on a 90-day range there is no
/// room for more, and the total above the chart is what is actually read.
class AdminSeriesChart extends StatelessWidget {
  const AdminSeriesChart({
    super.key,
    required this.title,
    required this.series,
    this.tint,
    this.icon,
  });

  final String title;
  final List<AdminSeriesPoint> series;
  final Color? tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppTheme.teal;
    final total = series.fold<int>(0, (sum, point) => sum + point.count);
    final peak = series.fold<int>(0, (max, p) => p.count > max ? p.count : max);

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, style: AppTheme.bodyStrong)),
              Text('${adminNumber(total)} totaal', style: AppTheme.caption),
            ],
          ),
          const SizedBox(height: 14),
          if (series.isEmpty)
            Text('Geen data in deze periode.', style: AppTheme.bodyMuted)
          else
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in series)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0.6),
                        child: Semantics(
                          label:
                              '${adminShortDate(point.date)}: ${point.count}',
                          child: Container(
                            height: peak == 0
                                ? 2
                                : 2 + (point.count / peak) * 62,
                            decoration: BoxDecoration(
                              color: point.count == 0
                                  ? accent.withValues(alpha: 0.15)
                                  : accent.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (series.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(adminShortDate(series.first.date), style: AppTheme.caption),
                Text(adminShortDate(series.last.date), style: AppTheme.caption),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What a failed admin call looks like. A 403 is terminal — the account is not
/// an admin — so it gets no retry button, only an explanation.
class AdminErrorState extends StatelessWidget {
  const AdminErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final forbidden = error is AdminException && (error as AdminException).isForbidden;
    final message = error is AdminException
        ? (error as AdminException).message
        : 'Er ging iets mis bij het laden. Probeer het opnieuw.';

    return AppEmptyState(
      icon: forbidden ? Icons.lock_outline : Icons.error_outline,
      title: forbidden ? 'Geen toegang' : 'Laden mislukt',
      description: message,
      action: forbidden
          ? null
          : SiteButton(
              label: 'Opnieuw proberen',
              onPressed: onRetry,
              expand: false,
            ),
    );
  }
}
