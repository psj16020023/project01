import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pyeonpick_app/src/models/combination_battle.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
import 'package:pyeonpick_app/src/screens/combination_battle_screen.dart';
import 'package:pyeonpick_app/src/services/bot_situation_analyzer.dart';
import 'package:shared_preferences/shared_preferences.dart';

BattleMatchEntry match(String id) => BattleMatchEntry(
  id: id,
  title: '투표 $id',
  authorId: 'author',
  authorNickname: '작성자',
  leftPostId: '',
  rightPostId: '',
  createdAt: DateTime.now(),
  endsAt: DateTime.now().add(const Duration(hours: 1)),
  leftColorValue: 0xFF49A9D8,
  rightColorValue: 0xFFFF8B64,
  leftCustomTitle: '우유 + 쿠키',
  rightCustomTitle: '라면 + 치즈',
  leftVoterIds: List.generate(11, (index) => 'left-$index'),
  rightVoterIds: const ['right-1', 'right-2'],
);

void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'vertical votes reveal 12:2 for one second then stay hidden after reload',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MockPostRepository(
        initialBattleState: CombinationBattleState(
          matches: [match('first'), match('second')],
        ),
      );
      Widget screen(MockPostRepository repo) => MaterialApp(
        home: Scaffold(
          body: CombinationBattleScreen(
            currentUser: const PyeonUser(
              id: 'me',
              username: 'test',
              password: '',
              nickname: '테스터',
            ),
            posts: const [],
            repository: repo,
            onUserChanged: (_) async {},
            onOpenPost: (_) async {},
            onOpenAuthor: (_, _) async {},
          ),
        ),
      );
      await tester.pumpWidget(screen(repository));
      await tester.pump();
      final votedTitle = tester
          .widget<Text>(
            find
                .textContaining(RegExp(r'^투표 (first|second)$'))
                .hitTestable()
                .first,
          )
          .data!;
      final votedId = votedTitle.split(' ').last;
      final nextTitle = votedId == 'first' ? '투표 second' : '투표 first';
      expect(find.byKey(const Key('battle-vertical-options')), findsWidgets);
      expect(find.text('11표'), findsNothing);
      expect(find.text('2표'), findsNothing);
      await tester.tap(find.byKey(const Key('battle-vote-left')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('12표'), findsOneWidget);
      expect(find.text('2표'), findsOneWidget);
      expect(find.text('더 많이 선택됨'), findsOneWidget);
      await tester.tap(find.byKey(const Key('battle-vote-right')).first);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('12표'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text(votedTitle), findsNothing);
      expect(find.text(nextTitle), findsOneWidget);
      final stored = (await repository.fetchBattleState()).matches.firstWhere(
        (match) => match.id == votedId,
      );
      expect(stored.leftVotes, 12);
      expect(stored.rightVotes, 2);
      expect(stored.voteSideOf('me'), BattleVoteSide.left);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(MockPostRepository()));
      await tester.pump();
      expect(find.text(votedTitle), findsNothing);
      expect(find.text(nextTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('deleting the last mock match does not seed it again', () async {
    final repo = MockPostRepository(
      initialBattleState: CombinationBattleState(matches: [match('last')]),
    );
    await repo.deleteBattle('last');
    expect((await MockPostRepository().fetchBattleState()).matches, isEmpty);
  });

  test(
    'learned taste is a small bonus and scarce votes are not over-weighted',
    () {
      const scarce = BotVotePreferences(
        sampleCount: 1,
        categoryWeights: {'달달': 1},
      );
      const established = BotVotePreferences(
        sampleCount: 10,
        categoryWeights: {'달달': 1, '짭짤': 1, '야식': 1},
      );
      expect(scarce.score(['달달']), 1);
      expect(established.score(['달달', '짭짤', '야식']), 6);
      expect(established.score(['새콤']), 0);
    },
  );
}
