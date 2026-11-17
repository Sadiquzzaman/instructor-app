import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/level_labels.dart';
import 'package:instructor_app/features/shell/screens/home_screen.dart';
import 'package:instructor_app/features/workspace/data/workspace_repository.dart';
import 'package:instructor_app/features/workspace/screens/workspace_gate.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

Map<String, Object?> _ctx({
  required String type,
  required String key,
  required String label,
  String? org,
  String status = 'approved',
  bool actionable = true,
  String role = 'Student',
}) => {
  'type': type,
  'key': key,
  'label': label,
  'role_label': role,
  'organization_id': ?org,
  'organization_status': type == 'organization' ? status : null,
  'actionable': actionable,
};

final _demo = _ctx(
  type: 'organization',
  key: 'org:org-1',
  label: 'Demo School',
  org: 'org-1',
);
final _ielts = _ctx(
  type: 'organization',
  key: 'org:org-2',
  label: 'Bright Path IELTS',
  org: 'org-2',
);
final _mine = _ctx(
  type: 'personal_teacher',
  key: 'personal',
  label: 'My Teaching',
  role: 'Teacher',
);

/// Signed in with several workspaces and none chosen.
Session _noWorkspace() => Session.fromPayload(
  sessionPayload(organizationId: null)
    ..['context_type'] = 'individual'
    ..['session_mode'] = 'individual',
);

void main() {
  group('WorkspaceContext', () {
    test('reads the API answer and knows the current one', () {
      final c = WorkspaceContext.fromJson(_demo)!;
      expect(c.label, 'Demo School');
      expect(c.roleLabel, 'Student');
      expect(c.isCurrent(testSession()), isTrue);
      expect(c.isCurrent(testSession(organizationId: 'org-2')), isFalse);
      expect(WorkspaceContext.fromJson({'label': 'x'}), isNull);
    });
  });

  testWidgets('several workspaces and none chosen: the picker, then home', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) => ok([_demo, _ielts]))
      ..on(
        'POST /auth/select-context',
        (_) => ok(sessionPayload(organizationId: 'org-2', access: 'access-2')),
      )
      ..on(
        'GET /workspace/level-labels',
        (_) => ok({'preset': 'COURSE_BATCH'}),
      );
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: _noWorkspace(),
    );

    expect(find.byType(WorkspacePickerScreen), findsOneWidget);
    expect(find.text('Your workspaces'), findsOneWidget);
    // "[[classes]]" in the intro is filled in.
    expect(find.textContaining('classes and tests'), findsOneWidget);

    await tester.tap(find.text('Bright Path IELTS'));
    await tester.pumpAndSettle();

    expect(api.to('POST /auth/select-context').single.body, {
      'type': 'organization',
      'organization_id': 'org-2',
    });
    final session = container.read(sessionProvider)!;
    expect(session.organizationId, 'org-2');
    expect(find.byType(HomeScreen), findsOneWidget);
    // The new workspace's requests carry its organisation.
    final labels = api.to('GET /workspace/level-labels').last;
    expect(labels.organizationHeader, 'org-2');
    expect(labels.bearer, 'access-2');
    expect(container.read(levelLabelsProvider), LevelLabels.courseBatch);
  });

  testWidgets('with one workspace (or none) there is no picker', (
    tester,
  ) async {
    final api = FakeApi()..on('GET /auth/contexts', (_) => ok([_demo]));
    await pumpInstructorApp(tester, api: api, session: _noWorkspace());
    expect(find.byType(WorkspacePickerScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('pending organisations say so', (tester) async {
    final api = FakeApi()
      ..on(
        'GET /auth/contexts',
        (_) => ok([
          _demo,
          _ctx(
            type: 'organization',
            key: 'org:org-3',
            label: 'New School',
            org: 'org-3',
            status: 'pending',
            role: 'Owner',
          ),
        ]),
      );
    await pumpInstructorApp(tester, api: api, session: _noWorkspace());
    expect(find.text('Pending approval'), findsOneWidget);
  });

  testWidgets('switcher: the sheet, another workspace, its language', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) => ok([_demo, _mine]))
      ..on(
        'POST /auth/select-context',
        (_) => ok(
          sessionPayload(organizationId: null, access: 'access-2')
            ..['locale'] = null,
        ),
      )
      ..on(
        'GET /workspace/level-labels',
        (_) => ok({'preset': 'CLASS_SECTION'}),
      );
    final session = Session.fromPayload(sessionPayload()..['locale'] = null);
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: session,
      prefs: {LanguageController.prefsKey: 'en'},
    );

    // The switcher shows the current workspace.
    expect(find.text('Demo School'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workspace-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('My Teaching').last);
    await tester.pumpAndSettle();

    expect(api.to('POST /auth/select-context').single.body, {
      'type': 'personal_teacher',
    });
    expect(container.read(sessionProvider)!.contextType, 'personal_teacher');
    expect(container.read(workspaceKeyProvider), 'user-1/personal_teacher');
    expect(find.text('Workspaces'), findsNothing);
  });

  testWidgets('the organisation\'s language applies when the person has none', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) => ok([_demo, _ielts]))
      ..on(
        'POST /auth/select-context',
        (_) => ok(sessionPayload(organizationId: 'org-2')..['locale'] = null),
      );
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: _noWorkspace(),
      prefs: {LanguageController.prefsKey: 'en'},
    );
    await tester.tap(find.text('Bright Path IELTS'));
    await tester.pumpAndSettle();
    // sessionPayload's organisation default is Bangla.
    expect(container.read(languageProvider).languageCode, 'bn');
  });

  testWidgets('a failed switch says so and stays', (tester) async {
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) => ok([_demo, _ielts]))
      ..on('POST /auth/select-context', (_) => apiError(403, message: 'No'));
    await pumpInstructorApp(tester, api: api, session: _noWorkspace());
    await tester.tap(find.text('Demo School'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byType(WorkspacePickerScreen), findsOneWidget);
  });

  testWidgets('the list cannot load: try again', (tester) async {
    var calls = 0;
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) {
        calls++;
        return calls == 1 ? apiError(502) : ok([_demo, _ielts]);
      });
    await pumpInstructorApp(tester, api: api, session: _noWorkspace());
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspacePickerScreen), findsOneWidget);
  });

  testWidgets('sign out drops the workspace\'s labels', (tester) async {
    final api = FakeApi()
      ..on('GET /auth/contexts', (_) => ok([_demo]))
      ..on('GET /workspace/level-labels', (_) => ok({'preset': 'COURSE_BATCH'}))
      ..on('POST /auth/logout', (_) => ok(null));
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
    );
    container.read(
      levelLabelsProvider,
    ); // start loading (nothing shows them yet)
    await tester.pumpAndSettle();
    expect(container.read(levelLabelsProvider), LevelLabels.courseBatch);
    await signOutFromMenu(tester);
    await tester.pumpAndSettle();
    expect(container.read(workspaceKeyProvider), isNull);
    expect(container.read(levelLabelsProvider), LevelLabels.defaults);
  });
}
