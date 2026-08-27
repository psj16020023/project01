import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pyeonpick_app/src/data/mock_posts.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/screens/home_screen.dart';
import 'package:pyeonpick_app/src/screens/post_reviews_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  const user = PyeonUser(
    id: 'ui-test',
    username: 'ui-test',
    password: '',
    nickname: '테스트',
  );

  testWidgets(
    'profile has account controls but no Pick Shorts section on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfilePage(
              currentUser: user,
              posts: const [],
              onUserChanged: (_) async {},
              onResetBotSetup: () async {},
              onLogout: () async {},
              onDeleteAccount: (_) async {},
              onOpenPost: (_) async {},
              onOpenAuthor: (_) {},
              onToggleProfilePublic: (_) async {},
            ),
          ),
        ),
      );
      expect(find.textContaining('픽 쇼츠'), findsNothing);
      expect(find.text('로그아웃'), findsOneWidget);
      expect(find.text('계정 삭제'), findsOneWidget);
      await tester.tap(find.text('프로필 공개 설정'));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(8));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reviews keep the comment composer visible and tolerate a keyboard on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final post = mockPosts.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DraggableScrollableSheet(
                    initialChildSize: .76,
                    expand: false,
                    builder: (_, controller) => PostReviewsScreen(
                      post: post,
                      currentUser: user,
                      scrollController: controller,
                      onAddReview: (_) async => post,
                      onUpdateReview: (_) async => post,
                      onDeleteReview: (_) async => post,
                    ),
                  ),
                ),
                child: const Text('후기 열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('후기 열기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reviews-bottom-sheet')), findsOneWidget);
      expect(find.text('최신순'), findsOneWidget);
      expect(find.text('평점순'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-compose-input')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewComposerSheet), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
