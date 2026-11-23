import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a message that marks parts with tags, as the web's `t.rich` does:
/// `Drag files here or <browse>choose files</browse>`.
///
/// [styles] styles each tag's text (merged onto [style]); [onTap] makes a
/// tag's text a link. Unknown tags show their text unstyled; text outside tags
/// is shown as it is.
class RichMessage extends StatefulWidget {
  const RichMessage(
    this.message, {
    this.style,
    this.styles = const {},
    this.onTap = const {},
    this.textAlign,
    super.key,
  });

  final String message;
  final TextStyle? style;
  final Map<String, TextStyle> styles;
  final Map<String, VoidCallback> onTap;
  final TextAlign? textAlign;

  /// The message split into plain text and tagged parts.
  static List<({String? tag, String text})> parse(String message) {
    final parts = <({String? tag, String text})>[];
    final tag = RegExp(r'<([A-Za-z][A-Za-z0-9]*)>(.*?)</\1>', dotAll: true);
    var last = 0;
    for (final m in tag.allMatches(message)) {
      if (m.start > last) {
        parts.add((tag: null, text: message.substring(last, m.start)));
      }
      parts.add((tag: m[1], text: m[2]!));
      last = m.end;
    }
    if (last < message.length) {
      parts.add((tag: null, text: message.substring(last)));
    }
    return parts;
  }

  @override
  State<RichMessage> createState() => _RichMessageState();
}

class _RichMessageState extends State<RichMessage> {
  final _recognizers = <TapGestureRecognizer>[];

  void _dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dispose();
    final linkColor = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    for (final part in RichMessage.parse(widget.message)) {
      final tag = part.tag;
      if (tag == null) {
        spans.add(TextSpan(text: part.text));
        continue;
      }
      final tap = widget.onTap[tag];
      TapGestureRecognizer? recognizer;
      if (tap != null) {
        recognizer = TapGestureRecognizer()..onTap = tap;
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: part.text,
          recognizer: recognizer,
          style: tap != null
              ? TextStyle(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ).merge(widget.styles[tag])
              : widget.styles[tag],
        ),
      );
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
