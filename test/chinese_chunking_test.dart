import 'package:flutter_test/flutter_test.dart';
import 'package:lu_ji/services/chunking_service.dart';

void main() {
  test('Chinese text splits at 。！？ though no space follows them', () {
    expect(
      chunkText('天下之道，合于一。圣人之治，贵在知机！可乎？'),
      ['天下之道，合于一。', '圣人之治，贵在知机！', '可乎？'],
    );
  });

  test('a closing quote stays with its sentence', () {
    expect(chunkText('他说：「可以。」然后离开了。'), ['他说：「可以。」', '然后离开了。']);
  });

  test('English splitting is unchanged', () {
    expect(chunkText('He left. She stayed.'), ['He left.', 'She stayed.']);
  });
}
