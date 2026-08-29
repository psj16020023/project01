import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/core/app_colors.dart';
import 'package:pyeonpick_app/src/core/app_theme.dart';
import 'package:pyeonpick_app/src/models/app_tab.dart';
import 'package:pyeonpick_app/src/screens/auth_screen.dart';
import 'package:pyeonpick_app/src/screens/home_screen.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test('pastel controls and text retain readable contrast', () {
    for (final pair in [
      (AppColors.ink, AppColors.lime),
      (AppColors.ink, AppColors.skyBlue),
      (AppColors.ink, AppColors.paper),
      (AppColors.limeDeep, AppColors.limeSoft),
      (AppColors.limeDeep, AppColors.lime),
      (AppColors.skyBlueDeep, AppColors.sky),
      (AppColors.muted, AppColors.receipt),
    ]) {
      expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
    final theme = AppTheme.light;
    expect(theme.colorScheme.primary, AppColors.skyBlue);
    expect(theme.colorScheme.secondary, AppColors.lime);
    expect(
      theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
      AppColors.skyBlue,
    );
    expect(
      theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
      AppColors.ink,
    );
    expect(
      theme.textButtonTheme.style!.foregroundColor!.resolve({}),
      AppColors.skyBlueDeep,
    );
  });

  test('browser chrome and loading screen use the same palette', () {
    final manifest = File('web/manifest.json').readAsStringSync();
    final boot = File('web/index.html').readAsStringSync();
    expect(manifest, contains('#91D5F0'));
    expect(boot, contains('name="theme-color" content="#91D5F0"'));
    expect(boot, contains('#cbea89'));
    expect(boot, isNot(contains('#16467a')));
  });

  test('app surfaces and web boot screen do not use gradients', () {
    final sources = [
      File('lib/src/screens/auth_screen.dart'),
      File('lib/src/screens/combination_battle_screen.dart'),
      File('lib/src/screens/home_screen.dart'),
      File('web/index.html'),
    ];
    for (final source in sources) {
      final content = source.readAsStringSync();
      expect(content, isNot(contains('LinearGradient')));
      expect(content, isNot(contains('linear-gradient')));
    }
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('login accents remain readable at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AuthScreen(
            onSignIn: (_, _) async {},
            onSignUp: (_, _, _) async {},
          ),
        ),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style!.backgroundColor!.resolve({}), AppColors.lime);
      expect(button.style!.foregroundColor!.resolve({}), AppColors.ink);
      await tester.tap(find.text('회원가입'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('signup-nickname')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('feature navigation keeps labels with sky fill and lime line', (
    tester,
  ) async {
    AppTab? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FeatureTabs(
            selectedTab: AppTab.communication,
            onChanged: (tab) => selected = tab,
          ),
        ),
      ),
    );
    final label = tester.widget<Text>(find.text('꿀조합 공유'));
    expect(label.style!.color, AppColors.skyBlueDeep);
    await tester.tap(find.text('픽 쇼츠'));
    expect(selected, AppTab.battle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taste setup uses both accents without white score labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: BotSetupPage(onComplete: (_) async {})),
      ),
    );
    final colors = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color);
    expect(colors, containsAll([AppColors.lime, AppColors.skyBlue]));
    for (final label in tester.widgetList<Text>(find.text('1'))) {
      expect(label.style!.color, AppColors.ink);
    }
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    expect(find.text('5/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
