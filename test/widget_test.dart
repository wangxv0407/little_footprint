import 'package:flutter_test/flutter_test.dart';

import 'package:little_footprint/utils/age_calculator.dart';

void main() {
  test('AgeCalculator 计算出生天数', () {
    final birth = DateTime(2026, 10, 1);
    final target = DateTime(2026, 10, 5);
    expect(AgeCalculator.fullText(birth, target), '出生4天');
  });

  test('AgeCalculator 计算月龄', () {
    final birth = DateTime(2025, 10, 1);
    final target = DateTime(2026, 10, 29);
    final text = AgeCalculator.fullText(birth, target);
    expect(text.startsWith('1岁'), isTrue);
  });
}
