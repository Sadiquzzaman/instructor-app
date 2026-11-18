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

/// The web's HTML from plain text typed in the app (homework instructions;
/// owner's decision, Stage 2 plan §7.1): blank lines split paragraphs,
/// lines starting with "- " or "• " make a list, other line breaks stay,
/// and &, < and > are escaped. The web shows it as typed.
String textToHtml(String text) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final bullet = RegExp(r'^\s*[-•]\s+');
  final blocks = text
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .trim()
      .split(RegExp(r'\n\s*\n'));
  final out = StringBuffer();
  for (final block in blocks) {
    final lines = block
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    var i = 0;
    while (i < lines.length) {
      if (bullet.hasMatch(lines[i])) {
        out.write('<ul>');
        while (i < lines.length && bullet.hasMatch(lines[i])) {
          out.write(
            '<li>${esc(lines[i].replaceFirst(bullet, '').trim())}</li>',
          );
          i++;
        }
        out.write('</ul>');
      } else {
        final para = <String>[];
        while (i < lines.length && !bullet.hasMatch(lines[i])) {
          para.add(esc(lines[i].trim()));
          i++;
        }
        out.write('<p>${para.join('<br>')}</p>');
      }
    }
  }
  return out.toString();
}
