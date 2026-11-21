import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/tests/data/exam_to_draft.dart';
import 'package:instructor_app/features/tests/screens/create_test_screen.dart';

/// A saved test with its questions and answers, to edit (`GET /exams/:id`).
final examForEditProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/exams/$id');
      final p = r.payload;
      return p is Map ? p.cast<String, Object?>() : null;
    }, retry: (retryCount, error) => null);

/// The web's /tests/create?examId=…: the test opens in the same steps and
/// is saved with `PUT /exams/:id`. A test with anything the app can't edit
/// without losing it (formatting, maths, media, IELTS) is edited on the
/// website instead (Stage 4 plan §7.1 A).
class EditTestScreen extends ConsumerWidget {
  const EditTestScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref
        .watch(examForEditProvider(id))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.createTestTitle),
          error: (e, _) =>
              e is ApiException && (e.statusCode == 404 || e.statusCode == 403)
              ? EmptyView(
                  icon: Icons.quiz_outlined,
                  title: l10n.testsDetailsNotFound,
                  message: l10n.testsDetailsNotFoundDetail,
                )
              : ErrorView(
                  title: l10n.testsResultsFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(examForEditProvider(id)),
                ),
          data: (exam) {
            final draft = exam == null ? null : draftFromExam(exam);
            if (draft == null) {
              return EmptyView(
                key: const Key('edit-on-website'),
                icon: Icons.open_in_new,
                title: l10n.appTestEditOnWebsiteTitle,
                message: l10n.appTestEditOnWebsiteBody,
                actionLabel: l10n.appTestEditOnWebsite,
                onAction: () => ref.read(openLinkProvider)(
                  Uri.parse(
                    '${AppConfig.webBaseUrl}/tests/create'
                    '?examId=${Uri.encodeQueryComponent(id)}',
                  ),
                ),
              );
            }
            return CreateTestScreen(editId: id, initial: draft);
          },
        );
  }
}
