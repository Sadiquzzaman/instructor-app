import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/plan/data/feature_catalog.dart';
import 'package:instructor_app/features/plan/data/feature_names.g.dart';
import 'package:instructor_app/features/plan/screens/more_features_screen.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();

/// A teacher who owns (or, with [memberRole], belongs to) the workspace.
Session _teacher({String memberRole = 'OWNER'}) {
  final p = sessionPayload();
  return Session.fromPayload({
    ...p,
    'role': 'TEACHER',
    'organization': <String, dynamic>{
      ...p['organization'] as Map<String, dynamic>,
      'role': memberRole,
    },
  });
}

const _catalog = [
  {
    'key': 'allow_graded_questions',
    'group': 'Question',
    'label': 'Graded questions',
  },
  {'key': 'allow_model_tests', 'group': 'Question', 'label': 'Model tests'},
  {
    'key': 'graphical_analytics',
    'group': 'Analytics',
    'label': 'Graphical analytics',
  },
  {'key': 'brand_new_thing', 'group': 'Performance', 'label': 'Brand new'},
];

FakeApi _api({FakeHandler? catalog, FakeHandler? request}) => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'plan': {'name': 'Starter'},
      'features': {'allow_graded_questions': true, 'allow_model_tests': false},
      'limits': <String, num>{},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on(
    'GET /subscriptions/feature-catalog',
    catalog ?? (_) => ok({'features': _catalog, 'limits': <Object>[]}),
  )
  ..on('POST /me/feature-requests', request ?? (_) => ok({'id': 'fr-1'}));

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeApi api, {
  Session? session,
  String? lang,
}) async {
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: session ?? _teacher(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(AppRoutes.features);
  await tester.pumpAndSettle();
  return c;
}

Finder _inRow(String key, Finder f) =>
    find.descendant(of: find.byKey(Key('feature-$key')), matching: f);

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .descendant(
          of: find.byType(MoreFeaturesScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('every catalog feature and group in the messages has its words', () {
    final web = jsonDecode(
      File('l10n/web/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final features = web['features'] as Map<String, dynamic>;
    final catalog = features['catalog'] as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in catalog.entries) {
      final v = value as Map<String, dynamic>;
      expect(featureName(_en, key), v['name'], reason: key);
      expect(featureDescription(_en, key), v['description'], reason: key);
    }
    for (final MapEntry(:key, :value)
        in (features['groups'] as Map<String, dynamic>).entries) {
      expect(featureGroupName(_en, key), value, reason: key);
    }
    expect(featureName(_en, 'not_a_feature'), isNull);
    expect(featureGroupName(_en, 'Performance'), isNull);
  });

  test('the catalog reads the API answer and keeps its group order', () {
    final features = [for (final f in _catalog) CatalogFeature.fromJson(f)!];
    expect(CatalogFeature.fromJson({'group': 'Question'}), isNull);
    expect(CatalogFeature.fromJson({'key': 'x'})!.label, 'x');
    final groups = groupFeatures(features);
    expect(groups.map((g) => g.$1), ['Question', 'Analytics', 'Performance']);
    expect(groups.first.$2.map((f) => f.key), [
      'allow_graded_questions',
      'allow_model_tests',
    ]);
  });

  testWidgets('an owner sees the plan and what it includes', (tester) async {
    await _open(tester, _api());
    expect(find.text(_en.featuresPagePlanTitle('Starter')), findsOneWidget);
    expect(find.text(_en.featuresGroupsQuestion), findsOneWidget);
    expect(
      _inRow('allow_graded_questions', find.text(_en.featuresPageIncluded)),
      findsOneWidget,
    );
    expect(
      _inRow('allow_graded_questions', find.text(_en.featuresPageRequest)),
      findsNothing,
    );
    expect(
      _inRow('allow_model_tests', find.text(_en.featuresPageLocked)),
      findsOneWidget,
    );
    expect(
      find.text(_en.featuresCatalogAllowModelTestsDescription),
      findsOneWidget,
    );
    // A key the messages do not know yet: the API's own words.
    await _scrollTo(tester, find.byKey(const Key('feature-brand_new_thing')));
    expect(find.text('Brand new'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    // No upgrade button (CLAUDE.md "Payments").
    expect(find.text(_en.featuresPageUpgrade), findsNothing);
  });

  testWidgets('requesting a locked feature sends it with the note', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequest)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        _en.featuresPageRequestTitle(_en.featuresCatalogAllowModelTestsName),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('feature-request-note')),
        matching: find.byType(TextField),
      ),
      '  For the board exams  ',
    );
    await tester.tap(find.text(_en.featuresPageSend));
    await tester.pumpAndSettle();

    final sent = api.to('POST /me/feature-requests').single;
    expect(sent.body, {
      'feature_key': 'allow_model_tests',
      'note': 'For the board exams',
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining(
        _en.featuresPageSent(_en.featuresCatalogAllowModelTestsName),
      ),
      findsOneWidget,
    );
    expect(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequested)),
      findsOneWidget,
    );
    expect(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequest)),
      findsNothing,
    );
  });

  testWidgets('an empty note is left out; cancel sends nothing', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequest)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.featuresPageCancel));
    await tester.pumpAndSettle();
    expect(api.to('POST /me/feature-requests'), isEmpty);

    await tester.tap(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequest)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.featuresPageSend));
    await tester.pumpAndSettle();
    expect(api.to('POST /me/feature-requests').single.body, {
      'feature_key': 'allow_model_tests',
    });
  });

  testWidgets('a refused request says so and keeps the dialog open', (
    tester,
  ) async {
    final api = _api(
      request: (_) => apiError(503, message: 'Service unavailable'),
    );
    await _open(tester, api);
    await tester.tap(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequest)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.featuresPageSend));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_en.uiErrorTitle), findsOneWidget);
    expect(find.textContaining('Service unavailable'), findsNothing);
    expect(
      _inRow('allow_model_tests', find.text(_en.featuresPageRequested)),
      findsNothing,
    );
  });

  testWidgets('a teacher member is told to ask the owner, nothing loads', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, session: _teacher(memberRole: 'TEACHER'));
    expect(find.text(_en.featuresPageMembersTitle), findsOneWidget);
    expect(find.text(_en.featuresPageMembersDetail), findsOneWidget);
    expect(api.to('GET /subscriptions/feature-catalog'), isEmpty);
  });

  testWidgets('a catalog that fails to load can be retried', (tester) async {
    var calls = 0;
    final api = _api(
      catalog: (_) => calls++ == 0
          ? apiError(500)
          : ok({'features': _catalog, 'limits': <Object>[]}),
    );
    await _open(tester, api);
    expect(find.text(_en.featuresPageLoadFailed), findsOneWidget);
    await tester.tap(find.text(_en.uiErrorRetry));
    await tester.pumpAndSettle();
    expect(find.text(_en.featuresPageLoadFailed), findsNothing);
    expect(find.text(_en.featuresPagePlanTitle('Starter')), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, _api(), lang: 'bn');
    expect(find.text(bn.featuresGroupsQuestion), findsOneWidget);
    expect(find.text(bn.featuresCatalogAllowModelTestsName), findsOneWidget);
    expect(find.text(bn.featuresPageRequest), findsWidgets);
  });

  group('the locked-feature sheet', () {
    Future<void> show(WidgetTester tester, {required bool canManage}) async {
      final c = await pumpInstructorApp(
        tester,
        api: _api(),
        session: _teacher(),
      );
      final context = c
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext!;
      // Not awaited: the sheet stays open until it is closed.
      unawaited(showLockedFeature(context, limit: false, canManage: canManage));
      await tester.pumpAndSettle();
    }

    testWidgets('an owner can go to all features', (tester) async {
      await show(tester, canManage: true);
      await tester.tap(find.text(_en.featuresLockedMoreFeatures));
      await tester.pumpAndSettle();
      expect(find.byType(MoreFeaturesScreen), findsOneWidget);
    });

    testWidgets('a member is not offered it', (tester) async {
      await show(tester, canManage: false);
      expect(find.text(_en.featuresLockedMemberMessage), findsOneWidget);
      expect(find.text(_en.featuresLockedMoreFeatures), findsNothing);
    });
  });
}
