import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/app.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const PyeonPickApp());
    expect(find.text('편pick! 오늘은 뭘 사먹을까?'), findsOneWidget);
  });
}
