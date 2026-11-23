import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';

/// Opens a file the server has (a teacher's attachment, a hand-in, a
/// resource) in the phone's viewer or browser, which also lets the person
/// download it. Says so when nothing can open it.
Future<void> openFile(
  BuildContext context,
  WidgetRef ref,
  String fileId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.appFileOpenFailed;
  final opened = await ref.read(openLinkProvider)(fileContentUri(fileId));
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
}

/// A picture the server has, loaded through its content link, with a
/// placeholder while it loads and an icon if it can't.
class ServerImage extends StatelessWidget {
  const ServerImage({
    required this.fileId,
    this.size = 96,
    this.semanticLabel,
    super.key,
  });

  final String fileId;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.network(
        fileContentUri(fileId).toString(),
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stack) =>
            const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
