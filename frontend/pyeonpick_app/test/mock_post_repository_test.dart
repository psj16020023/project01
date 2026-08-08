import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/sort_mode.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('popular badge uses enough likes with a clear positive ratio', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MockPostRepository();

    final page = await repository.fetchPosts(
      sortMode: SortMode.latest,
      currentUserId: 'tester',
      limit: 100,
    );
    final popularIds = page.posts
        .where((post) => post.topFiveEnteredAt != null)
        .map((post) => post.id)
        .toSet();

    expect(popularIds, contains('seed-2026-01'));
    expect(popularIds.length, 5);
    expect(popularIds, isNot(contains('seed-2026-07')));
    expect(popularIds, isNot(contains('seed-2026-08')));
  });

  test('mock likes survive repository reload for the same user', () async {
    SharedPreferences.setMockInitialValues({});
    final firstRepository = MockPostRepository();

    final liked = await firstRepository.toggleLike('seed-2026-01', 'tester');
    expect(liked.likedByMe, isTrue);

    final reloadedRepository = MockPostRepository();
    final page = await reloadedRepository.fetchPosts(
      sortMode: SortMode.latest,
      currentUserId: 'tester',
      limit: 20,
    );
    final restored = page.posts.firstWhere((post) => post.id == 'seed-2026-01');

    expect(restored.likedByMe, isTrue);
    expect(restored.likes, liked.likes);
  });
}
