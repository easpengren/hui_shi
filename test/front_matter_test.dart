import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/front_matter.dart';

/// Measured on the real thing: the Gutenberg wrapper around *The Art of War*
/// is 19,305 characters, about twenty-five minutes of spoken licence text
/// before and after the book.
void main() {
  group('stripGutenbergWrapper', () {
    const header = 'The Project Gutenberg eBook of Something\n\n'
        'This eBook is for the use of anyone anywhere at no cost.\n\n'
        'Title: Something\n\nAuthor: Someone\n\n';
    const licence = '\n\nUpdated editions will replace the previous one.\n\n'
        'Most people start at our website: www.gutenberg.org.';

    test('keeps only the span between the markers', () {
      const text = '$header'
          '*** START OF THE PROJECT GUTENBERG EBOOK SOMETHING ***\n\n'
          'The real first line.\n\nThe real last line.\n\n'
          '*** END OF THE PROJECT GUTENBERG EBOOK SOMETHING ***'
          '$licence';
      expect(stripGutenbergWrapper(text),
          'The real first line.\n\nThe real last line.');
    });

    test('accepts the older THIS wording', () {
      const text = '$header'
          '*** START OF THIS PROJECT GUTENBERG EBOOK X ***\n\nBody.\n\n'
          '*** END OF THIS PROJECT GUTENBERG EBOOK X ***$licence';
      expect(stripGutenbergWrapper(text), 'Body.');
    });

    test('a missing end marker still drops the header', () {
      const text = '$header*** START OF THE PROJECT GUTENBERG EBOOK X ***'
          '\n\nBody.';
      expect(stripGutenbergWrapper(text), 'Body.');
    });

    test('a document with no markers is untouched', () {
      const text = 'Chapter One.\n\nIt was a bright cold day in April.';
      expect(stripGutenbergWrapper(text), text);
    });
  });

  group('isPublisherBoilerplate', () {
    test('recognises copyright apparatus', () {
      for (final s in [
        'All rights reserved.',
        'Copyright © 2019 by Someone.',
        '© 2019 Someone Ltd.',
        'ISBN 978-0-14-303997-4',
        'eISBN: 978-1-101-65900-4',
        'Library of Congress Cataloging-in-Publication Data',
        'A CIP catalogue record for this book is available.',
        'No part of this book may be reproduced without permission.',
        'Printed and bound in Great Britain.',
        'First published in 1969 by Faber.',
        'The moral right of the author has been asserted.',
        'Cover design by Someone.',
        'Typeset in Bembo by Someone.',
        '10 9 8 7 6 5 4 3 2 1',
        'This eBook is for the use of anyone under the Project Gutenberg '
            'License.',
      ]) {
        expect(isPublisherBoilerplate(s), isTrue, reason: s);
      }
    });

    test('leaves the book alone', () {
      for (final s in [
        'It was a bright cold day in April, and the clocks were striking.',
        'All warfare is based on deception.',
        'Sun Tzŭ on The Art of War',
        'To my brother, in the hope that a work 2400 years old may yet '
            'contain lessons worth consideration.',
      ]) {
        expect(isPublisherBoilerplate(s), isFalse, reason: s);
      }
    });

    test('a long paragraph is never boilerplate', () {
      // A chapter *about* copyright would otherwise be deleted silently.
      final essay = 'The phrase all rights reserved entered the language '
          'through the Buenos Aires Convention, and its persistence long '
          'after it ceased to have legal force is a small monument to the '
          'inertia of publishing convention, repeated on page after page. '
          '${"It endured well past its purpose. " * 12}';
      expect(essay.length, greaterThan(500));
      expect(isPublisherBoilerplate(essay), isFalse);
    });
  });


  group('isTableOfContents', () {
    test('an explicit contents heading', () {
      expect(isTableOfContents('CONTENTS'), isTrue);
      expect(isTableOfContents('Table of Contents'), isTrue);
    });

    test('a run of chapter entries', () {
      // How the Art of War contents block actually survives: one paragraph.
      expect(
        isTableOfContents('Preface by Lionel Giles INTRODUCTION Sun Wu and '
            'his Book Chapter I. Laying Plans Chapter II. Waging War '
            'Chapter III. Attack by Stratagem'),
        isTrue,
      );
    });

    test('dot leaders with page numbers', () {
      expect(
        isTableOfContents('Laying Plans ...... 1 Waging War ...... 9 '
            'Attack by Stratagem ...... 17'),
        isTrue,
      );
    });

    test('prose about chapters survives', () {
      // The failure that would matter: deleting a real chapter.
      expect(
        isTableOfContents('In this chapter I want to argue that the previous '
            'chapter was mistaken about the nature of the problem.'),
        isFalse,
      );
      expect(isTableOfContents('It was a bright cold day in April.'), isFalse);
    });
  });

  group('dropBoilerplate', () {
    test('removes it at the front', () {
      final chunks = ['All rights reserved.', 'ISBN 978-0-00-000000-0',
        'Chapter One.', 'It was a bright cold day.'];
      expect(dropBoilerplate(chunks), ['Chapter One.', 'It was a bright cold day.']);
    });

    test('removes it at the back', () {
      final chunks = ['Chapter One.', 'The end.', 'Printed in the USA.'];
      expect(dropBoilerplate(chunks), ['Chapter One.', 'The end.']);
    });

    test('never removes from the middle of a book', () {
      // The failure that would actually matter: a false positive deleting a
      // paragraph a reader is relying on.
      // Chunks are sentences here, so the edge window is 80 — the book has to
      // be long enough that its middle is genuinely in the middle.
      final chunks = <String>[
        ...List.generate(100, (i) => 'Body sentence $i, long enough to read.'),
        'All rights reserved.',
        ...List.generate(100, (i) => 'More body $i, also long enough to read.'),
      ];
      expect(dropBoilerplate(chunks).length, chunks.length,
          reason: 'a mid-book match must survive');
      expect(dropBoilerplate(chunks), contains('All rights reserved.'));
    });

    test('a document that is entirely boilerplate is handed back whole', () {
      final chunks = ['All rights reserved.', 'ISBN 978-0-00-000000-0'];
      expect(dropBoilerplate(chunks), chunks,
          reason: 'more likely a misjudgement than a book with no content');
    });

    test('an empty document is safe', () {
      expect(dropBoilerplate(const []), isEmpty);
    });
  });
}
