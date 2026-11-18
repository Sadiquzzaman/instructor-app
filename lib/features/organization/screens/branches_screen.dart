import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

/// The check-in radius limits, the same as the API's.
const radiusMin = 25;
const radiusMax = 1000;

double round6(double v) => (v * 1e6).roundToDouble() / 1e6;

bool _validPin(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

/// The pin in a pasted Google Maps (or OpenStreetMap) link, or in plain
/// "23.7577, 90.3897" text, as the web reads it. Short links hold no
/// coordinates and give null.
({double lat, double lng})? pinFromText(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  var decoded = value;
  try {
    decoded = Uri.decodeComponent(value);
  } on ArgumentError {
    // Keep the text as pasted.
  }
  const n = r'-?\d{1,3}(?:\.\d+)?';
  for (final pattern in [
    RegExp('!3d($n)!4d($n)'),
    RegExp('@($n),($n)'),
    RegExp(
      '[?&](?:q|query|ll|center|destination)=($n)(?:,|%2C)($n)',
      caseSensitive: false,
    ),
    RegExp(
      '($n)'
      r'\s*,\s*'
      '($n)',
    ),
    RegExp(
      r'map=\d+/'
      '($n)/($n)',
    ),
    RegExp('mlat=($n).*mlon=($n)'),
  ]) {
    final m = pattern.firstMatch(decoded);
    if (m == null) continue;
    final lat = double.parse(m[1]!);
    final lng = double.parse(m[2]!);
    if (_validPin(lat, lng)) return (lat: round6(lat), lng: round6(lng));
  }
  return null;
}

/// What is wrong with a typed pin and radius, per field (the API checks
/// the same).
({String? lat, String? lng, String? radius}) locationProblems(
  String lat,
  String lng,
  String radius,
) {
  String? latP;
  String? lngP;
  final a = lat.trim();
  final b = lng.trim();
  if (a.isNotEmpty != b.isNotEmpty) {
    if (a.isEmpty) {
      latP = 'pinIncomplete';
    } else {
      lngP = 'pinIncomplete';
    }
  }
  final la = double.tryParse(a);
  final lo = double.tryParse(b);
  if (a.isNotEmpty && (la == null || la.abs() > 90)) latP = 'latInvalid';
  if (b.isNotEmpty && (lo == null || lo.abs() > 180)) lngP = 'lngInvalid';
  final r = int.tryParse(radius.trim());
  return (
    lat: latP,
    lng: lngP,
    radius: r == null || r < radiusMin || r > radiusMax
        ? 'radiusInvalid'
        : null,
  );
}

/// The web's /attendance-branches: branches with their check-in pin and
/// radius; the main branch is always there (it can't be removed). Add,
/// change, remove (asked first).
class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Branch? b) async {
    final main = ref.read(branchesProvider).value?.where((x) => x.isDefault);
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BranchFormScreen(
          branch: b,
          defaultRadius: main?.firstOrNull?.radius ?? 100,
        ),
      ),
    );
    if (saved == true) ref.invalidate(branchesProvider);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Branch b) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final name = b.name ?? l10n.branchesMainBranch;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.branchesRemoveTitle),
        content: Text(
          ref.levels(context, l10n.branchesRemoveDescription(name)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.branchesCancel),
          ),
          FilledButton(
            key: const Key('branch-remove-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.branchesRemove),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(apiClientProvider).delete('/attendance/branches/${b.id}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.branchesRemoved)));
      ref.invalidate(branchesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.code) {
            'ATTENDANCE_BRANCH_IN_USE' =>
              l10n.branchesErrorsATTENDANCEBRANCHINUSE,
            'ATTENDANCE_BRANCH_DEFAULT_KEPT' =>
              l10n.branchesErrorsATTENDANCEBRANCHDEFAULTKEPT,
            _ => apiErrorText(l10n, e),
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final branches = ref.watch(branchesProvider);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.branchesTitle, style: text.headlineSmall),
            Text(l10n.branchesIntro, style: muted),
            const SizedBox(height: AppSpacing.md),
            if (canEdit)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('branch-add'),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(l10n.branchesAdd),
                  onPressed: () => _edit(context, ref, null),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            ...branches.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(semanticsLabel: l10n.branchesTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: l10n.branchesLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(branchesProvider),
                  ),
                ),
              ],
              data: (list) => [
                for (final b in list) ...[
                  AppCard(
                    key: Key('branch-${b.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              b.name ?? l10n.branchesMainBranch,
                              style: text.titleSmall,
                            ),
                            if (b.isDefault)
                              StatusPill(
                                label: l10n.branchesMain,
                                tone: StatusTone.neutral,
                              ),
                            b.lat == null
                                ? StatusPill(
                                    label: l10n.branchesNoPin,
                                    tone: StatusTone.warning,
                                  )
                                : StatusPill(
                                    label: l10n.branchesRadiusShort(
                                      OrgTime.number(b.radius, language),
                                    ),
                                    tone: StatusTone.success,
                                  ),
                          ],
                        ),
                        if ((b.address ?? '').isNotEmpty)
                          Text(b.address!, style: muted),
                        Text(
                          '${ref.levels(context, l10n.branchesSections)}: ${OrgTime.number(b.sections, language)}',
                          style: muted,
                        ),
                        if (canEdit)
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AppSpacing.xs,
                            children: [
                              TextButton(
                                key: Key('branch-edit-${b.id}'),
                                onPressed: () => _edit(context, ref, b),
                                child: Text(l10n.branchesEdit),
                              ),
                              if (!b.isDefault)
                                TextButton(
                                  key: Key('branch-remove-${b.id}'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.danger,
                                  ),
                                  onPressed: () => _remove(context, ref, b),
                                  child: Text(l10n.branchesRemove),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (list.length == 1) Text(l10n.branchesOnlyMain, style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or change a branch: its name (the main branch keeps its own), an
/// address, and the pin and radius without a map, as on the web: paste a
/// Google Maps link, use this phone's location when standing there, or type
/// the coordinates; then check the pin on Google Maps. Pops true when
/// saved.
class BranchFormScreen extends ConsumerStatefulWidget {
  const BranchFormScreen({required this.defaultRadius, this.branch, super.key});

  final Branch? branch;
  final int defaultRadius;

  @override
  ConsumerState<BranchFormScreen> createState() => _BranchFormScreenState();
}

class _BranchFormScreenState extends ConsumerState<BranchFormScreen> {
  late final Branch? _b = widget.branch;
  late final _name = TextEditingController(text: _b?.name ?? '');
  late final _address = TextEditingController(text: _b?.address ?? '');
  late final _lat = TextEditingController(
    text: _b?.lat == null ? '' : '${_b!.lat}',
  );
  late final _lng = TextEditingController(
    text: _b?.lng == null ? '' : '${_b!.lng}',
  );
  late final _radius = TextEditingController(
    text: '${_b?.radius ?? widget.defaultRadius}',
  );
  final _link = TextEditingController();
  bool _linkFailed = false;
  String? _located;
  bool _locating = false;
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lng, _radius, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _readLink(String v) {
    final pin = pinFromText(v);
    setState(() {
      _linkFailed = v.trim().isNotEmpty && pin == null;
      if (pin != null) {
        _lat.text = '${pin.lat}';
        _lng.text = '${pin.lng}';
      }
    });
  }

  Future<void> _useMine() async {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _locating = true;
      _located = null;
    });
    try {
      final fix = await ref.read(locatorProvider).currentFix();
      if (!mounted) return;
      setState(() {
        _lat.text = '${round6(fix.latitude)}';
        _lng.text = '${round6(fix.longitude)}';
        _located = l10n.branchesLocationLocated(
          OrgTime.number(fix.accuracy.round(), language),
        );
      });
    } on Object {
      if (mounted) setState(() => _located = l10n.branchesLocationLocateFailed);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final lat = _lat.text.trim();
    final lng = _lng.text.trim();
    final body = {
      'name': _name.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'geo_lat': lat.isEmpty ? null : round6(double.parse(lat)),
      'geo_lng': lng.isEmpty ? null : round6(double.parse(lng)),
      'checkin_radius_m': int.parse(_radius.text.trim()),
    };
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final b = _b;
      if (b == null) {
        await api.post('/attendance/branches', data: body);
      } else {
        await api.patch('/attendance/branches/${b.id}', data: body);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(b == null ? l10n.branchesAdded : l10n.branchesUpdated),
        ),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = switch (e.code) {
            'ATTENDANCE_BRANCH_NAME_REQUIRED' =>
              l10n.branchesErrorsATTENDANCEBRANCHNAMEREQUIRED,
            'ATTENDANCE_BRANCH_NAME_TAKEN' =>
              l10n.branchesErrorsATTENDANCEBRANCHNAMETAKEN,
            'ATTENDANCE_BRANCH_PIN_INCOMPLETE' =>
              l10n.branchesErrorsATTENDANCEBRANCHPININCOMPLETE,
            'ATTENDANCE_BRANCHES_NOT_FOR_SOLO' =>
              l10n.branchesErrorsATTENDANCEBRANCHESNOTFORSOLO,
            _ => apiErrorText(l10n, e),
          };
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final b = _b;
    final isMain = b?.isDefault ?? false;
    final p = locationProblems(_lat.text, _lng.text, _radius.text);
    String? problemText(String? code) => switch (code) {
      'pinIncomplete' => l10n.branchesLocationErrorsPinIncomplete,
      'latInvalid' => l10n.branchesLocationErrorsLatInvalid,
      'lngInvalid' => l10n.branchesLocationErrorsLngInvalid,
      'radiusInvalid' => l10n.branchesLocationErrorsRadiusInvalid(
        OrgTime.number(radiusMin, language),
        OrgTime.number(radiusMax, language),
      ),
      _ => null,
    };
    final nameMissing = !isMain && _name.text.trim().isEmpty;
    final pinLat = double.tryParse(_lat.text.trim());
    final pinLng = double.tryParse(_lng.text.trim());
    final hasPin =
        pinLat != null && pinLng != null && p.lat == null && p.lng == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          b == null
              ? l10n.branchesAddTitle
              : l10n.branchesEditTitle(b.name ?? l10n.branchesMainBranch),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  l10n.branchesFormHint,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('branch-name'),
                  controller: _name,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: l10n.branchesName,
                    helperText: isMain ? l10n.branchesMainNameHint : null,
                    helperMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  key: const Key('branch-address'),
                  controller: _address,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: l10n.branchesAddress,
                    helperText: l10n.branchesAddressHint,
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.branchesPin, style: text.titleSmall),
                TextField(
                  key: const Key('branch-link'),
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.branchesLocationLink,
                    helperText: l10n.branchesLocationLinkHint,
                    helperMaxLines: 3,
                    errorText: _linkFailed
                        ? l10n.branchesLocationLinkFailed
                        : null,
                  ),
                  onChanged: _readLink,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('branch-use-mine'),
                  icon: const Icon(Icons.my_location),
                  label: Text(l10n.branchesLocationUseMine),
                  onPressed: _locating ? null : _useMine,
                ),
                Text(
                  _located ?? l10n.branchesLocationUseMineHint,
                  key: const Key('branch-located'),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('branch-lat'),
                        controller: _lat,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.branchesLocationLat,
                          errorText: problemText(p.lat),
                          errorMaxLines: 3,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const Key('branch-lng'),
                        controller: _lng,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.branchesLocationLng,
                          errorText: problemText(p.lng),
                          errorMaxLines: 3,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasPin) ...[
                      TextButton.icon(
                        key: const Key('branch-check'),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.branchesLocationCheck),
                        onPressed: () => ref.read(openLinkProvider)(
                          Uri.parse(
                            'https://www.google.com/maps?q=$pinLat,$pinLng',
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('branch-clear'),
                        onPressed: () => setState(() {
                          _lat.clear();
                          _lng.clear();
                          _link.clear();
                        }),
                        child: Text(l10n.branchesLocationClear),
                      ),
                    ] else
                      Text(
                        l10n.branchesLocationNoPin,
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('branch-radius'),
                  controller: _radius,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.branchesLocationRadius,
                    helperText: l10n.branchesLocationRadiusHint(
                      OrgTime.number(radiusMin, language),
                      OrgTime.number(radiusMax, language),
                    ),
                    helperMaxLines: 3,
                    suffixText: l10n.branchesLocationMetres,
                    errorText: problemText(p.radius),
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _problem!,
                      key: const Key('branch-problem'),
                      style: TextStyle(color: colors.danger),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.branchesCancel),
                    ),
                    FilledButton(
                      key: const Key('branch-save'),
                      onPressed:
                          _saving ||
                              nameMissing ||
                              p.lat != null ||
                              p.lng != null ||
                              p.radius != null
                          ? null
                          : _save,
                      child: Text(
                        b == null ? l10n.branchesAdd : l10n.branchesSaveChanges,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
