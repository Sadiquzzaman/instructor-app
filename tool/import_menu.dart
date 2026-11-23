// Generates lib/features/shell/menu/menu_items.g.dart from the web's side menu
// (tes-taker frontend/utils/sidebarList.tsx: the items and who sees them;
// sidebarGroups.ts: NAV_ITEM_ORDER, the order they are shown in), so the app
// shows the same pages to the same people, in the same order (CLAUDE.md,
// STAGE-0-PLAN.md §5).
//
//   dart run tool/import_menu.dart                          # regenerate from the copies in tool/
//   dart run tool/import_menu.dart <tes-taker/frontend/utils> # copy newer files first
//
// Every label, group and category must exist in lib/l10n/app_en.arb (the `nav`
// namespace); the tool fails otherwise, so the menu never shows a raw key.
// test/features/shell/menu_test.dart fails when the generated file is stale.
import 'dart:convert';
import 'dart:io';

const _list = 'tool/sidebarList.tsx';
const _groups = 'tool/sidebarGroups.ts';
const _output = 'lib/features/shell/menu/menu_items.g.dart';

void main(List<String> args) {
  if (args.isNotEmpty) {
    File('${args.first}/sidebarList.tsx').copySync(_list);
    File('${args.first}/sidebarGroups.ts').copySync(_groups);
    stdout.writeln(
      'Copied sidebarList.tsx and sidebarGroups.ts from ${args.first}',
    );
  }
  final arb = jsonDecode(
    File('lib/l10n/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  File(_output).writeAsStringSync(
    generateMenu(
      File(_list).readAsStringSync(),
      arb.keys.toSet(),
      order: parseOrder(File(_groups).readAsStringSync()),
    ),
  );
  final format = Process.runSync('dart', ['format', _output], runInShell: true);
  if (format.exitCode != 0) {
    stderr.writeln(format.stderr);
    exit(format.exitCode);
  }
  stdout.writeln('Wrote $_output');
}

/// One menu entry as read from the TSX.
class WebMenuItem {
  WebMenuItem(this.fields);
  final Map<String, Object> fields;

  String str(String k) => fields[k]! as String;
  String? opt(String k) => fields[k] as String?;
  List<String>? list(String k) => fields[k] as List<String>?;
  bool flag(String k) => fields[k] == true;
}

/// The objects of `const sidebarList: SideBarList[] = [ … ];`.
List<WebMenuItem> parseMenu(String tsx) {
  final declaration = tsx.indexOf('const sidebarList');
  final equals = declaration < 0 ? -1 : tsx.indexOf('=', declaration);
  final start = equals < 0 ? -1 : tsx.indexOf('[', equals);
  if (start < 0) throw const FormatException('No sidebarList array');
  final objects = <String>[];
  var depth = 0;
  var objectStart = -1;
  for (var i = start + 1; i < tsx.length; i++) {
    final c = tsx[i];
    if (c == '{') {
      if (depth == 0) objectStart = i;
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) objects.add(tsx.substring(objectStart, i + 1));
    } else if (c == ']' && depth == 0) {
      break;
    }
  }

  String? str(String o, String f) =>
      RegExp('\\b$f:\\s*"([^"]*)"').firstMatch(o)?[1];
  List<String>? list(String o, String f) {
    final m = RegExp('\\b$f:\\s*\\[([^\\]]*)\\]').firstMatch(o);
    if (m == null) return null;
    return RegExp('"([^"]*)"').allMatches(m[1]!).map((x) => x[1]!).toList();
  }

  return [
    for (final o in objects)
      WebMenuItem({
        'category': ?str(o, 'category'),
        'label': ?str(o, 'label'),
        'route': ?str(o, 'route'),
        'group': ?str(o, 'group'),
        'role': ?list(o, 'role'),
        'memberRoles': ?list(o, 'memberRoles'),
        'workspaces': ?list(o, 'workspaces'),
        'feature':
            ?(list(o, 'feature') ??
            (str(o, 'feature') == null ? null : [str(o, 'feature')!])),
        'personalWorkspaceOnly': RegExp(r'\bpersonalWorkspaceOnly:\s*true')
            .hasMatch(o),
        'setup': RegExp(r'\bsetup:\s*true').hasMatch(o),
        'icon': _icon(RegExp(r'<Sidebar(\w+?)IconSVG').firstMatch(o)?[1]),
      }),
  ];
}

/// NAV_ITEM_ORDER from sidebarGroups.ts: the labels in menu order.
List<String> parseOrder(String ts) {
  final m = RegExp(r'NAV_ITEM_ORDER[^=]*=\s*\[([^\]]*)\]').firstMatch(ts);
  if (m == null) throw const FormatException('No NAV_ITEM_ORDER');
  return RegExp('"([^"]*)"').allMatches(m[1]!).map((x) => x[1]!).toList();
}

/// `Dashboard` (from SidebarDashboardIconSVG) → `dashboard`.
String _icon(String? name) =>
    name == null ? 'dashboard' : name[0].toLowerCase() + name.substring(1);

/// `nav.group.academics` → `navGroupAcademics` (the import tool's naming).
String _key(List<String> path) {
  final words = path.expand((p) => p.split(RegExp('[-_]'))).toList();
  return words.first +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

String _set(List<String>? xs) =>
    xs == null ? 'null' : '{${xs.map((x) => "'$x'").join(', ')}}';

String generateMenu(
  String tsx,
  Set<String> arbKeys, {
  required List<String> order,
}) {
  final items = parseMenu(tsx);
  for (final i in items) {
    for (final f in ['category', 'label', 'route', 'role']) {
      if (!i.fields.containsKey(f)) {
        throw FormatException('A menu item has no "$f": ${i.fields}');
      }
    }
  }
  void need(String key, String what) {
    if (!arbKeys.contains(key)) {
      throw FormatException(
        '$what has no message "$key": import the web\'s nav wording first',
      );
    }
  }

  final labels = {for (final i in items) i.str('label')};
  final groups = {for (final i in items) ?i.opt('group')};
  final categories = {for (final i in items) i.str('category')};
  for (final l in labels) {
    need(_key(['nav', l]), 'Label "$l"');
  }
  for (final g in groups) {
    need(_key(['nav', 'group', g]), 'Group "$g"');
  }
  for (final c in categories) {
    need(_key(['nav', 'category', c]), 'Category "$c"');
  }

  final b = StringBuffer()
    ..writeln('// GENERATED by tool/import_menu.dart from tool/sidebarList.tsx')
    ..writeln(
      '// (tes-taker frontend/utils/sidebarList.tsx). Do not edit by hand.',
    )
    ..writeln()
    ..writeln(
      "import 'package:instructor_app/features/shell/menu/menu_item.dart';",
    )
    ..writeln(
      "import 'package:instructor_app/l10n/generated/app_localizations.dart';",
    )
    ..writeln()
    ..writeln("/// The web's side menu, in its order.")
    ..writeln('const webMenu = <MenuItem>[');
  for (final i in items) {
    b
      ..writeln('  MenuItem(')
      ..writeln("    category: '${i.str('category')}',")
      ..writeln("    label: '${i.str('label')}',")
      ..writeln("    route: '${i.str('route')}',")
      ..writeln('    roles: ${_set(i.list('role'))},')
      ..writeln("    icon: '${i.str('icon')}',");
    if (i.opt('group') != null) b.writeln("    group: '${i.opt('group')}',");
    if (i.list('memberRoles') != null) {
      b.writeln('    memberRoles: ${_set(i.list('memberRoles'))},');
    }
    if (i.flag('personalWorkspaceOnly')) {
      b.writeln('    personalWorkspaceOnly: true,');
    }
    if (i.list('workspaces') != null) {
      b.writeln('    workspaces: ${_set(i.list('workspaces'))},');
    }
    if (i.list('feature') != null) {
      b.writeln(
        "    features: [${i.list('feature')!.map((f) => "'$f'").join(', ')}],",
      );
    }
    if (i.flag('setup')) b.writeln('    setup: true,');
    b.writeln('  ),');
  }
  b
    ..writeln('];')
    ..writeln()
    ..writeln(
      "/// The web's NAV_ITEM_ORDER (sidebarGroups.ts): labels in menu order;",
    )
    ..writeln('/// labels not listed go last.')
    ..writeln('const navItemOrder = <String>[')
    ..writeAll(order.map((l) => "  '$l',\n"))
    ..writeln('];')
    ..writeln()
    ..writeln('/// A menu item\'s name in the current language.')
    ..writeln(
      'String menuLabel(AppLocalizations l10n, String label) => switch (label) {',
    );
  for (final l in labels) {
    b.writeln("  '$l' => l10n.${_key(['nav', l])},");
  }
  b
    ..writeln('  _ => label,')
    ..writeln('};')
    ..writeln()
    ..writeln('/// A group\'s name in the current language.')
    ..writeln(
      'String menuGroupLabel(AppLocalizations l10n, String group) => switch (group) {',
    );
  for (final g in groups) {
    b.writeln("  '$g' => l10n.${_key(['nav', 'group', g])},");
  }
  b
    ..writeln('  _ => group,')
    ..writeln('};')
    ..writeln()
    ..writeln('/// A category\'s name in the current language.')
    ..writeln(
      'String menuCategoryLabel(AppLocalizations l10n, String category) => switch (category) {',
    );
  for (final c in categories) {
    b.writeln("  '$c' => l10n.${_key(['nav', 'category', c])},");
  }
  b
    ..writeln('  _ => category,')
    ..writeln('};');
  return b.toString();
}
