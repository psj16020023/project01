import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pyeonpick_app/src/data/mock_posts.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/models/combination_battle.dart';
import 'package:pyeonpick_app/src/models/post.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
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

  testWidgets('profile taste summary expands and collapses cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const tasteUser = PyeonUser(
      id: 'taste-test',
      username: 'taste-test',
      password: '',
      nickname: '취향 테스트',
      botSetup: BotSetup(
        age: 15,
        gender: '남자',
        tasteRatings: {'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
        priorityValues: ['시간절약', '호불호'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            currentUser: tasteUser,
            repository: MockPostRepository(
              initialBattleState: const CombinationBattleState(),
            ),
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

    expect(find.text('기본 정보'), findsOneWidget);
    expect(find.text('맛 선호'), findsOneWidget);
    await tester.tap(find.text('접기'));
    await tester.pumpAndSettle();
    expect(find.text('기본 정보'), findsNothing);
    expect(find.text('펼치기'), findsOneWidget);
    expect(find.text('남자 · 15세 · 시간절약 · 호불호'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile keeps account controls and offers private Pick Shorts results on mobile',
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
              repository: MockPostRepository(
                initialBattleState: const CombinationBattleState(),
              ),
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
      expect(find.text('픽 쇼츠'), findsOneWidget);
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

  testWidgets('post review action sits in the post header, not the app bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final post = mockPosts.first;
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailPage(
          post: post,
          currentUser: user,
          allPosts: mockPosts,
          allUsers: const [user],
          onLoadAudienceStats: () async =>
              const PostAudienceStats(maleCount: 0, femaleCount: 0),
          isMine: false,
          isSaved: false,
          onToggleLike: () async => post,
          onToggleDislike: () async => post,
          onAddComment: (_) async => post,
          onToggleSave: () async {},
          onEdit: () async {},
          onDelete: () async {},
          onOpenAuthor: () {},
          onOpenCommentAuthor: (_, _) {},
          onAddReview: (_) async => post,
          onUpdateReview: (_) async => post,
          onDeleteReview: (_) async => post,
        ),
      ),
    );

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('후기 작성')),
      findsNothing,
    );
    expect(find.text('후기 작성'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
