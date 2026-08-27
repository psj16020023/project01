import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/screens/auth_screen.dart';

void main() {
  testWidgets('login does not advertise development-only credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onSignIn: (_, _) async {},
          onSignUp: (_, _, _) async {},
        ),
      ),
    );
    expect(find.textContaining('테스트 계정'), findsNothing);
    expect(find.byKey(const ValueKey('signin-username')), findsOneWidget);
    expect(find.byKey(const ValueKey('signin-password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
