import 'post.dart';
import 'pyeon_user.dart';

class CommunityTitleDefinition {
  const CommunityTitleDefinition({
    required this.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.category,
    required this.rank,
    required this.primaryColorValue,
    required this.secondaryColorValue,
  });

  final String key;
  final String icon;
  final String label;
  final String description;
  final String category;
  final int rank;
  final int primaryColorValue;
  final int secondaryColorValue;
}

class CommunityTitleAward {
  const CommunityTitleAward({
    required this.definition,
    required this.progress,
    required this.goal,
  });

  final CommunityTitleDefinition definition;
  final int progress;
  final int goal;
}

const List<CommunityTitleDefinition> communityTitleDefinitions =
    <CommunityTitleDefinition>[
      CommunityTitleDefinition(
        key: 'share-1',
        icon: '🌱',
        label: '첫 조합',
        description: '커뮤니케이션에 조합 공유 1개 달성',
        category: '조합 공유',
        rank: 1,
        primaryColorValue: 0xFF4AA84E,
        secondaryColorValue: 0xFFDFF6DE,
      ),
      CommunityTitleDefinition(
        key: 'share-5',
        icon: '🍜',
        label: '꿀조합 입문자',
        description: '커뮤니케이션에 조합 공유 5개 달성',
        category: '조합 공유',
        rank: 2,
        primaryColorValue: 0xFFEA7C2D,
        secondaryColorValue: 0xFFFFECD9,
      ),
      CommunityTitleDefinition(
        key: 'share-10',
        icon: '🧪',
        label: '조합 연구원',
        description: '커뮤니케이션에 조합 공유 10개 달성',
        category: '조합 공유',
        rank: 3,
        primaryColorValue: 0xFF2F7EF0,
        secondaryColorValue: 0xFFE1EEFF,
      ),
      CommunityTitleDefinition(
        key: 'share-20',
        icon: '👨‍🍳',
        label: '편의점 셰프',
        description: '커뮤니케이션에 조합 공유 20개 달성',
        category: '조합 공유',
        rank: 4,
        primaryColorValue: 0xFF9C4D1A,
        secondaryColorValue: 0xFFF8E6D8,
      ),
      CommunityTitleDefinition(
        key: 'review-1',
        icon: '🍽',
        label: '맛 입문자',
        description: '먹어봄 후기 1회 달성',
        category: '후기(먹어봄)',
        rank: 1,
        primaryColorValue: 0xFF6D5CE8,
        secondaryColorValue: 0xFFEBE7FF,
      ),
      CommunityTitleDefinition(
        key: 'review-5',
        icon: '😋',
        label: '한입좌',
        description: '먹어봄 후기 5회 달성',
        category: '후기(먹어봄)',
        rank: 2,
        primaryColorValue: 0xFFE84C7E,
        secondaryColorValue: 0xFFFFE2EC,
      ),
      CommunityTitleDefinition(
        key: 'review-10',
        icon: '📝',
        label: '시식단',
        description: '먹어봄 후기 10회 달성',
        category: '후기(먹어봄)',
        rank: 3,
        primaryColorValue: 0xFF0F8D7A,
        secondaryColorValue: 0xFFDDF7F1,
      ),
      CommunityTitleDefinition(
        key: 'review-30',
        icon: '🧭',
        label: '미식 탐험가',
        description: '먹어봄 후기 30회 달성',
        category: '후기(먹어봄)',
        rank: 4,
        primaryColorValue: 0xFF146C94,
        secondaryColorValue: 0xFFDDF1FA,
      ),
      CommunityTitleDefinition(
        key: 'review-50',
        icon: '👑',
        label: '편의점 미식가',
        description: '먹어봄 후기 50회 달성',
        category: '후기(먹어봄)',
        rank: 5,
        primaryColorValue: 0xFFAF7D11,
        secondaryColorValue: 0xFFFFF1CC,
      ),
      CommunityTitleDefinition(
        key: 'like-10',
        icon: '💫',
        label: '관심받는 조합',
        description: '작성한 게시글 중 좋아요 10개 달성',
        category: '인기 조합',
        rank: 2,
        primaryColorValue: 0xFF536DFE,
        secondaryColorValue: 0xFFE4E9FF,
      ),
      CommunityTitleDefinition(
        key: 'like-30',
        icon: '🔥',
        label: '인기 조합',
        description: '작성한 게시글 중 좋아요 30개 달성',
        category: '인기 조합',
        rank: 3,
        primaryColorValue: 0xFFEF5D28,
        secondaryColorValue: 0xFFFFE4D8,
      ),
      CommunityTitleDefinition(
        key: 'like-50',
        icon: '🚀',
        label: '화제의 조합',
        description: '작성한 게시글 중 좋아요 50개 달성',
        category: '인기 조합',
        rank: 4,
        primaryColorValue: 0xFFAB2AE6,
        secondaryColorValue: 0xFFF3E2FF,
      ),
      CommunityTitleDefinition(
        key: 'tag-master',
        icon: '🏷',
        label: '꿀조합 마스터',
        description: '꿀조합 태그 감성이 진한 게시글 3개 달성',
        category: '인기 태그',
        rank: 3,
        primaryColorValue: 0xFF00796B,
        secondaryColorValue: 0xFFDCF7EF,
      ),
    ];

CommunityTitleDefinition? communityTitleByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final definition in communityTitleDefinitions) {
    if (definition.key == key) return definition;
  }
  return null;
}

List<CommunityTitleAward> communityTitlesForUser(
  PyeonUser user,
  List<Post> posts,
) => communityTitlesForAuthor(user.id, posts);

List<CommunityTitleAward> communityTitlesForAuthor(
  String authorId,
  List<Post> posts,
) {
  final authoredPosts = posts
      .where((post) => post.authorId == authorId)
      .toList();
  final authoredCount = authoredPosts.length;
  final reviewCount = posts
      .expand((post) => post.reviews)
      .where((review) => review.authorId == authorId)
      .length;
  final bestLikes = authoredPosts.fold<int>(
    0,
    (best, post) => post.likes > best ? post.likes : best,
  );
  final honeyTagCount = authoredPosts.where((post) {
    final text = '${post.title} ${post.content} ${post.categories.join(' ')}';
    return text.contains('꿀조합');
  }).length;

  final awards = <CommunityTitleAward>[];

  void unlock(String key, int progress, int goal) {
    final definition = communityTitleByKey(key);
    if (definition == null) return;
    awards.add(
      CommunityTitleAward(
        definition: definition,
        progress: progress,
        goal: goal,
      ),
    );
  }

  if (authoredCount >= 1) unlock('share-1', authoredCount, 1);
  if (authoredCount >= 5) unlock('share-5', authoredCount, 5);
  if (authoredCount >= 10) unlock('share-10', authoredCount, 10);
  if (authoredCount >= 20) unlock('share-20', authoredCount, 20);

  if (reviewCount >= 1) unlock('review-1', reviewCount, 1);
  if (reviewCount >= 5) unlock('review-5', reviewCount, 5);
  if (reviewCount >= 10) unlock('review-10', reviewCount, 10);
  if (reviewCount >= 30) unlock('review-30', reviewCount, 30);
  if (reviewCount >= 50) unlock('review-50', reviewCount, 50);

  if (bestLikes >= 10) unlock('like-10', bestLikes, 10);
  if (bestLikes >= 30) unlock('like-30', bestLikes, 30);
  if (bestLikes >= 50) unlock('like-50', bestLikes, 50);

  if (honeyTagCount >= 3) unlock('tag-master', honeyTagCount, 3);

  return awards;
}

bool userHasCommunityTitle(PyeonUser user, List<Post> posts, String key) {
  return communityTitlesForAuthor(
    user.id,
    posts,
  ).any((award) => award.definition.key == key);
}

List<CommunityTitleDefinition> unlockedCommunityTitlesForUser(
  PyeonUser user,
  List<Post> posts,
) {
  return communityTitlesForUser(
    user,
    posts,
  ).map((award) => award.definition).toList();
}

CommunityTitleDefinition? selectedCommunityTitleForUser(
  PyeonUser user,
  List<Post> posts,
) {
  final unlocked = unlockedCommunityTitlesForUser(user, posts);
  final selected = communityTitleByKey(user.selectedCommunityTitleKey);
  if (selected != null &&
      unlocked.any((definition) => definition.key == selected.key)) {
    return selected;
  }
  return null;
}

bool userMeetsCommunityTitleRequirement(
  PyeonUser user,
  List<Post> posts,
  String requiredKey,
) {
  final required = communityTitleByKey(requiredKey);
  if (required == null) return true;
  return unlockedCommunityTitlesForUser(
    user,
    posts,
  ).any((definition) => definition.rank >= required.rank);
}

const List<String> communityTitleCategoryOrder = <String>[
  '조합 공유',
  '후기(먹어봄)',
  '인기 조합',
  '인기 태그',
];
