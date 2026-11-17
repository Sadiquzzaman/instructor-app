import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_theme.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';

Widget _wrap(Widget child, {bool bangla = false}) => MaterialApp(
  theme: AppTheme.light(bangla: bangla),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AppButton', () {
    testWidgets('calls onPressed when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Sign in', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Sign in'));
      expect(taps, 1);
    });

    testWidgets('while loading: a spinner, no label, taps ignored', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          AppButton(label: 'Sign in', onPressed: () => taps++, loading: true),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      expect(taps, 0);
      // It keeps its brand colour, so the white spinner stays visible.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
      // Screen readers still hear what the button is.
      expect(find.bySemanticsLabel('Sign in'), findsOneWidget);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppButton(label: 'Save', onPressed: null)),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('danger buttons are red', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppButton(
            label: 'Remove',
            onPressed: () {},
            variant: AppButtonVariant.danger,
          ),
        ),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final background = button.style!.backgroundColor!.resolve({});
      expect(background, AppColors.light.danger);
    });

    testWidgets('meets the 44 px tap target', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'OK', onPressed: () {})));
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });
  });

  group('AppTextField', () {
    testWidgets('shows its label and error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppTextField(label: 'Email or phone', errorText: 'Required'),
        ),
      );
      expect(find.text('Email or phone'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('a password field hides the text and can show it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppTextField(
            label: 'Password',
            obscure: true,
            showLabel: 'Show password',
            hideLabel: 'Hide password',
          ),
        ),
      );
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });
  });

  testWidgets('AppCard is tappable when given onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(AppCard(onTap: () => taps++, child: const Text('Class 6-A'))),
    );
    await tester.tap(find.text('Class 6-A'));
    expect(taps, 1);
  });

  testWidgets('StatusPill uses the tone colours', (tester) async {
    await tester.pumpWidget(
      _wrap(const StatusPill(label: 'Late', tone: StatusTone.warning)),
    );
    final text = tester.widget<Text>(find.text('Late'));
    expect(text.style!.color, AppColors.light.warning);
  });

  group('state views', () {
    testWidgets('ErrorView retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          ErrorView(
            title: 'Could not load',
            retryLabel: 'Try again',
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('EmptyView shows its action only when given one', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const EmptyView(title: 'Nothing yet')));
      expect(find.text('Nothing yet'), findsOneWidget);
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('LoadingView is announced', (tester) async {
      await tester.pumpWidget(
        _wrap(const LoadingView(semanticsLabel: 'Loading')),
      );
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
  });

  testWidgets('Bangla text renders in the Bangla theme on a 360 px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        AppButton(label: 'লগ ইন', onPressed: () {}, expand: true),
        bangla: true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('লগ ইন'), findsOneWidget);
  });
}
