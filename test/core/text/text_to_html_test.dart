import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/text/html_text.dart';

void main() {
  test('paragraphs, line breaks and lists', () {
    expect(
      textToHtml(
        'Read chapter 3.\nThen answer:\n\n- Question 1\n• Question 2\n\nThanks',
      ),
      '<p>Read chapter 3.<br>Then answer:</p>'
      '<ul><li>Question 1</li><li>Question 2</li></ul>'
      '<p>Thanks</p>',
    );
  });

  test('escapes &, < and >', () {
    expect(textToHtml('a < b & c > d'), '<p>a &lt; b &amp; c &gt; d</p>');
  });

  test('empty text is empty', () {
    expect(textToHtml('  \n\n '), '');
  });

  test('round trip with htmlToText keeps the words and the list', () {
    const text = 'Read chapter 3.\n\n- Question 1\n- Question 2';
    expect(
      htmlToText(textToHtml(text)),
      'Read chapter 3.\n• Question 1\n• Question 2',
    );
  });
}
