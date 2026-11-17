import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/shell/menu/menu_item.dart';
import 'package:instructor_app/features/shell/menu/menu_items.g.dart';

/// A menu page that is not in the app yet: its name and "Please use the
/// website for it for now" (IELTS pages: "… for IELTS for now", owner's
/// decision 6). Each stage replaces these with real screens. No link to the
/// website: some pages there sell plans (CLAUDE.md "Payments").
class NotYetScreen extends ConsumerWidget {
  const NotYetScreen({required this.item, super.key});

  final MenuItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return EmptyView(
      icon: item.ieltsOnly ? Icons.translate : Icons.public,
      title: ref.levels(context, menuLabel(l10n, item.label)),
      message: item.ieltsOnly ? l10n.appNotYetIelts : l10n.appNotYetBody,
    );
  }
}
