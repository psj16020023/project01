import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pyeonpick_app/src/app.dart';
import 'package:pyeonpick_app/src/data/mock_posts.dart';
import 'package:pyeonpick_app/src/models/bot_message.dart';
import 'package:pyeonpick_app/src/models/combination_battle.dart';
import 'package:pyeonpick_app/src/models/post_feature_index.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/models/sort_mode.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
import 'package:pyeonpick_app/src/screens/combination_battle_screen.dart';
import 'package:pyeonpick_app/src/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  test('a Pick Shorts vote is fixed after the first choice', () {
    final match = BattleMatchEntry(
      id: 'battle-1',
      title: '첫 선택 고정 테스트',
      authorId: 'author',
      authorNickname: '작성자',
      leftPostId: 'left',
      rightPostId: 'right',
      createdAt: DateTime(2026, 8, 22),
      leftColorValue: 0xFF49A9D8,
      rightColorValue: 0xFFFF8B64,
    );

    final firstVote = match.castVote('user-1', BattleVoteSide.left);
    final secondVote = firstVote.castVote('user-1', BattleVoteSide.right);

    expect(firstVote.voteSideOf('user-1'), BattleVoteSide.left);
    expect(secondVote.voteSideOf('user-1'), BattleVoteSide.left);
    expect(secondVote.leftVotes, 1);
    expect(secondVote.rightVotes, 0);
  });

  testWidgets('an already voted Pick Shorts card still advances', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    BattleMatchEntry match(String id, String title, {bool voted = false}) {
      return BattleMatchEntry(
        id: id,
        title: title,
        authorId: 'author',
        authorNickname: '작성자',
        leftPostId: '',
        rightPostId: '',
        createdAt: now,
        endsAt: now.add(const Duration(hours: 1)),
        leftColorValue: 0xFF49A9D8,
        rightColorValue: 0xFFFF8B64,
        leftCustomTitle: '$title 왼쪽 A + B',
        rightCustomTitle: '$title 오른쪽 C + D',
        leftVoterIds: voted ? const <String>['voter'] : const <String>[],
      );
    }

    final user = PyeonUser(
      id: 'voter',
      username: 'voter',
      password: '1234',
      nickname: '투표자',
      battleState: CombinationBattleState(
        matches: <BattleMatchEntry>[
          match('first', '첫 번째 쇼츠', voted: true),
          match('second', '두 번째 쇼츠'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombinationBattleScreen(
            currentUser: user,
            posts: const [],
            repository: MockPostRepository(),
            onUserChanged: (_) async {},
            onOpenPost: (_) async {},
            onOpenAuthor: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('첫 번째 쇼츠'), findsOneWidget);
    await tester.tap(find.text('첫 번째 쇼츠 왼쪽 A + B'));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('두 번째 쇼츠'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app boots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PyeonPickApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('bot shows a button for the next three recommendations', (
    tester,
  ) async {
    var moreRequested = false;
    final user = PyeonUser(
      id: 'bot-user',
      username: 'bot-user',
      password: '1234',
      nickname: '편봇테스터',
      botSetup: const BotSetup(
        age: 24,
        gender: '여자',
        tasteRatings: {'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
        priorityValues: ['가성비', '시간절약'],
      ),
      botMessages: [
        BotMessage(
          role: 'assistant',
          text: '추천 결과',
          createdAt: DateTime(2026, 6, 20),
          recommendedPostIds: [mockPosts.first.id],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PyeonBotPage(
            currentUser: user,
            posts: mockPosts,
            onSend: (_, _, _) async => const BotTurnResult(),
            onMore: (_, _) async => moreRequested = true,
            onOpenPost: (_) {},
            onResetSetup: () async {},
            onResetConversation: () async {},
          ),
        ),
      ),
    );

    final moreButton = find.text('다른 추천 3개 더 보기');
    expect(moreButton, findsOneWidget);
    await tester.ensureVisible(moreButton);
    await tester.tap(moreButton);
    await tester.pump();
    expect(moreRequested, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('bot sends the current conversation budget', (tester) async {
    int? receivedBudget;
    final user = PyeonUser(
      id: 'budget-user',
      username: 'budget-user',
      password: '1234',
      nickname: '예산테스터',
      botSetup: const BotSetup(
        age: 24,
        gender: '여자',
        tasteRatings: {'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
        priorityValues: ['가성비', '시간절약'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PyeonBotPage(
            currentUser: user,
            posts: mockPosts,
            onSend: (_, _, budget) async {
              receivedBudget = budget;
              return const BotTurnResult();
            },
            onMore: (_, _) async {},
            onOpenPost: (_) {},
            onResetSetup: () async {},
            onResetConversation: () async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('bot-budget-input')), '4300');
    await tester.enterText(
      find.byKey(const Key('bot-message-input')),
      '저녁 추천해줘',
    );
    await tester.tap(find.byKey(const Key('bot-send-button')));
    await tester.pump();
    expect(receivedBudget, 4300);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('bot keeps compact controls on a 390px mobile screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = PyeonUser(
      id: 'mobile-user',
      username: 'mobile-user',
      password: '1234',
      nickname: '모바일테스터',
      botSetup: const BotSetup(
        age: 24,
        gender: '여자',
        tasteRatings: {'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
        priorityValues: ['가성비', '시간절약'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PyeonBotPage(
            currentUser: user,
            posts: mockPosts,
            onSend: (_, _, _) async => const BotTurnResult(),
            onMore: (_, _) async {},
            onOpenPost: (_) {},
            onResetSetup: () async {},
            onResetConversation: () async {},
          ),
        ),
      ),
    );

    expect(find.text('권장 칼로리 반영'), findsOneWidget);
    expect(find.byKey(const Key('bot-budget-input')), findsOneWidget);
    expect(find.byKey(const Key('bot-message-input')), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message budget is synchronized into the compact input', (
    tester,
  ) async {
    final user = PyeonUser(
      id: 'sync-user',
      username: 'sync-user',
      password: '1234',
      nickname: '동기화테스터',
      botSetup: const BotSetup(
        age: 24,
        gender: '여자',
        tasteRatings: {'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
        priorityValues: ['가성비', '시간절약'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PyeonBotPage(
            currentUser: user,
            posts: mockPosts,
            onSend: (_, _, _) async => const BotTurnResult(
              resolvedBudget: 5000,
              shouldSyncBudget: true,
            ),
            onMore: (_, _) async {},
            onOpenPost: (_) {},
            onResetSetup: () async {},
            onResetConversation: () async {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('bot-message-input')),
      '5천 원 있는데 아무거나',
    );
    await tester.tap(find.byKey(const Key('bot-send-button')));
    await tester.pump(const Duration(milliseconds: 200));

    final budgetField = tester.widget<TextField>(
      find.byKey(const Key('bot-budget-input')),
    );
    expect(budgetField.controller?.text, '5000');
  });

  testWidgets('communication topics reveal horizontal photo shelves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchController = TextEditingController();
    final minController = TextEditingController();
    final maxController = TextEditingController();
    final scrollController = ScrollController();
    addTearDown(searchController.dispose);
    addTearDown(minController.dispose);
    addTearDown(maxController.dispose);
    addTearDown(scrollController.dispose);

    final user = PyeonUser(
      id: 'communication-user',
      username: 'communication-user',
      password: '1234',
      nickname: '커뮤니케이션테스터',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunicationBody(
            loading: false,
            error: null,
            posts: mockPosts.take(2).toList(),
            allFeatureInfo: mockPosts.map(PostFeatureInfo.fromPost).toList(),
            currentUser: user,
            searchController: searchController,
            minFilterController: minController,
            maxFilterController: maxController,
            sortMode: SortMode.latest,
            selectedTags: const <String>{},
            scrollController: scrollController,
            hasMorePosts: false,
            loadingMore: false,
            onReload: () async {},
            onChangeSort: (_) {},
            onToggleLike: (_) async {},
            onToggleDislike: (_) async {},
            onToggleSave: (_) async {},
            onAddComment: (_, _) async {},
            onEditPost: (_) async {},
            onDeletePost: (_) async {},
            onOpenAuthor: (_) {},
            onOpenPost: (_) async {},
            onOpenFeaturePost: (_) async {},
            onToggleSearchTag: (_) async {},
            onOpenCollection: (_) {},
            onShuffle: () {},
            onScanBarcode: () async {},
          ),
        ),
      ),
    );

    expect(find.text('취향 필터'), findsNothing);
    expect(find.text('이번 주 인기'), findsOneWidget);
    expect(find.text('남자들이 많이 고른 조합'), findsOneWidget);
    expect(find.text('여자들이 많이 고른 조합'), findsOneWidget);
    expect(find.text('새로 들어온 조합'), findsOneWidget);
    expect(find.text('PB로 만든 조합'), findsOneWidget);
    expect(find.text('다시 보는 조합'), findsOneWidget);
    expect(find.text('하트 성비'), findsNothing);
    expect(
      find.byKey(const Key('discovery-horizontal-이번 주 인기')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('discovery-topic-3')));
    await tester.pumpAndSettle();
    final collapsedHeight = tester
        .getSize(find.byKey(const Key('discovery-topic-3')))
        .height;
    await tester.tap(find.text('새로 들어온 조합'));
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(find.byKey(const Key('discovery-topic-3')))
        .height;
    expect(expandedHeight, greaterThan(collapsedHeight));
    await tester.ensureVisible(find.byTooltip('상세 필터'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('상세 필터'));
    await tester.pump();
    expect(find.text('취향 필터'), findsOneWidget);
    expect(find.text('섞기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
