// test/core/utils/exam_date_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_exam_app/core/utils/exam_date_options.dart';

void main() {
  test('returns 61 consecutive dates starting today, time stripped', () {
    final now = DateTime(2026, 9, 14, 15, 30);
    final options = examDateOptions(now: now);

    expect(options.length, 61);
    expect(options.first, DateTime(2026, 9, 14));
    expect(options.last, DateTime(2026, 11, 13));
    expect(options[1], DateTime(2026, 9, 15));
  });
}
