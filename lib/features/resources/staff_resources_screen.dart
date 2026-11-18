import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/resources/resources_screen.dart';

/// A resource in the staff library (`GET /resources`).
@immutable
class LibraryResource {
  const LibraryResource({
    required this.resource,
    required this.shares,
    this.folderId,
    this.tags = const [],
    this.archived = false,
    this.canEdit = false,
  });

  /// What students see too (title, link, file, subject, download).
  final Resource resource;
  final List<({String offeringId, String label})> shares;
  final String? folderId;
  final List<String> tags;
  final bool archived;
  final bool canEdit;

  String get id => resource.id;

  /// The upload behind a FILE (`/files/:id/content`).
  String? get fileId =>
      RegExp(r'/files/([^/]+)/content').firstMatch(resource.url)?.group(1);

  static LibraryResource? fromJson(Object? j) {
    final r = Resource.fromJson(j);
    if (r == null || j is! Map) return null;
    return LibraryResource(
      resource: r,
      folderId: j['folder_id'] as String?,
      tags: [
        if (j['tags'] is List)
          for (final t in j['tags'] as List)
            if (t is String) t,
      ],
      archived: j['archived'] == true,
      canEdit: j['can_edit'] == true,
      shares: [
        if (j['shares'] is List)
          for (final s in j['shares'] as List)
            if (s is Map && s['offering_id'] is String)
              (
                offeringId: s['offering_id'] as String,
                label: (s['label'] as String?) ?? '',
              ),
      ],
    );
  }
}

/// A subject class the caller may share with (`GET /resources/subject-classes`).
typedef ShareOption = ({
  String offeringId,
  String label,
  String subjectId,
  String subject,
});

typedef ResourceFolder = ({String id, String name});

typedef LibraryQuery = ({String q, String? folder, bool archived});

final libraryProvider = FutureProvider.autoDispose
    .family<List<LibraryResource>, LibraryQuery>((ref, query) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/resources',
            query: {
              'q': query.q.trim().isEmpty ? null : query.q.trim(),
              'folder_id': query.folder,
              'archived': query.archived ? 'true' : null,
            },
          );
      final p = r.payload;
      return [
        if (p is List)
          for (final i in p) ?LibraryResource.fromJson(i),
      ];
    }, retry: (retryCount, error) => null);

final shareOptionsProvider = FutureProvider.autoDispose<List<ShareOption>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p =
      (await ref.read(apiClientProvider).get('/resources/subject-classes'))
          .payload;
  return [
    if (p is List)
      for (final o in p)
        if (o is Map && o['offering_id'] is String)
          (
            offeringId: o['offering_id'] as String,
            label: (o['label'] as String?) ?? '',
            subjectId:
                (o['subject'] is Map
                    ? (o['subject'] as Map)['id'] as String?
                    : null) ??
                '',
            subject:
                (o['subject'] is Map
                    ? (o['subject'] as Map)['name'] as String?
                    : null) ??
                '',
          ),
  ];
}, retry: (retryCount, error) => null);

final resourceFoldersProvider =
    FutureProvider.autoDispose<List<ResourceFolder>>((ref) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/resources/folders'))
          .payload;
      return [
        if (p is List)
          for (final f in p)
            if (f is Map && f['id'] is String)
              (id: f['id'] as String, name: (f['name'] as String?) ?? ''),
      ];
    }, retry: (retryCount, error) => null);

typedef Opener = ({String name, String via, DateTime? lastOpened, int opens});

typedef ResourceInsights = ({
  int students,
  List<Opener> opened,
  List<Opener> notOpened,
});

final resourceInsightsProvider = FutureProvider.autoDispose
    .family<ResourceInsights, String>((ref, id) async {
      final p =
          (await ref.read(apiClientProvider).get('/resources/$id/insights'))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      List<Opener> people(Object? list) => [
        if (list is List)
          for (final s in list)
            if (s is Map)
              (
                name: (s['full_name'] as String?) ?? '',
                via: (s['via'] as String?) ?? '',
                lastOpened: s['last_opened_at'] is String
                    ? DateTime.tryParse(s['last_opened_at'] as String)
                    : null,
                opens: (s['opens'] as num?)?.toInt() ?? 0,
              ),
      ];
      return (
        students: (j['students'] as num?)?.toInt() ?? 0,
        opened: people(j['opened']),
        notOpened: people(j['not_opened']),
      );
    }, retry: (retryCount, error) => null);

/// The web's /resources for staff (`ResourcesPage` StaffLibrary): their
/// library and what is shared with the classes they teach; search, folders,
/// archived; add a file or a link and share it with subject classes; edit,
/// archive, delete; who opened it.
class StaffResourcesScreen extends ConsumerStatefulWidget {
  const StaffResourcesScreen({super.key});

  @override
  ConsumerState<StaffResourcesScreen> createState() =>
      _StaffResourcesScreenState();
}

class _StaffResourcesScreenState extends ConsumerState<StaffResourcesScreen> {
  String _q = '';
  String? _folder;
  bool _archived = false;
  Timer? _typing;

  LibraryQuery get _query => (q: _q, folder: _folder, archived: _archived);

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  Future<bool> _call(Future<void> Function() call, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(libraryProvider);
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      return false;
    }
  }

  Future<void> _open(LibraryResource r) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final file = r.fileId;
    if (r.resource.type != 'LINK' && file != null) {
      await openFile(context, ref, file);
      return;
    }
    final ok = await ref.read(openLinkProvider)(r.resource.target);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.appFileOpenFailed)));
    }
  }

  Future<void> _edit(LibraryResource? r) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ResourceFormScreen(resource: r),
      ),
    );
    if (saved == true && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.resourcesSaved)));
      ref.invalidate(libraryProvider);
    }
  }

  Future<void> _delete(LibraryResource r) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.resourcesDeleteTitle(r.resource.title)),
        content: Text(l10n.resourcesDeleteDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.resourcesCancel),
          ),
          FilledButton(
            key: const Key('resource-delete-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.resourcesDelete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _call(
      () => ref.read(apiClientProvider).delete('/resources/${r.id}'),
      l10n.resourcesDeleted,
    );
  }

  Future<void> _newFolder() async {
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FolderDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    if (await _call(
      () => ref
          .read(apiClientProvider)
          .post('/resources/folders', data: {'name': name.trim()}),
      l10n.resourcesFolderAdded,
    )) {
      ref.invalidate(resourceFoldersProvider);
    }
  }

  Future<void> _deleteFolder(String id) async {
    final l10n = context.l10n;
    if (await _call(
      () => ref.read(apiClientProvider).delete('/resources/folders/$id'),
      l10n.resourcesFolderDeleted,
    )) {
      ref.invalidate(resourceFoldersProvider);
      if (mounted) setState(() => _folder = null);
    }
  }

  void _insights(LibraryResource r) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _Insights(resource: r),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final items = ref.watch(libraryProvider(_query));
    final folders =
        ref.watch(resourceFoldersProvider).value ?? const <ResourceFolder>[];
    final folder = _folder == null || _folder == 'none'
        ? null
        : folders.where((f) => f.id == _folder).firstOrNull;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.resourcesTitle, style: text.headlineSmall),
            Text(
              l10n.resourcesStaffDescription,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const Key('resource-add'),
                icon: const Icon(Icons.add),
                label: Text(l10n.resourcesAdd),
                onPressed: () => _edit(null),
              ),
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
            DropdownButtonFormField<String?>(
              key: const Key('resource-folder'),
              initialValue:
                  _folder == 'none' || folders.any((f) => f.id == _folder)
                  ? _folder
                  : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.resourcesFolder),
              items: [
                DropdownMenuItem<String?>(
                  child: Text(l10n.resourcesAllFolders),
                ),
                DropdownMenuItem<String?>(
                  value: 'none',
                  child: Text(l10n.resourcesNoFolder),
                ),
                for (final f in folders)
                  DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => _folder = v),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                TextButton.icon(
                  key: const Key('folder-new'),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(l10n.resourcesNewFolder),
                  onPressed: _newFolder,
                ),
                if (folder != null)
                  TextButton.icon(
                    key: const Key('folder-delete'),
                    icon: const Icon(Icons.folder_delete_outlined),
                    label: Text(l10n.resourcesDeleteFolder),
                    onPressed: () => _deleteFolder(folder.id),
                  ),
              ],
            ),
            SwitchListTile(
              key: const Key('resource-archived'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.resourcesShowArchived),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                    onRetry: () => ref.invalidate(libraryProvider(_query)),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 260,
                        child: EmptyView(
                          icon: Icons.folder_open_outlined,
                          title: _archived
                              ? l10n.resourcesNoArchived
                              : l10n.resourcesEmpty,
                          message: _archived ? null : l10n.resourcesEmptyHint,
                        ),
                      ),
                    ]
                  : [
                      for (final r in list) ...[
                        _ResourceCard(
                          key: Key('resource-${r.id}'),
                          item: r,
                          onOpen: () => _open(r),
                          onInsights: () => _insights(r),
                          onEdit: () => _edit(r),
                          onArchive: () => _call(
                            () => ref
                                .read(apiClientProvider)
                                .patch(
                                  '/resources/${r.id}',
                                  data: {'archived': !r.archived},
                                ),
                            r.archived
                                ? l10n.resourcesRestored
                                : l10n.resourcesArchivedDone,
                          ),
                          onDelete: () => _delete(r),
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

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.item,
    required this.onOpen,
    required this.onInsights,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
    super.key,
  });

  final LibraryResource item;
  final VoidCallback onOpen;
  final VoidCallback onInsights;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final r = item.resource;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return AppCard(
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
              Expanded(child: Text(r.title, style: text.titleSmall)),
              if (!r.downloadAllowed)
                StatusPill(
                  label: l10n.resourcesViewOnly,
                  tone: StatusTone.warning,
                ),
            ],
          ),
          if (r.description != null && r.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(r.description!, style: text.bodyMedium),
            ),
          Text(
            [
              switch (r.type) {
                'LINK' => l10n.resourcesTypesLINK,
                'VIDEO' => l10n.resourcesTypesVIDEO,
                _ => l10n.resourcesTypesFILE,
              },
              r.subject,
              r.fileName,
              ...item.tags,
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            style: muted,
          ),
          Text(
            item.shares.isEmpty
                ? l10n.resourcesNotShared
                : l10n.resourcesSharedWith(
                    item.shares.map((s) => s.label).join(', '),
                  ),
            style: muted,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton(
                key: Key('open-${item.id}'),
                onPressed: onOpen,
                child: Text(l10n.resourcesOpen),
              ),
              if (item.canEdit) ...[
                TextButton(
                  key: Key('insights-${item.id}'),
                  onPressed: onInsights,
                  child: Text(l10n.resourcesWhoOpened),
                ),
                TextButton(
                  key: Key('edit-${item.id}'),
                  onPressed: onEdit,
                  child: Text(l10n.resourcesEdit),
                ),
                TextButton(
                  key: Key('archive-${item.id}'),
                  onPressed: onArchive,
                  child: Text(
                    item.archived
                        ? l10n.resourcesRestore
                        : l10n.resourcesArchive,
                  ),
                ),
                TextButton(
                  key: Key('delete-${item.id}'),
                  onPressed: onDelete,
                  child: Text(l10n.resourcesDelete),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "New folder": pops the name, or nothing when cancelled.
class _FolderDialog extends StatefulWidget {
  const _FolderDialog();

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.resourcesNewFolder),
      content: TextField(
        key: const Key('folder-name'),
        controller: _name,
        autofocus: true,
        maxLength: 120,
        decoration: InputDecoration(labelText: l10n.resourcesFolderName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.resourcesCancel),
        ),
        FilledButton(
          key: const Key('folder-save'),
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: Text(l10n.resourcesSave),
        ),
      ],
    );
  }
}

/// Who opened it and who has not (`GET /resources/:id/insights`).
class _Insights extends ConsumerWidget {
  const _Insights({required this.resource});

  final LibraryResource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final data = ref.watch(resourceInsightsProvider(resource.id));
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(resource.resource.title, style: text.titleMedium),
            Text(l10n.resourcesWhoOpened, style: muted),
            const SizedBox(height: AppSpacing.md),
            ...data.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [
                Text(e is ApiException ? apiErrorText(l10n, e) : '$e'),
              ],
              data: (d) => [
                Text(
                  l10n.resourcesOpenedCount(d.opened.length, d.students),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.resourcesOpened, style: text.labelLarge),
                if (d.opened.isEmpty)
                  Text(l10n.resourcesNobodyYet, style: muted),
                for (final s in d.opened)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.name),
                    subtitle: Text(
                      [
                        s.via,
                        if (s.lastOpened != null)
                          l10n.resourcesOpenedAt(
                            OrgTime.dateTime(s.lastOpened!, language),
                            s.opens,
                          ),
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                  ),
                if (d.notOpened.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.resourcesNotOpened, style: text.labelLarge),
                  for (final s in d.notOpened)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      subtitle: Text(s.via),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Adding or changing a resource (the web's `ResourceForm`): a file or a
/// link, title, description, subject, folder, tags, "Students may download
/// it", and the subject classes it is shared with. Pops true when saved.
class ResourceFormScreen extends ConsumerStatefulWidget {
  const ResourceFormScreen({this.resource, super.key});

  /// Null for a new one.
  final LibraryResource? resource;

  @override
  ConsumerState<ResourceFormScreen> createState() => _ResourceFormScreenState();
}

class _ResourceFormScreenState extends ConsumerState<ResourceFormScreen> {
  late final LibraryResource? _r = widget.resource;
  late String _kind = _r?.resource.type == 'LINK' ? 'LINK' : 'FILE';
  late final _title = TextEditingController(text: _r?.resource.title ?? '');
  late final _description = TextEditingController(
    text: _r?.resource.description ?? '',
  );
  late final _url = TextEditingController();
  late final _tags = TextEditingController(text: _r?.tags.join(', ') ?? '');
  late String? _subject = _r?.resource.subjectId;
  late String? _folder = _r?.folderId;
  late bool _download = _r?.resource.downloadAllowed ?? true;
  late final Set<String> _shares = {...?_r?.shares.map((s) => s.offeringId)};
  List<UploadedFile> _files = const [];
  bool _uploading = false;
  bool _busy = false;

  bool get _editing => _r != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _url.dispose();
    _tags.dispose();
    super.dispose();
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty &&
      !_uploading &&
      (_editing ||
          (_kind == 'LINK' ? _url.text.trim().isNotEmpty : _files.isNotEmpty));

  List<String> get _tagList => <String>{
    for (final t in _tags.text.split(','))
      if (t.trim().isNotEmpty) t.trim(),
  }.take(10).toList();

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final description = _description.text.trim();
    try {
      final api = ref.read(apiClientProvider);
      if (_editing) {
        await api.patch(
          '/resources/${_r!.id}',
          data: {
            'title': _title.text.trim(),
            'description': description.isEmpty ? null : description,
            'subject_id': _subject,
            'folder_id': _folder,
            'tags': _tagList,
            'download_allowed': _download,
            'offering_ids': _shares.toList(),
          },
        );
      } else {
        await api.post(
          '/resources',
          data: {
            'type': _kind,
            'title': _title.text.trim(),
            'description': ?(description.isEmpty ? null : description),
            'subject_id': ?_subject,
            'folder_id': ?_folder,
            'tags': _tagList,
            'download_allowed': _download,
            'offering_ids': _shares.toList(),
            if (_kind == 'LINK')
              'url': _url.text.trim()
            else
              'file_id': _files.first.id,
          },
        );
      }
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final options =
        ref.watch(shareOptionsProvider).value ?? const <ShareOption>[];
    final folders =
        ref.watch(resourceFoldersProvider).value ?? const <ResourceFolder>[];
    final subjects = {for (final o in options) o.subjectId: o.subject};
    if (_subject != null && !subjects.containsKey(_subject)) {
      subjects[_subject!] = _r?.resource.subject ?? '';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? l10n.resourcesEditTitle : l10n.resourcesAddTitle,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (!_editing) ...[
                  Text(l10n.resourcesKind, style: text.labelLarge),
                  RadioGroup<String>(
                    groupValue: _kind,
                    onChanged: (v) => setState(() => _kind = v ?? _kind),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          key: const Key('kind-file'),
                          contentPadding: EdgeInsets.zero,
                          value: 'FILE',
                          title: Text(l10n.resourcesKindFile),
                          subtitle: Text(l10n.resourcesKindFileHint),
                        ),
                        RadioListTile<String>(
                          key: const Key('kind-link'),
                          contentPadding: EdgeInsets.zero,
                          value: 'LINK',
                          title: Text(l10n.resourcesKindLink),
                          subtitle: Text(l10n.resourcesKindLinkHint),
                        ),
                      ],
                    ),
                  ),
                  if (_kind == 'FILE') ...[
                    AttachmentField(
                      label: l10n.resourcesFile,
                      purpose: FilePurpose.resource,
                      maxFiles: 1,
                      enabled: !_busy,
                      onChanged: (f) => setState(() {
                        _files = f;
                        if (_title.text.trim().isEmpty && f.isNotEmpty) {
                          _title.text = f.first.name.replaceFirst(
                            RegExp(r'\.[^.]+$'),
                            '',
                          );
                        }
                      }),
                      onBusyChanged: (b) => setState(() => _uploading = b),
                    ),
                    Text(l10n.resourcesFileTypes, style: text.bodySmall),
                  ] else
                    TextField(
                      key: const Key('resource-url'),
                      controller: _url,
                      keyboardType: TextInputType.url,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: l10n.resourcesUrl,
                        hintText: 'https://',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextField(
                  key: const Key('resource-title'),
                  controller: _title,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: l10n.resourcesTitleLabel,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  key: const Key('resource-description'),
                  controller: _description,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l10n.resourcesDescriptionLabel,
                  ),
                ),
                DropdownButtonFormField<String?>(
                  key: const Key('resource-subject'),
                  initialValue: _subject,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.resourcesSubject),
                  items: [
                    DropdownMenuItem<String?>(
                      child: Text(l10n.resourcesNoSubject),
                    ),
                    for (final MapEntry(:key, :value) in subjects.entries)
                      DropdownMenuItem<String?>(value: key, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => _subject = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('resource-form-folder'),
                  initialValue: folders.any((f) => f.id == _folder)
                      ? _folder
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.resourcesFolder),
                  items: [
                    DropdownMenuItem<String?>(
                      child: Text(l10n.resourcesNoFolder),
                    ),
                    for (final f in folders)
                      DropdownMenuItem<String?>(
                        value: f.id,
                        child: Text(f.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _folder = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('resource-tags'),
                  controller: _tags,
                  decoration: InputDecoration(labelText: l10n.resourcesTags),
                ),
                CheckboxListTile(
                  key: const Key('resource-download'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _download,
                  title: Text(l10n.resourcesDownload),
                  subtitle: Text(l10n.resourcesDownloadHint),
                  onChanged: (v) => setState(() => _download = v ?? true),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.resourcesShareWith, style: text.labelLarge),
                if (options.isEmpty)
                  Text(
                    l10n.resourcesNoClasses,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                for (final o in options)
                  CheckboxListTile(
                    key: Key('share-${o.offeringId}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _shares.contains(o.offeringId),
                    title: Text(o.label),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _shares.add(o.offeringId)
                          : _shares.remove(o.offeringId),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.resourcesCancel),
                    ),
                    FilledButton(
                      key: const Key('resource-save'),
                      onPressed: _busy || !_ready ? null : _save,
                      child: Text(l10n.resourcesSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
