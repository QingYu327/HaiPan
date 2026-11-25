import 'package:flutter_test/flutter_test.dart';
import 'package:jw_app/theme/ink_tokens.dart';

void main() {
  test('课程色板：浅色/深色一一对应，底色与字色不相同', () {
    expect(InkCourseTints.dark.length, InkCourseTints.light.length);
    for (final (bg, fg) in [...InkCourseTints.light, ...InkCourseTints.dark]) {
      expect(bg, isNot(fg), reason: '课程底色与字色不应相同');
    }
  });

  test('语义色：浅色与深色主题各自有独立取值', () {
    expect(InkPalette.light.danger, isNot(InkPalette.dark.danger));
    expect(InkPalette.light.success, isNot(InkPalette.dark.success));
    expect(InkPalette.light.brandGradient.colors.length, 2);
    expect(InkPalette.dark.brandGradient.colors.length, 2);
  });

  test('间距与圆角：页面留白与卡片圆角保持在设计值', () {
    expect(InkSpacing.page.left, InkSpacing.l);
    expect(InkRadius.control, lessThan(InkRadius.card));
    expect(InkStroke.hairline, lessThan(InkStroke.emphasized));
  });
}
