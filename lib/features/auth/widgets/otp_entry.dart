import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// The 6-digit code field. One field (not six boxes) so the phone can fill
/// the code from the SMS and screen readers read it as one; digits only.
class OtpField extends StatelessWidget {
  const OtpField({
    required this.controller,
    this.errorText,
    this.onSubmitted,
    super.key,
  });

  static const length = 6;

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    return TextField(
      key: const Key('otp'),
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      textAlign: TextAlign.center,
      style: style?.copyWith(letterSpacing: AppSpacing.md),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: context.l10n.authOtpCode,
        errorText: errorText,
        counterText: '',
      ),
    );
  }
}

/// "Resend available in 01:00", then a "Resend code" button (the web's
/// ResendCode). The button calls [onResend]; the timer then starts again.
class ResendTimer extends StatefulWidget {
  const ResendTimer({required this.onResend, this.seconds = 60, super.key});

  final Future<void> Function() onResend;
  final int seconds;

  @override
  State<ResendTimer> createState() => _ResendTimerState();
}

class _ResendTimerState extends State<ResendTimer> {
  Timer? _timer;
  late int _left = widget.seconds;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _left = widget.seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = _left - 1);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await widget.onResend();
      if (mounted) _start();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    if (_left > 0) {
      return Text(
        l10n.authOtpResendIn(OrgTime.clock(_left, language)),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        onPressed: _sending ? null : _resend,
        child: Text(l10n.authOtpResend),
      ),
    );
  }
}
