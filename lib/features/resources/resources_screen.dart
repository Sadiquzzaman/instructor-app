import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/resources/staff_resources_screen.dart';

/// A resource shared with the student's classes (`GET /resources/mine`).
@immutable
class Resource {
  const Resource({
    required this.id,
    required this.type,
    required this.title,
    required this.url,
    this.description,
    this.subjectId,
    this.subject,
    this.fileName,
    this.downloadAllowed = true,
    this.isNew = false,
  });

  final String id;

  /// FILE, VIDEO or LINK.
  final String type;
  final String title;

  /// FILE: `/files/:id/content`; LINK: the address.
  final String url;
  final String? description;
  final String? subjectId;
  final String? subject;
  final String? fileName;
  final bool downloadAllowed;
  final bool isNew;

  static Resource? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final s = j['subject'];
    final f = j['file'];
    return Resource(
      id: j['id'] as String,
      type: (j['type'] as String?) ?? 'FILE',
      title: (j['title'] as String?) ?? '',
      url: (j['url'] as String?) ?? '',
      description: j['description'] as String?,
      subjectId: s is Map ? s['id'] as String? : null,
      subject: s is Map ? s['name'] as String? : null,
      fileName: f is Map ? f['name'] as String? : null,
      downloadAllowed: j['download_allowed'] != false,
      isNew: j['is_new'] == true,
    );
  }

  /// Where it opens: a file through the API host, a link as it is.
  Uri get target {
    final u = Uri.tryParse(url);
    if (u != null && u.hasScheme) return u;
    final base = Uri.parse(AppConfig.apiBaseUrl);
    // "/api/v1/files/…" is from the host; "/files/…" is under the API.
    return url.startsWith(base.path)
        ? base.replace(path: url)
        : Uri.parse('${AppConfig.apiBaseUrl}$url');
  }
}

typedef ResourceQuery = ({String q, String? subject, String? type});

final myResourcesProvider = FutureProvider.autoDispose
    .family<List<Resource>, ResourceQuery>((ref, query) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/resources/mine',
            query: {
              'q': query.q.trim().isEmpty ? null : query.q.trim(),
              'subject_id': query.subject,
              'type': query.type,
            },
          );
      final p = r.payload;
      return [
        if (p is List)
          for (final i in p) ?Resource.fromJson(i),
      ];
    }, retry: (retryCount, error) => null);

/// The web's /resources for a student: files and links shared with their
/// classes; search, by subject and type; opening is recorded first (the
/// "New" tag goes, the teacher sees it), then it opens.
class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  String _q = '';
  String? _subject;
  String? _type;
  Timer? _typing;
  final _opened = <String>{};

  /// Subjects seen so far (the filter keeps them while filtering).
  final _subjects = <String, String>{};

  ResourceQuery get _query => (q: _q, subject: _subject, type: _type);

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  Future<void> _open(Resource r) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(apiClientProvider).post('/resources/${r.id}/open');
      if (mounted) setState(() => _opened.add(r.id));
      final ok = await ref.read(openLinkProvider)(r.target);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appFileOpenFailed)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    // Staff keep a library and share it (the web's StaffLibrary).
    if (ref.watch(sessionProvider)?.role != 'STUDENT') {
      return const StaffResourcesScreen();
    }
    final items = ref.watch(myResourcesProvider(_query));
    for (final r in items.value ?? const <Resource>[]) {
      if (r.subjectId != null) _subjects[r.subjectId!] = r.subject ?? '';
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.resourcesTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.resourcesStudentDescription,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('resource-search'),
              decoration: InputDecoration(
                labelText: l10n.resourcesSearch,
                hintText: l10n.resourcesSearchPlaceholder,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) {
                _typing?.cancel();
                _typing = Timer(
                  const Duration(milliseconds: 400),
                  () => setState(() => _q = v),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _subject,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.resourcesSubject,
                    ),
                    items: [
                      DropdownMenuItem(child: Text(l10n.resourcesAllSubjects)),
                      for (final MapEntry(:key, :value) in _subjects.entries)
                        DropdownMenuItem(value: key, child: Text(value)),
                    ],
                    onChanged: (v) => setState(() => _subject = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: const Key('resource-type'),
                    initialValue: _type,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.resourcesType),
                    items: [
                      DropdownMenuItem(child: Text(l10n.resourcesAllTypes)),
                      DropdownMenuItem(
                        value: 'FILE',
                        child: Text(l10n.resourcesTypesFILE),
                      ),
                      DropdownMenuItem(
                        value: 'LINK',
                        child: Text(l10n.resourcesTypesLINK),
                      ),
                    ],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...items.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(semanticsLabel: l10n.resourcesTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: e is ApiException && e.statusCode == 403
                        ? l10n.resourcesNotAvailable
                        : l10n.resourcesLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(myResourcesProvider(_query)),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 260,
                        child: EmptyView(
                          icon: Icons.folder_open_outlined,
                          title: l10n.resourcesStudentEmpty,
                          message: l10n.resourcesStudentEmptyHint,
                        ),
                      ),
                    ]
                  : [
                      for (final r in list) ...[
                        AppCard(
                          key: Key('resource-${r.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    r.type == 'LINK'
                                        ? Icons.link
                                        : Icons.insert_drive_file_outlined,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      r.title,
                                      style: text.titleSmall,
                                    ),
                                  ),
                                  if (r.isNew && !_opened.contains(r.id))
                                    StatusPill(
                                      label: l10n.resourcesNew,
                                      tone: StatusTone.success,
                                    ),
                                ],
                              ),
                              if (r.description != null &&
                                  r.description!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.xs,
                                  ),
                                  child: Text(
                                    r.description!,
                                    style: text.bodyMedium,
                                  ),
                                ),
                              Text(
                                [r.subject, r.fileName]
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                style: text.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                              if (r.type == 'FILE' && !r.downloadAllowed)
                                Text(
                                  l10n.resourcesViewOnlyNote,
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: AppButton(
                                  label: l10n.resourcesOpen,
                                  onPressed: () => _open(r),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
