import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/features/shell/menu/menu_filter.dart';
import 'package:instructor_app/features/shell/menu/menu_item.dart';
import 'package:instructor_app/features/shell/menu/menu_items.g.dart';

import '../../../tool/import_menu.dart';

List<String> _routes(List<MenuSection> sections) => [
  for (final s in sections)
    for (final e in s.entries)
      if (e.item != null) e.item!.route else ...e.items.map((i) => i.route),
];

const _student = MenuViewer(
  role: 'STUDENT',
  sessionMode: 'organization',
  workspaceType: 'ACADEMIC',
  memberRole: 'STUDENT',
);
const _owner = MenuViewer(
  role: 'TEACHER',
  sessionMode: 'organization',
  workspaceType: 'ACADEMIC',
  memberRole: 'OWNER',
);
const _teacher = MenuViewer(
  role: 'TEACHER',
  sessionMode: 'organization',
  workspaceType: 'ACADEMIC',
  memberRole: 'TEACHER',
);

void main() {
  test('menu_items.g.dart matches tool/sidebarList.tsx '
      '(run `dart run tool/import_menu.dart`)', () {
    final web = parseMenu(File('tool/sidebarList.tsx').readAsStringSync());
    expect(webMenu.length, web.length);
    for (final (i, item) in webMenu.indexed) {
      final w = web[i];
      expect(item.route, w.str('route'), reason: '#$i');
      expect(item.label, w.str('label'), reason: '#$i');
      expect(item.category, w.str('category'), reason: '#$i');
      expect(item.roles, w.list('role')!.toSet(), reason: item.route);
      expect(
        item.memberRoles,
        w.list('memberRoles')?.toSet(),
        reason: item.route,
      );
      expect(item.features, w.list('feature'), reason: item.route);
      expect(
        item.workspaces,
        w.list('workspaces')?.toSet(),
        reason: item.route,
      );
    }
  });

  group('visibleMenu (the web\'s Sidebar rules)', () {
    final allOn = {
      for (final i in webMenu)
        for (final f in i.features ?? const <String>[]) f: true,
    };

    test('a student in an organisation gets Platform and System', () {
      final menu = visibleMenu(
        webMenu,
        _student,
        order: navItemOrder,
        features: allOn,
      );
      expect(menu.map((s) => s.category), ['Platform', 'System']);
      expect(_routes(menu), containsAll(['/today', '/account']));
      expect(_routes(menu), isNot(contains('/organization')));
    });

    test('an owner gets Organization pages a teacher does not', () {
      final owner = _routes(
        visibleMenu(webMenu, _owner, order: navItemOrder, features: allOn),
      );
      final teacher = _routes(
        visibleMenu(webMenu, _teacher, order: navItemOrder, features: allOn),
      );
      expect(
        owner.toSet().difference(teacher.toSet()),
        contains('/attendance-settings'),
      );
      expect(teacher, isNot(contains('/attendance-settings')));
    });

    test('IELTS workspaces never see Academic-only pages', () {
      const ielts = MenuViewer(
        role: 'STUDENT',
        sessionMode: 'organization',
        workspaceType: 'IELTS',
        memberRole: 'STUDENT',
      );
      final routes = _routes(
        visibleMenu(webMenu, ielts, order: navItemOrder, features: allOn),
      );
      final academicOnly = webMenu
          .where(
            (i) =>
                i.workspaces?.length == 1 && i.workspaces!.contains('ACADEMIC'),
          )
          .map((i) => i.route);
      expect(routes.toSet().intersection(academicOnly.toSet()), isEmpty);
    });

    test('personal-workspace-only pages need personal teaching', () {
      const off = MenuViewer(
        role: 'TEACHER',
        sessionMode: 'individual',
        workspaceType: 'ACADEMIC',
      );
      const on = MenuViewer(
        role: 'TEACHER',
        sessionMode: 'individual',
        workspaceType: 'ACADEMIC',
        personalTeacherEnabled: true,
      );
      final personalOnly = webMenu
          .where((i) => i.personalWorkspaceOnly && i.category == 'Platform')
          .map((i) => i.route)
          .toSet();
      expect(
        _routes(visibleMenu(webMenu, off, order: navItemOrder, features: allOn))
            .toSet()
            .intersection(personalOnly),
        isEmpty,
      );
      expect(
        _routes(visibleMenu(webMenu, on, order: navItemOrder, features: allOn))
            .toSet()
            .intersection(personalOnly),
        isNotEmpty,
      );
    });

    test('plan features: off hides, loading hides, unknown shows', () {
      final attendanceOff = {...allOn, 'attendance': false};
      bool hasMyAttendance(Map<String, bool>? f, {bool loading = false}) =>
          _routes(
            visibleMenu(
              webMenu,
              _student,
              order: navItemOrder,
              features: f,
              featuresLoading: loading,
            ),
          ).contains('/my-attendance');
      expect(hasMyAttendance(allOn), isTrue);
      expect(hasMyAttendance(attendanceOff), isFalse);
      expect(hasMyAttendance(null, loading: true), isFalse);
      expect(hasMyAttendance(null), isTrue);
    });

    test('platform admins: the Admin section stays on the web', () {
      const admin = MenuViewer(
        role: 'ADMIN',
        sessionMode: 'individual',
        workspaceType: 'ACADEMIC',
      );
      final menu = visibleMenu(
        webMenu,
        admin,
        order: navItemOrder,
        features: allOn,
      );
      expect(menu.map((s) => s.category), isNot(contains('Admin')));
      expect(_routes(menu).where((r) => r.startsWith('/admin')), isEmpty);
    });

    test('a group appears once, where its first page is', () {
      final menu = visibleMenu(
        webMenu,
        _owner,
        order: navItemOrder,
        features: allOn,
      );
      for (final s in menu) {
        final groups = s.entries.map((e) => e.group).nonNulls.toList();
        expect(groups.toSet().length, groups.length, reason: s.category);
      }
    });
  });

  test('the web order: Today first, a group of one is a plain link', () {
    final allOn = {
      for (final i in webMenu)
        for (final f in i.features ?? const <String>[]) f: true,
    };
    final menu = visibleMenu(
      webMenu,
      _owner,
      order: navItemOrder,
      features: allOn,
    );
    final first = menu.first.entries.first;
    expect(first.item?.route, '/today');
    for (final s in menu) {
      for (final e in s.entries) {
        if (e.group != null) {
          expect(e.items.length, greaterThan(1), reason: e.group);
        }
      }
    }
    expect(navItemOrder.first, 'today');
  });

  test('IELTS-only pages are recognised', () {
    final ielts = webMenu.where((i) => i.ieltsOnly).toList();
    expect(ielts, isNotEmpty);
    expect(ielts.every((i) => i.workspaces!.single == 'IELTS'), isTrue);
    const both = MenuItem(
      category: 'Platform',
      label: 'x',
      route: '/x',
      roles: {'STUDENT'},
      icon: 'dashboard',
    );
    expect(both.ieltsOnly, isFalse);
  });
}
