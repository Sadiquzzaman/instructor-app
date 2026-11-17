import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/features/shell/screens/home_screen.dart';
import 'package:instructor_app/features/shell/screens/not_yet_screen.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

FakeApi _api({
  Map<String, bool> features = const {
    'attendance': true,
    'homework': true,
    'calendar': true,
    'performance': true,
    'chat': true,
    'resources': true,
    'ielts': true,
  },
}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': features}))
  ..on('GET /workspace/level-labels', (_) => ok({'preset': 'CLASS_SECTION'}));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(DrawerButton));
  await tester.pumpAndSettle();
}

Session _ielts() => Session.fromPayload(
  sessionPayload()
    ..['workspace_type'] = 'IELTS'
    ..['organization'] = {
      'id': 'org-2',
      'name': 'Bright Path IELTS',
      'role': 'STUDENT',
      'status': 'approved',
      'workspace_type': 'IELTS',
    },
);

void main() {
  testWidgets('phone: the drawer has the student\'s menu; a page not built '
      'yet says to use the website', (tester) async {
    await pumpInstructorApp(tester, api: _api(), session: testSession());
    expect(find.byType(HomeScreen), findsOneWidget);
    // The workspace in the top bar.
    expect(find.text('Demo School'), findsOneWidget);

    await _openMenu(tester);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byType(NotYetScreen), findsOneWidget);
    expect(
      find.text(
        'This page is not in the app yet. Please use the website for it for now.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a feature the plan lacks is not in the menu', (tester) async {
    await pumpInstructorApp(
      tester,
      api: _api(features: {'attendance': false}),
      session: testSession(),
    );
    await _openMenu(tester);
    expect(find.text('My attendance'), findsNothing);
  });

  testWidgets('IELTS pages say "use the website for IELTS"', (tester) async {
    await pumpInstructorApp(tester, api: _api(), session: _ielts());
    await _openMenu(tester);
    final ieltsLink = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('menu-/ielts'),
    );
    expect(ieltsLink, findsWidgets);
    await tester.tap(ieltsLink.first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'IELTS pages are not in the app yet. Please use the website for IELTS for now.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tablet: the menu stays open, no drawer button', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpInstructorApp(tester, api: _api(), session: testSession());
    expect(find.byType(DrawerButton), findsNothing);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('the shell fits a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpInstructorApp(
      tester,
      api: _api(),
      session: testSession(),
      prefs: {'language': 'bn'},
    );
    await _openMenu(tester);
    expect(tester.takeException(), isNull);
  });

  group('common API errors', () {
    Future<void> trigger(
      WidgetTester tester,
      Session session,
      ApiException error,
    ) async {
      await pumpInstructorApp(tester, api: _api(), session: session);
      final context = tester.element(find.byType(HomeScreen));
      // Not awaited: the locked-feature sheet's future ends only when closed.
      unawaited(handleCommonApiError(context, error, session: session));
      await tester.pumpAndSettle();
    }

    const locked = ApiException(
      kind: ApiErrorKind.forbidden,
      statusCode: 403,
      code: 'FEATURE_NOT_IN_PLAN',
      feature: 'chat',
    );

    testWidgets('locked feature, member: ask your admin, no upgrade', (
      tester,
    ) async {
      await trigger(tester, testSession(), locked);
      expect(find.text('Not in your plan'), findsOneWidget);
      expect(find.text('Ask your admin to unlock this.'), findsOneWidget);
      expect(find.text('Upgrade'), findsNothing);
    });

    testWidgets('locked feature, owner: one upgrade away, still no button', (
      tester,
    ) async {
      final owner = Session.fromPayload(
        sessionPayload()
          ..['organization'] = {
            'id': 'org-1',
            'name': 'Demo School',
            'role': 'OWNER',
            'status': 'approved',
          },
      );
      await trigger(tester, owner, locked);
      expect(
        find.text('This feature is one upgrade away — unlock it today!'),
        findsOneWidget,
      );
      expect(find.text('Upgrade'), findsNothing);
    });

    testWidgets('branch managers get a short message', (tester) async {
      await trigger(
        tester,
        testSession(),
        const ApiException(
          kind: ApiErrorKind.forbidden,
          code: 'NOT_FOR_BRANCH_MANAGERS',
        ),
      );
      expect(
        find.text('This is not available to branch managers yet.'),
        findsOneWidget,
      );
    });
  });
}
