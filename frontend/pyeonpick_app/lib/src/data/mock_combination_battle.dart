import '../models/combination_battle.dart';
import '../models/post.dart';

CombinationBattleState mockCombinationBattleState(
  List<Post> posts, {
  required DateTime now,
}) {
  if (posts.length < 2) return const CombinationBattleState();

  final matches = <BattleMatchEntry>[];
  for (
    var index = 0;
    index + 1 < posts.length && matches.length < 4;
    index += 2
  ) {
    final left = posts[index];
    final right = posts[index + 1];
    matches.add(
      BattleMatchEntry(
        id: 'battle-${now.millisecondsSinceEpoch}-$index',
        title: index == 0
            ? '야식으로 더 끌리는 조합은?'
            : index == 2
            ? '재구매하고 싶은 편의점 조합은?'
            : '오늘 한 끼로 고른다면?',
        authorId: left.authorId,
        authorNickname: left.authorNickname,
        leftPostId: left.id,
        rightPostId: right.id,
        leftColorValue: index.isEven ? 0xFFC91F2D : 0xFFBE4C1B,
        rightColorValue: index.isEven ? 0xFF2E68D3 : 0xFF4A5BD0,
        endsAt: now.add(Duration(days: 2 + matches.length)),
        createdAt: now.subtract(Duration(days: matches.length)),
        leftVoterIds: List<String>.generate(
          12 + index,
          (i) => 'left-$index-$i',
        ),
        rightVoterIds: List<String>.generate(
          9 + index,
          (i) => 'right-$index-$i',
        ),
      ),
    );
  }

  return CombinationBattleState(matches: matches);
}
