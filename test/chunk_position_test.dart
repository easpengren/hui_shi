import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';

/// A reading position is stored as a bare chunk index, so any change to
/// chunking silently moves it. Improving the sentence splitter alone changed
/// this app's chunk count for one book by 22% — a place saved at 53% through
/// would have reopened at about 68%.
void main() {
  test('an unchanged chunk count keeps the exact position', () {
    expect(rescaleChunkIndex(index: 1200, oldTotal: 3772, newTotal: 3772), 1200);
  });

  test('the real case: 22% fewer chunks after the splitter changed', () {
    // 2000 of 3772 is 53% through; 1557 of 2937 is the same place.
    expect(rescaleChunkIndex(index: 2000, oldTotal: 3772, newTotal: 2937), 1557);
  });

  test('a coarser chunking maps back too', () {
    expect(rescaleChunkIndex(index: 1557, oldTotal: 2937, newTotal: 3772), 2000);
  });

  test('a first-time open has no previous total', () {
    expect(rescaleChunkIndex(index: 0, oldTotal: 0, newTotal: 40), 0);
    expect(rescaleChunkIndex(index: 7, oldTotal: 0, newTotal: 40), 7);
  });

  test('never points past the end', () {
    expect(rescaleChunkIndex(index: 3771, oldTotal: 3772, newTotal: 100), 99);
    expect(rescaleChunkIndex(index: 9000, oldTotal: 0, newTotal: 100), 99);
  });

  test('an empty document is position zero', () {
    expect(rescaleChunkIndex(index: 500, oldTotal: 3772, newTotal: 0), 0);
  });
}
