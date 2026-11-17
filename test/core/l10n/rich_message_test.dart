import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/rich_message.dart';

void main() {
  test('splits a message into plain and tagged parts', () {
    expect(
      RichMessage.parse('Drag files here or <browse>choose files</browse>.'),
      [
        (tag: null, text: 'Drag files here or '),
        (tag: 'browse', text: 'choose files'),
        (tag: null, text: '.'),
      ],
    );
    expect(RichMessage.parse('No tags'), [(tag: null, text: 'No tags')]);
  });

  testWidgets('shows the text without tags and taps a linked part', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichMessage(
            'Drag files here or <browse>choose files</browse>',
            onTap: {'browse': () => taps++},
          ),
        ),
      ),
    );
    expect(
      find.text('Drag files here or choose files', findRichText: true),
      findsOneWidget,
    );

    final text = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText() == 'Drag files here or choose files',
      ),
    );
    TextSpan? link;
    text.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'choose files') link = span;
      return link == null;
    });
    (link!.recognizer! as TapGestureRecognizer).onTap!();
    expect(taps, 1);
  });
}
