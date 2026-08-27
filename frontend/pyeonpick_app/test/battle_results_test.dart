import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/battle_results.dart';
import 'package:pyeonpick_app/src/models/combination_battle.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
import 'package:pyeonpick_app/src/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const author = PyeonUser(
  id: 'author',
  username: 'author',
  password: '',
  nickname: '작성자',
);
const voter = PyeonUser(
  id: 'voter',
  username: 'voter',
  password: '',
  nickname: '참여자',
);

BattleMatchEntry fixture(
  String id, {
  String authorId = 'author',
  bool ended = true,
  int left = 12,
  int right = 2,
}) => BattleMatchEntry(
  id: id,
  title: '결과 $id',
  authorId: authorId,
  authorNickname: '작성자',
  leftPostId: '',
  rightPostId: '',
  createdAt: DateTime.now(),
  endsAt: DateTime.now().add(Duration(hours: ended ? -1 : 1)),
  leftColorValue: 0,
  rightColorValue: 0,
  leftCustomTitle: '우유 + 쿠키',
  rightCustomTitle: '라면 + 치즈',
  leftVoteCount: left,
  rightVoteCount: right,
  leftVoterIds: const ['voter'],
);

Widget screen(MockPostRepository repository, {PyeonUser user = author}) =>
    MaterialApp(
      home: Scaffold(
        body: ProfilePage(
          currentUser: user,
          repository: repository,
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
    );

class ScheduledResults extends MockPostRepository {
  int calls = 0;
  final DateTime ends = DateTime.now();
  @override
  Future<BattleResultsPage> fetchBattleResults(String userId) async {
    calls++;
    if (calls == 1) {
      return const BattleResultsPage(refreshAfter: Duration(milliseconds: 500));
    }
    return BattleResultsPage(
      results: [
        BattleResultEntry(
          id: 'just-ended',
          title: '방금 종료',
          endsAt: ends,
          leftTitle: '우유 + 쿠키',
          rightTitle: '라면 + 치즈',
          leftVotes: 12,
          rightVotes: 2,
          unread: true,
        ),
      ],
    );
  }

  @override
  Future<List<String>> markBattleResultsRead(
    String userId,
    List<String> ids,
  ) async => ids;
}

class DelayedResults extends MockPostRepository {
  final request = Completer<BattleResultsPage>();
  @override
  Future<BattleResultsPage> fetchBattleResults(String userId) =>
      userId == 'author'
      ? request.future
      : Future.value(const BattleResultsPage());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'only ended author results are returned; read state survives reload',
    () async {
      final state = CombinationBattleState(
        matches: [
          fixture('won'),
          fixture('active', ended: false),
          fixture('other', authorId: 'another'),
          fixture('tie', left: 2, right: 2),
          fixture('zero', left: 0, right: 0),
          fixture('right', left: 1, right: 3),
        ],
      );
      final repo = MockPostRepository(initialBattleState: state);
      final page = await repo.fetchBattleResults('author');
      expect(
        page.results.map((r) => r.id),
        unorderedEquals(['won', 'tie', 'zero', 'right']),
      );
      expect(
        page.results.firstWhere((r) => r.id == 'won').outcome,
        '우유 + 쿠키 승리',
      );
      expect(page.results.firstWhere((r) => r.id == 'tie').outcome, '무승부');
      expect(
        page.results.firstWhere((r) => r.id == 'zero').outcome,
        '투표 없이 종료',
      );
      expect(
        page.results.firstWhere((r) => r.id == 'right').outcome,
        '라면 + 치즈 승리',
      );
      expect((await repo.fetchBattleResults('voter')).results, isEmpty);
      expect(await repo.markBattleResultsRead('voter', ['won']), isEmpty);
      expect(
        await repo.markBattleResultsRead('author', ['won', 'other', 'active']),
        ['won'],
      );
      final reload = await MockPostRepository(
        initialBattleState: state,
      ).fetchBattleResults('author');
      expect(reload.results.firstWhere((r) => r.id == 'won').unread, isFalse);
      expect(reload.results.firstWhere((r) => r.id == 'tie').unread, isTrue);
    },
  );

  testWidgets(
    'profile badge opens a flat result list without a popup; reading clears the badge',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockPostRepository(
        initialBattleState: CombinationBattleState(matches: [fixture('won')]),
      );
      await tester.pumpWidget(screen(repo));
      await tester.pumpAndSettle();
      expect(find.text('픽 쇼츠 · 새 결과 1'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('12표'), findsNothing);
      await tester.tap(find.text('픽 쇼츠 · 새 결과 1'));
      await tester.pumpAndSettle();
      expect(find.text('픽 쇼츠'), findsOneWidget);
      expect(find.text('우유 + 쿠키 승리'), findsOneWidget);
      expect(find.text('12표'), findsOneWidget);
      expect(find.text('2표'), findsOneWidget);
      expect(
        (await repo.fetchBattleResults(author.id)).results.single.unread,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the server deadline triggers a fresh result and author badge', (
    tester,
  ) async {
    final repo = ScheduledResults();
    await tester.pumpWidget(screen(repo));
    await tester.pump();
    expect(find.text('픽 쇼츠 · 새 결과 1'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(repo.calls, 2);
    expect(find.text('픽 쇼츠 · 새 결과 1'), findsOneWidget);
    await tester.tap(find.text('픽 쇼츠 · 새 결과 1'));
    await tester.pumpAndSettle();
    expect(find.text('방금 종료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late responses from another account never enter the current profile',
    (tester) async {
      final repo = DelayedResults();
      await tester.pumpWidget(screen(repo));
      await tester.pumpWidget(screen(repo, user: voter));
      await tester.pump();
      repo.request.complete(
        BattleResultsPage(
          results: [
            BattleResultEntry(
              id: 'private',
              title: '다른 사람 결과',
              endsAt: DateTime.now(),
              leftTitle: 'A',
              rightTitle: 'B',
              leftVotes: 1,
              rightVotes: 0,
              unread: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('픽 쇼츠 · 새 결과 1'), findsNothing);
      await tester.tap(find.text('픽 쇼츠'));
      await tester.pumpAndSettle();
      expect(find.text('다른 사람 결과'), findsNothing);
      expect(find.textContaining('내가 올린 픽 쇼츠가 종료되면'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed requests have a retryable error instead of an empty result',
    (tester) async {
      final repo = DelayedResults();
      await tester.pumpWidget(screen(repo));
      await tester.tap(find.text('픽 쇼츠'));
      repo.request.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('결과를 불러오지 못했어요. 새로고침해 주세요.'), findsOneWidget);
      expect(find.textContaining('내가 올린 픽 쇼츠가 종료되면'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
