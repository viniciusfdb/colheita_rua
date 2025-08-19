import 'package:flutter_test/flutter_test.dart';
import 'package:colheita_rua/core/utils/slug.dart';

void main() {
  group('slugify', () {
    test('removes leading and trailing hyphens', () {
      expect(slugify(' São Paulo! '), 'sao-paulo');
      expect(slugify('Azul!'), 'azul');
    });

    test('handles multiple separators', () {
      expect(slugify('Rio---de Janeiro'), 'rio-de-janeiro');
    });
  });
}
