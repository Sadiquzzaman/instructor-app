import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

/// `GET /attendance/settings`.
typedef AttendanceSettings = ({
  int grace,
  List<int> offDays,
  bool smsLate,
  bool smsAbsent,
  bool smsLeave,
  int repeatDays,
});

AttendanceSettings attendanceSettingsFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  final sms = j['guardian_sms'] is Map
      ? j['guardian_sms'] as Map
      : const <String, Object?>{};
  return (
    grace: (j['late_grace_minutes'] as num?)?.toInt() ?? 10,
    offDays: [
      if (j['weekly_off_days'] is List)
        for (final d in j['weekly_off_days'] as List)
          if (d is num) d.toInt(),
    ],
    smsLate: sms['late'] == true,
    smsAbsent: sms['absent'] == true,
    smsLeave: sms['leave'] == true,
    repeatDays: (j['repeat_absence_days'] as num?)?.toInt() ?? 3,
  );
}

/// A branch (`GET /attendance/branches`).
typedef Branch = ({
  String id,
  String? name,
  String? address,
  double? lat,
  double? lng,
  int radius,
  bool isDefault,
  int sections,
});

Branch? branchFromJson(Object? b) {
  if (b is! Map || b['id'] is! String) return null;
  return (
    id: b['id'] as String,
    name: b['name'] as String?,
    address: b['address'] as String?,
    lat: (b['geo_lat'] as num?)?.toDouble(),
    lng: (b['geo_lng'] as num?)?.toDouble(),
    radius: (b['checkin_radius_m'] as num?)?.toInt() ?? 100,
    isDefault: b['is_default'] == true,
    sections: (b['section_count'] as num?)?.toInt() ?? 0,
  );
}

final attendanceSettingsProvider =
    FutureProvider.autoDispose<AttendanceSettings>((ref) async {
      ref.watch(workspaceKeyProvider);
      return attendanceSettingsFromJson(
        (await ref.read(apiClientProvider).get('/attendance/settings')).payload,
      );
    }, retry: (retryCount, error) => null);

final branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/attendance/branches'))
      .payload;
  return [
    if (p is List)
      for (final b in p) ?branchFromJson(b),
  ];
}, retry: (retryCount, error) => null);

/// The school week as on the web: Saturday first (ISO days).
const schoolWeek = [6, 7, 1, 2, 3, 4, 5];

String weekdayName(AppLocalizations l10n, int day) => switch (day) {
  1 => l10n.attendanceSettingsWeekday1,
  2 => l10n.attendanceSettingsWeekday2,
  3 => l10n.attendanceSettingsWeekday3,
  4 => l10n.attendanceSettingsWeekday4,
  5 => l10n.attendanceSettingsWeekday5,
  6 => l10n.attendanceSettingsWeekday6,
  _ => l10n.attendanceSettingsWeekday7,
};

/// The web's /attendance-settings: where check-in is allowed (the
/// branches and their radius; changing them is on the branches screen),
/// the grace before Late, weekly days off, guardian SMS and the
/// repeated-absence alert. Owners and admins change them; others read.
class AttendanceSettingsScreen extends ConsumerStatefulWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  ConsumerState<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState
    extends ConsumerState<AttendanceSettingsScreen> {
  AttendanceSettings? _draft;
  AttendanceSettings? _saved;
  final _grace = TextEditingController();
  final _repeat = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _grace.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _show(AttendanceSettings s) {
    _saved = s;
    _draft = s;
    _grace.text = '${s.grace}';
    _repeat.text = '${s.repeatDays}';
  }

  int? _whole(String v, int min, int max) {
    final n = int.tryParse(v.trim());
    return n != null && n >= min && n <= max ? n : null;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final d = _draft!;
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .patch(
            '/attendance/settings',
            data: {
              'late_grace_minutes': _whole(_grace.text, 0, 60),
              'weekly_off_days': d.offDays,
              'guardian_sms': {
                'late': d.smsLate,
                'absent': d.smsAbsent,
                'leave': d.smsLeave,
              },
              'repeat_absence_days': _whole(_repeat.text, 2, 30),
            },
          );
      if (!mounted) return;
      setState(() => _show(attendanceSettingsFromJson(r.payload)));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.attendanceSettingsSaved)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final loaded = ref.watch(attendanceSettingsProvider);
    final branches = ref.watch(branchesProvider).value;
    if (_saved == null && loaded.value != null) _show(loaded.value!);
    final d = _draft;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final graceOk = _whole(_grace.text, 0, 60) != null;
    final repeatOk = _whole(_repeat.text, 2, 30) != null;
    final noWorkingDay = (d?.offDays.length ?? 0) >= 7;
    final changed =
        d != null &&
        (d != _saved ||
            _grace.text.trim() != '${_saved!.grace}' ||
            _repeat.text.trim() != '${_saved!.repeatDays}');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.attendanceSettingsTitle, style: text.headlineSmall),
            Text(
              ref.levels(context, l10n.attendanceSettingsIntro),
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            if (d == null)
              loaded.hasError
                  ? SizedBox(
                      height: 280,
                      child: ErrorView(
                        title: l10n.attendanceSettingsLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () =>
                            ref.invalidate(attendanceSettingsProvider),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: LoadingView(
                        semanticsLabel: l10n.attendanceSettingsTitle,
                      ),
                    )
            else ...[
              if (!canEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    l10n.attendanceSettingsReadOnly,
                    key: const Key('settings-read-only'),
                    style: muted,
                  ),
                ),
              AppCard(
                key: const Key('settings-location'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.attendanceSettingsLocationTitle,
                      style: text.titleMedium,
                    ),
                    Text(l10n.attendanceSettingsLocationIntro, style: muted),
                    const SizedBox(height: AppSpacing.sm),
                    if (branches == null)
                      const LinearProgressIndicator()
                    else ...[
                      Text(
                        l10n.attendanceSettingsBranchesSummary(branches.length),
                      ),
                      for (final b in branches)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              Text(
                                (b.name ?? '').isNotEmpty
                                    ? b.name!
                                    : l10n.branchesMainBranch,
                                style: text.labelLarge,
                              ),
                              Text(
                                b.lat == null
                                    ? l10n.branchesNoPin
                                    : l10n.branchesRadiusShort(
                                        OrgTime.number(b.radius, language),
                                      ),
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                      if (canEdit)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const Key('settings-branches'),
                            onPressed: () =>
                                context.push(AppRoutes.attendanceBranches),
                            child: Text(l10n.attendanceSettingsManageBranches),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('settings-days'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.attendanceSettingsDaysTitle,
                      style: text.titleMedium,
                    ),
                    Text(
                      ref.levels(context, l10n.attendanceSettingsDaysIntro),
                      style: muted,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('settings-grace'),
                      controller: _grace,
                      enabled: canEdit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.attendanceSettingsGrace,
                        helperText: ref.levels(
                          context,
                          l10n.attendanceSettingsGraceHint,
                        ),
                        helperMaxLines: 3,
                        suffixText: l10n.attendanceSettingsMinutesUnit,
                        errorText: graceOk
                            ? null
                            : l10n.attendanceSettingsGraceError,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.attendanceSettingsOffDays,
                      style: text.labelLarge,
                    ),
                    Text(l10n.attendanceSettingsOffDaysHint, style: muted),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        for (final day in schoolWeek)
                          FilterChip(
                            key: Key('off-$day'),
                            label: Text(weekdayName(l10n, day)),
                            selected: d.offDays.contains(day),
                            onSelected: canEdit
                                ? (on) => setState(() {
                                    final days = [
                                      for (final x in d.offDays)
                                        if (x != day) x,
                                      if (on) day,
                                    ]..sort();
                                    _draft = (
                                      grace: d.grace,
                                      offDays: days,
                                      smsLate: d.smsLate,
                                      smsAbsent: d.smsAbsent,
                                      smsLeave: d.smsLeave,
                                      repeatDays: d.repeatDays,
                                    );
                                  })
                                : null,
                          ),
                      ],
                    ),
                    if (noWorkingDay)
                      Text(
                        l10n.attendanceSettingsNoWorkingDay,
                        style: text.bodySmall?.copyWith(color: colors.danger),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('settings-alerts'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.attendanceSettingsAlertsTitle,
                      style: text.titleMedium,
                    ),
                    Text(l10n.attendanceSettingsAlertsIntro, style: muted),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.attendanceSettingsGuardianSms,
                      style: text.labelLarge,
                    ),
                    for (final (key, label, hint, on) in [
                      (
                        'late',
                        l10n.attendanceSettingsSmsLate,
                        l10n.attendanceSettingsSmsHintLate,
                        d.smsLate,
                      ),
                      (
                        'absent',
                        l10n.attendanceSettingsSmsAbsent,
                        l10n.attendanceSettingsSmsHintAbsent,
                        d.smsAbsent,
                      ),
                      (
                        'leave',
                        l10n.attendanceSettingsSmsLeave,
                        l10n.attendanceSettingsSmsHintLeave,
                        d.smsLeave,
                      ),
                    ])
                      CheckboxListTile(
                        key: Key('sms-$key'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: on,
                        title: Text(label),
                        subtitle: Text(hint),
                        onChanged: canEdit
                            ? (v) => setState(
                                () => _draft = (
                                  grace: d.grace,
                                  offDays: d.offDays,
                                  smsLate: key == 'late'
                                      ? v == true
                                      : d.smsLate,
                                  smsAbsent: key == 'absent'
                                      ? v == true
                                      : d.smsAbsent,
                                  smsLeave: key == 'leave'
                                      ? v == true
                                      : d.smsLeave,
                                  repeatDays: d.repeatDays,
                                ),
                              )
                            : null,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('settings-repeat'),
                      controller: _repeat,
                      enabled: canEdit,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.attendanceSettingsRepeatDays,
                        helperText: l10n.attendanceSettingsRepeatDaysHint,
                        helperMaxLines: 3,
                        suffixText: l10n.attendanceSettingsDaysUnit,
                        errorText: repeatOk
                            ? null
                            : l10n.attendanceSettingsRepeatDaysError,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      key: const Key('settings-undo'),
                      onPressed: changed && !_saving
                          ? () => setState(() => _show(_saved!))
                          : null,
                      child: Text(l10n.attendanceSettingsUndo),
                    ),
                    FilledButton(
                      key: const Key('settings-save'),
                      onPressed:
                          changed &&
                              !_saving &&
                              graceOk &&
                              repeatOk &&
                              !noWorkingDay
                          ? _save
                          : null,
                      child: Text(l10n.attendanceSettingsSave),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
