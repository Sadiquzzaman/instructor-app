import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/local_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

enum _State { uploading, done, failed, refused }

class _Item {
  _Item(this.file);

  final LocalFile file;
  _State state = _State.uploading;
  double progress = 0;
  UploadedFile? uploaded;
  String? error;
  CancelToken? cancel;
}

/// Photos and files for a form (homework hand-in, leave, chat): take a photo,
/// choose photos or choose files; each is uploaded at once with its progress,
/// and can be removed or, after a failure, uploaded again. [onChanged] gets
/// the uploaded files; [onBusyChanged] says whether any is still uploading,
/// so the form can wait before it sends.
class AttachmentField extends ConsumerStatefulWidget {
  const AttachmentField({
    required this.label,
    required this.purpose,
    required this.onChanged,
    this.onBusyChanged,
    this.scopeId,
    this.maxFiles = 10,
    this.enabled = true,
    super.key,
  });

  /// The field's name in the screen's words ("Photos or files", "Attachment").
  final String label;
  final FilePurpose purpose;
  final String? scopeId;
  final int maxFiles;
  final bool enabled;
  final ValueChanged<List<UploadedFile>> onChanged;
  final ValueChanged<bool>? onBusyChanged;

  @override
  ConsumerState<AttachmentField> createState() => _AttachmentFieldState();
}

class _AttachmentFieldState extends ConsumerState<AttachmentField> {
  final _items = <_Item>[];
  bool _storageWarning = false;

  @override
  void dispose() {
    for (final i in _items) {
      i.cancel?.cancel();
    }
    super.dispose();
  }

  bool get _busy => _items.any((i) => i.state == _State.uploading);

  void _changed() {
    widget.onChanged([
      for (final i in _items)
        if (i.uploaded != null) i.uploaded!,
    ]);
    widget.onBusyChanged?.call(_busy);
  }

  Future<void> _choose() async {
    final l10n = context.l10n;
    final picking = ref.read(filePickingProvider);
    final room = widget.maxFiles - _items.length;
    if (room <= 0) {
      _snack(l10n.appAttachTooMany(widget.maxFiles));
      return;
    }
    final source = await showModalBottomSheet<int>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.appAttachTakePhoto),
              onTap: () => Navigator.of(sheet).pop(0),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.appAttachChoosePhotos),
              onTap: () => Navigator.of(sheet).pop(1),
            ),
            if (widget.purpose.allowsDocuments)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(l10n.appAttachChooseFile),
                onTap: () => Navigator.of(sheet).pop(2),
              ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = switch (source) {
      0 => [?await picking.takePhoto()],
      1 => await picking.choosePhotos(limit: room),
      _ => await picking.chooseFiles(extensionsFor(widget.purpose.mimes)),
    };
    if (!mounted || picked.isEmpty) return;
    if (picked.length > room) _snack(l10n.appAttachTooMany(widget.maxFiles));
    for (final f in picked.take(room)) {
      _add(f);
    }
  }

  void _add(LocalFile file) {
    final l10n = context.l10n;
    final item = _Item(file);
    if (!widget.purpose.allows(file.mime)) {
      item
        ..state = _State.refused
        ..error = l10n.appAttachTypeNotAllowed(file.name);
    } else if (file.size > maxUploadBytes) {
      item
        ..state = _State.refused
        ..error = l10n.uiFileDropTooLarge(
          file.name,
          maxUploadBytes ~/ (1024 * 1024),
        );
    }
    setState(() => _items.add(item));
    if (item.state == _State.uploading) _upload(item);
  }

  Future<void> _upload(_Item item) async {
    setState(() {
      item
        ..state = _State.uploading
        ..progress = 0
        ..error = null
        ..cancel = CancelToken();
    });
    widget.onBusyChanged?.call(true);
    try {
      final uploaded = await ref
          .read(fileUploaderProvider)
          .upload(
            widget.purpose,
            item.file,
            scopeId: widget.scopeId,
            cancelToken: item.cancel,
            onProgress: (p) {
              if (mounted) setState(() => item.progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        item
          ..state = _State.done
          ..uploaded = uploaded;
        _storageWarning = _storageWarning || uploaded.storageWarning;
      });
    } on ApiException catch (e) {
      if (!mounted || e.kind == ApiErrorKind.cancelled) return;
      setState(() {
        item
          ..state = _State.failed
          ..error = context.l10n.appAttachFailed;
      });
      // Over the storage quota: the locked-feature sheet, by role.
      await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      );
    }
    if (mounted) _changed();
  }

  void _remove(_Item item) {
    item.cancel?.cancel();
    setState(() => _items.remove(item));
    _changed();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            key: const Key('attach'),
            label: widget.label,
            icon: Icons.attach_file,
            variant: AppButtonVariant.secondary,
            onPressed: widget.enabled ? _choose : null,
          ),
        ),
        for (final item in _items)
          Padding(
            key: ObjectKey(item),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  item.file.mime.startsWith('image/')
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  color: colors.inkMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                      if (item.state == _State.uploading) ...[
                        Text(
                          l10n.appAttachUploading(
                            (item.progress * 100).round(),
                          ),
                          style: text.bodySmall?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs / 2),
                        LinearProgressIndicator(value: item.progress),
                      ],
                      if (item.error != null)
                        Text(
                          item.error!,
                          style: text.bodySmall?.copyWith(color: colors.danger),
                        ),
                    ],
                  ),
                ),
                if (item.state == _State.failed)
                  IconButton(
                    tooltip: l10n.appAttachRetry,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _upload(item),
                  ),
                IconButton(
                  tooltip: l10n.uiFileDropRemove(item.file.name),
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(item),
                ),
              ],
            ),
          ),
        if (_storageWarning)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              l10n.appAttachStorageAlmostFull,
              style: text.bodySmall?.copyWith(color: colors.warning),
            ),
          ),
      ],
    );
  }
}
