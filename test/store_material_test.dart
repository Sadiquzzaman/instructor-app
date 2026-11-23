import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The store files meet the stores' limits (docs/store).
void main() {
  test('the Play icon is a 512×512 PNG under 1 MB', () {
    final f = File('docs/store/play-icon-512.png');
    final bytes = f.readAsBytesSync();
    expect(bytes.length, lessThan(1024 * 1024));
    // PNG signature, then the IHDR chunk's width and height.
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
    final header = ByteData.sublistView(bytes, 16, 24);
    expect(header.getUint32(0), 512);
    expect(header.getUint32(4), 512);
  });

  test('the short descriptions fit Play\'s 80 characters', () {
    final text = File('docs/store/listing.md').readAsStringSync();
    final section = text.split('## Short description')[1].split('\n## ')[0];
    final quotes = [
      for (final l in section.split('\n'))
        if (l.startsWith('> ')) l.substring(2),
    ];
    expect(quotes, hasLength(2));
    for (final q in quotes) {
      expect(q.runes.length, lessThanOrEqualTo(80), reason: q);
    }
  });

  test('the store texts never point at buying', () {
    for (final path in ['docs/store/listing.md']) {
      final text = File(path).readAsStringSync().toLowerCase();
      // The listing only says it doesn't mention these.
      final body = text.split('## name')[1];
      for (final word in ['price', 'buy', 'subscribe', 'upgrade', 'কিনুন']) {
        expect(body.contains(word), isFalse, reason: word);
      }
    }
  });
}
