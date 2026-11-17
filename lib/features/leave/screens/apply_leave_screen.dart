import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/leave/data/leave_repository.dart';
import 'package:instructor_app/features/leave/leave_text.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// Leave can start this many days back (the API's rule, the picker's first
/// day); how far ahead the server decides (TOO_FAR).
const _backDays = 30;
const _pickerAheadDays = 365;

/// "Apply for leave" for oneself: first day, last day (empty for one day),
/// a reason, and an optional photo or PDF. Pops the saved request.
class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({required this.today, super.key});

  /// The school's today (`YYYY-MM-DD`), from the server.
  final String today;

  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  final _reason = TextEditingController();
  String? _from;
  String? _to;
  String? _fileId;
  bool _uploading = false;
  bool _saving = false;
  String? _problem;

  String get _today => widget.today.isNotEmpty ? widget.today : OrgTime.today();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool first}) async {
    DateTime d(String s) => DateTime.parse('${s}T00:00:00');
    final current = first ? _from : (_to ?? _from);
    final picked = await showDatePicker(
      context: context,
      initialDate: d(current ?? _today),
      firstDate: d(
        first
            ? addDays(_today, -_backDays)
            : (_from ?? addDays(_today, -_backDays)),
      ),
      lastDate: d(addDays(_today, _pickerAheadDays)),
    );
    if (picked == null) return;
    final value = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {
      _problem = null;
      if (first) {
        _from = value;
        if (_to != null && _to!.compareTo(value) < 0) _to = null;
      } else {
        _to = value;
      }
    });
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    // The web's checks, in its order.
    if (_from == null || (_to != null && _to!.compareTo(_from!) < 0)) {
      setState(() => _problem = l10n.leaveErrorsATTENDANCELEAVEDATESINVALID);
      return;
    }
    if (_reason.text.trim().length < 3) {
      setState(() => _problem = l10n.leaveErrorsREASONREQUIRED);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final saved = await ref
          .read(leaveRepositoryProvider)
          .apply(
            from: _from!,
            to: _to ?? _from!,
            reason: _reason.text.trim(),
            fileId: _fileId,
          );
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      final known = leaveErrorText(l10n, e, language);
      if (known != null) {
        setState(() => _problem = known);
      } else if (!await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      )) {
        if (mounted) setState(() => _problem = apiErrorText(l10n, e));
      }
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
    String shown(String? day) => day == null
        ? '—'
        : DateFormat.yMMMEd(OrgTime.intlLocale(language))
              .format(DateTime.parse('${day}T00:00:00Z'));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.leaveFormTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  l10n.leaveFormHint,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                _DateField(
                  key: const Key('leave-from'),
                  label: l10n.leaveFormFrom,
                  value: shown(_from),
                  onTap: () => _pick(first: true),
                ),
                const SizedBox(height: AppSpacing.md),
                _DateField(
                  key: const Key('leave-to'),
                  label: l10n.leaveFormTo,
                  hint: l10n.leaveFormToHint,
                  value: shown(_to),
                  onTap: () => _pick(first: false),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  key: const Key('leave-reason'),
                  label: l10n.leaveFormReason,
                  hint: l10n.leaveFormReasonHint,
                  controller: _reason,
                  maxLines: 3,
                  onChanged: (_) {
                    if (_problem != null) setState(() => _problem = null);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AttachmentField(
                  label: l10n.leaveFormFile,
                  purpose: FilePurpose.leave,
                  maxFiles: 1,
                  enabled: !_saving,
                  onChanged: (files) =>
                      setState(() => _fileId = files.firstOrNull?.id),
                  onBusyChanged: (busy) => setState(() => _uploading = busy),
                ),
                if (_problem != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _problem!,
                      style: text.bodyMedium?.copyWith(color: colors.danger),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  key: const Key('leave-submit'),
                  label: _uploading
                      ? l10n.leaveFormUploading
                      : l10n.leaveFormSubmit,
                  onPressed: _uploading ? null : _submit,
                  loading: _saving,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled date that opens the picker.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    super.key,
  });

  final String label;
  final String value;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
    );
  }
}
