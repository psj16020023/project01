import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/sort_mode.dart';
import 'package:pyeonpick_app/src/repositories/mock_post_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('picked-author filtering is applied before pagination', () async {
    final repository = MockPostRepository();
    final catalog = await repository.fetchPostCatalog();
    final authorId = catalog.first.authorId;
    final page = await repository.fetchPosts(
      authorIds: [authorId],
      limit: 2,
      sortMode: SortMode.latest,
    );
    expect(page.posts, isNotEmpty);
    expect(page.posts.every((post) => post.authorId == authorId), isTrue);
  });

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
    final target = (await firstRepository.fetchPostCatalog()).firstWhere(
      (post) => post.id == 'seed-2026-01',
    );

    final liked = await firstRepository.toggleLike(target, 'tester');
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

  test('맛 표현으로 제목 외의 내용도 검색한다', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MockPostRepository();

    final page = await repository.fetchPosts(
      query: '매운맛',
      sortMode: SortMode.latest,
      currentUserId: 'tester',
      limit: 100,
    );

    expect(page.posts.map((post) => post.id), contains('seed-2026-01'));
    expect(page.posts.map((post) => post.id), contains('seed-2026-06'));
  });

  test('맛 필터로 본문의 맛 표현을 찾는다', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MockPostRepository();

    final page = await repository.fetchPosts(
      selectedTags: const <String>['매콤'],
      sortMode: SortMode.latest,
      currentUserId: 'tester',
      limit: 100,
    );

    expect(page.posts.map((post) => post.id), contains('seed-2026-01'));
    expect(page.posts.map((post) => post.id), contains('seed-2026-06'));
  });
}
