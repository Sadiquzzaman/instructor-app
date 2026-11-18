import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

typedef Holiday = ({String id, String from, String to, String? note, int days});

final holidaysProvider = FutureProvider.autoDispose.family<List<Holiday>, int>((
  ref,
  year,
) async {
  ref.watch(workspaceKeyProvider);
  final p =
      (await ref
              .read(apiClientProvider)
              .get(
                '/holidays',
                query: {'from': '$year-01-01', 'to': '$year-12-31'},
              ))
          .payload;
  return [
    if (p is List)
      for (final h in p)
        if (h is Map && h['id'] is String && h['date_from'] is String)
          (
            id: h['id'] as String,
            from: (h['date_from'] as String).substring(0, 10),
            to: ((h['date_to'] ?? h['date_from']) as String).substring(0, 10),
            note: h['name'] as String?,
            days: (h['days'] as num?)?.toInt() ?? 1,
          ),
  ];
}, retry: (retryCount, error) => null);

/// The web's /holidays: holidays and closures by year, single days or
/// ranges with a note; the weekly off days beside them. Only days from
/// today on can be added, changed or removed (asked first).
class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});

  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  late final String _today = OrgTime.today();
  late int _year = int.parse(_today.substring(0, 4));

  Future<void> _edit(Holiday? h) async {
    final saved = await showDialog<int>(
      context: context,
      builder: (_) => _HolidayDialog(holiday: h, today: _today),
    );
    if (saved == null) return;
    ref.invalidate(holidaysProvider);
    if (saved != _year) setState(() => _year = saved);
  }

  Future<void> _remove(Holiday h, String dates) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.holidaysRemoveTitle),
        content: Text(l10n.holidaysRemoveDescription(dates)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.holidaysCancel),
          ),
          FilledButton(
            key: const Key('holiday-remove-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.holidaysRemove),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(apiClientProvider).delete('/holidays/${h.id}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.holidaysRemoved)));
      ref.invalidate(holidaysProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final holidays = ref.watch(holidaysProvider(_year));
    final offDays = ref.watch(attendanceSettingsProvider).value?.offDays;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final thisYear = int.parse(_today.substring(0, 4));
    String dates(Holiday h) => h.from == h.to
        ? OrgTime.schoolDay(h.from, language)
        : l10n.holidaysRange(
            OrgTime.schoolDay(h.from, language),
            OrgTime.schoolDay(h.to, language),
          );
    String year(int y) => OrgTime.number(y, language).replaceAll(',', '');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.holidaysTitle, style: text.headlineSmall),
            Text(l10n.holidaysIntro, style: muted),
            const SizedBox(height: AppSpacing.md),
            if (canEdit)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('holiday-add'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.holidaysAdd),
                  onPressed: () => _edit(null),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int>(
              key: const Key('holiday-year'),
              initialValue: _year,
              decoration: InputDecoration(labelText: l10n.holidaysYear),
              items: [
                for (final y in [thisYear - 1, thisYear, thisYear + 1])
                  DropdownMenuItem(value: y, child: Text(year(y))),
              ],
              onChanged: (v) => setState(() => _year = v ?? _year),
            ),
            if (offDays != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  offDays.isEmpty
                      ? l10n.holidaysNoOffDays
                      : l10n.holidaysOffDays(
                          [
                            for (final d in schoolWeek)
                              if (offDays.contains(d)) weekdayName(l10n, d),
                          ].join(', '),
                        ),
                  key: const Key('holiday-off-days'),
                  style: muted,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.holidaysListTitle(year(_year)), style: text.titleMedium),
            ...holidays.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [
                SizedBox(
                  height: 240,
                  child: ErrorView(
                    title: l10n.holidaysLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(holidaysProvider(_year)),
                  ),
                ),
              ],
              data: (list) => [
                if (list.isEmpty)
                  SizedBox(
                    height: 200,
                    child: EmptyView(
                      icon: Icons.beach_access_outlined,
                      title: l10n.holidaysEmpty(year(_year)),
                      message: canEdit ? l10n.holidaysEmptyHint : null,
                    ),
                  )
                else
                  Text(
                    l10n.holidaysSummary(
                      list.length,
                      list.fold<int>(0, (s, h) => s + h.days),
                    ),
                    style: muted,
                  ),
                for (final h in list) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    key: Key('holiday-${h.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(dates(h), style: text.titleSmall),
                            switch ((
                              h.to.compareTo(_today) < 0,
                              h.from.compareTo(_today) <= 0,
                            )) {
                              (true, _) => StatusPill(
                                label: l10n.holidaysWhenPast,
                                tone: StatusTone.neutral,
                              ),
                              (false, true) => StatusPill(
                                label: l10n.holidaysWhenNow,
                                tone: StatusTone.success,
                              ),
                              _ => StatusPill(
                                label: l10n.holidaysWhenUpcoming,
                                tone: StatusTone.info,
                              ),
                            },
                          ],
                        ),
                        Text(
                          '${l10n.holidaysDays}: ${OrgTime.number(h.days, language)}'
                          '${(h.note ?? '').isNotEmpty ? ' · ${h.note}' : ''}',
                          style: muted,
                        ),
                        if (canEdit)
                          h.from.compareTo(_today) >= 0
                              ? Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: AppSpacing.xs,
                                  children: [
                                    TextButton(
                                      key: Key('holiday-edit-${h.id}'),
                                      onPressed: () => _edit(h),
                                      child: Text(l10n.holidaysEdit),
                                    ),
                                    TextButton(
                                      key: Key('holiday-remove-${h.id}'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: colors.danger,
                                      ),
                                      onPressed: () => _remove(h, dates(h)),
                                      child: Text(l10n.holidaysRemove),
                                    ),
                                  ],
                                )
                              : Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    l10n.holidaysLocked,
                                    style: muted,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or change a holiday: a first day (today or later), an optional last
/// day and a note. Pops the year it falls in when saved.
class _HolidayDialog extends ConsumerStatefulWidget {
  const _HolidayDialog({required this.today, this.holiday});

  final Holiday? holiday;
  final String today;

  @override
  ConsumerState<_HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends ConsumerState<_HolidayDialog> {
  late String? _from = widget.holiday?.from;
  late String? _to = widget.holiday?.to;
  late final _note = TextEditingController(text: widget.holiday?.note ?? '');
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final from = _from!;
    final h = widget.holiday;
    final body = {
      'date_from': from,
      'date_to': _to ?? from,
      'name': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (h == null) {
        await api.post('/holidays', data: body);
      } else {
        await api.patch('/holidays/${h.id}', data: body);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(h == null ? l10n.holidaysAdded : l10n.holidaysUpdated),
        ),
      );
      navigator.pop(int.parse(from.substring(0, 4)));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = switch (e.code) {
            'HOLIDAY_PAST_LOCKED' => l10n.holidaysErrorsHOLIDAYPASTLOCKED,
            'HOLIDAY_RANGE_INVALID' => l10n.holidaysErrorsHOLIDAYRANGEINVALID,
            'HOLIDAY_RANGE_TOO_LONG' => l10n.holidaysErrorsHOLIDAYRANGETOOLONG,
            'HOLIDAY_INVALID_DATE' => l10n.holidaysErrorsHOLIDAYINVALIDDATE,
            _ => apiErrorText(l10n, e),
          };
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.holiday != null;
    return AlertDialog(
      title: Text(editing ? l10n.holidaysEditTitle : l10n.holidaysAddTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.holidaysFormHint),
            const SizedBox(height: AppSpacing.sm),
            DateField(
              key: const Key('holiday-from'),
              label: l10n.holidaysFrom,
              value: _from,
              min: widget.today,
              onChanged: (v) => setState(() {
                _from = v;
                if (_to != null && _to!.compareTo(v) < 0) _to = null;
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            DateField(
              key: const Key('holiday-to'),
              label: l10n.holidaysTo,
              value: _to,
              min: _from ?? widget.today,
              onChanged: (v) => setState(() => _to = v),
            ),
            Text(
              l10n.holidaysToHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              key: const Key('holiday-note'),
              controller: _note,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.holidaysNoteLabel,
                helperText: l10n.holidaysNoteHint,
              ),
            ),
            if (_problem != null)
              Text(
                _problem!,
                key: const Key('holiday-problem'),
                style: TextStyle(color: AppColors.of(context).danger),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.holidaysCancel),
        ),
        FilledButton(
          key: const Key('holiday-save'),
          onPressed: _saving || _from == null ? null : _save,
          child: Text(editing ? l10n.holidaysSaveChanges : l10n.holidaysAdd),
        ),
      ],
    );
  }
}
