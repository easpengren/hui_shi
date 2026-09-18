import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/state/reader_state.dart';

/// Shared text is keyed by its content, not by when it arrived.
///
/// The bug this fixes: Four Books hands a chapter to LuJi over the same door
/// Confucius uses for article prose (#97), and `openSharedText` opened it with
/// no id and no start chunk — so `bookId` became a fresh uuid on every share
/// and playback restarted at the beginning. The position was being written
/// correctly the whole time, under the previous uuid, which nothing would ever
/// open again.
///
/// The old filename appended `DateTime.now().millisecondsSinceEpoch`,
/// deliberately, "so sharing the same article twice does not silently reopen
/// the first copy". That is the right instinct and the wrong key: an article
/// arriving twice IS new, and a chapter of the Analects arriving twice is the
/// one you were listening to yesterday. Content tells them apart; arrival time
/// cannot.

void main() {
  group('the same text is the same book', () {
    test('two shares of identical text share an id', () {
      const chapter = 'The Master said: to learn and at times to practise it.';
      expect(ReaderState.sharedTextId(chapter),
          ReaderState.sharedTextId(chapter));
    });

    test('a re-wrapped handoff is still the same book', () {
      // The two sides stage the text through a file and an intent; a handoff
      // that re-wraps lines or gains a trailing newline must not read as a
      // different text, or the bug comes back wearing a different hat.
      const a = 'The Master said:\nto learn and at times to practise it.';
      const b = 'The Master said: to learn and at times to practise it.\n';
      expect(ReaderState.sharedTextId(a), ReaderState.sharedTextId(b));
    });

    test('leading and trailing whitespace is not identity', () {
      expect(ReaderState.sharedTextId('  a chapter  '),
          ReaderState.sharedTextId('a chapter'));
    });
  });

  group('different texts stay different books', () {
    test('two articles do not collide', () {
      expect(ReaderState.sharedTextId('First article body.'),
          isNot(ReaderState.sharedTextId('Second article body.')));
    });

    test('a one-word difference is a different book', () {
      expect(ReaderState.sharedTextId('The Master said: to learn.'),
          isNot(ReaderState.sharedTextId('The Master said: to teach.')));
    });

    test('same opening line, different body — the case a title would miss', () {
      // The library title comes from the first line, so two texts can look
      // identical in the list. They must not share a reading position.
      const a = 'Chapter One\nThe first body text.';
      const b = 'Chapter One\nA completely different body.';
      expect(ReaderState.sharedTextId(a), isNot(ReaderState.sharedTextId(b)));
    });
  });

  group('the id is usable as a key', () {
    test('it is stable, prefixed and short enough to read in a log', () {
      final id = ReaderState.sharedTextId('some text');
      expect(id, startsWith('shared-'));
      expect(id.length, lessThan(32));
      expect(id, matches(RegExp(r'^shared-[0-9a-f]+$')));
    });

    test('empty text still yields an id rather than throwing', () {
      expect(ReaderState.sharedTextId(''), startsWith('shared-'));
    });
  });
}
