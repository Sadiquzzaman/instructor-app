/// Plain text from the web editor's HTML (homework instructions, resource
/// notes): paragraphs and line breaks kept, list items as "• …", headings
/// on their own line, every other tag dropped, entities decoded. The app has
/// no HTML renderer yet (docs/TODO.md); this keeps the words and their
/// order, without bold, links or tables.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'\r\n?'), '\n')
      // Line breaks and block ends become new lines.
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|tr|blockquote)>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp('<[^>]+>'), '');
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
  };
  for (final MapEntry(:key, :value) in entities.entries) {
    s = s.replaceAll(key, value);
  }
  s = s.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m[1]!)),
  );
  // No more than one empty line in a row; no spaces at line ends.
  s = s
      .split('\n')
      .map((l) => l.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}
