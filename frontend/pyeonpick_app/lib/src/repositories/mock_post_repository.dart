import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/mock_posts.dart';
import '../data/mock_combination_battle.dart';
import '../data/product_catalog.dart' as catalog;
import '../models/combination_battle.dart';
import '../models/battle_results.dart';
import '../models/post.dart';
import '../models/post_feature_index.dart';
import '../models/post_draft.dart';
import '../models/post_page.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'post_repository.dart';

class MockPostRepository implements PostRepository {
  MockPostRepository({CombinationBattleState? initialBattleState})
    : _posts = mockPosts.map((post) => post.copyWith()).toList(),
      _battleState = initialBattleState ?? const CombinationBattleState(),
      _battlesLoaded = initialBattleState != null {
    _applyTopFiveBadges();
  }

  final List<Post> _posts;
  CombinationBattleState _battleState;
  bool _battlesLoaded;
  Future<void>? _battleLoading;
  static const _battleStorageKey = 'pyeonpick_mock_battles_v1';
  static const _storageKey = 'pyeonpick_mock_posts_v3';
  static const _reactionStorageKey = 'pyeonpick_mock_post_reactions_v1';
  final Map<String, Set<String>> _likedPostIdsByUser = <String, Set<String>>{};
  final Map<String, Set<String>> _dislikedPostIdsByUser =
      <String, Set<String>>{};
  bool _loaded = false;

  @override
  Future<BattleResultsPage> fetchBattleResults(String currentUserId) async {
    final state = await fetchBattleState();
    final prefs = await SharedPreferences.getInstance();
    final read =
        prefs.getStringList('pyeonpick_battle_results_read_$currentUserId') ??
        [];
    final now = DateTime.now();
    final owned = state.matches.where(
      (match) => match.authorId == currentUserId && match.endsAt != null,
    );
    final ended = owned.where((match) => !match.endsAt!.isAfter(now)).toList()
      ..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
    final upcoming = owned.where((match) => match.endsAt!.isAfter(now)).toList()
      ..sort((a, b) => a.endsAt!.compareTo(b.endsAt!));
    String title(String? custom, String postId, String fallback) =>
        custom ??
        _posts.where((post) => post.id == postId).firstOrNull?.title ??
        fallback;
    return BattleResultsPage(
      refreshAfter: upcoming.isEmpty
          ? const Duration(seconds: 15)
          : Duration(
              milliseconds:
                  (upcoming.first.endsAt!.difference(now).inMilliseconds + 200)
                      .clamp(300, 15000),
            ),
      results: ended
          .map(
            (match) => BattleResultEntry(
              id: match.id,
              title: match.title,
              endsAt: match.endsAt!,
              leftTitle: title(
                match.leftCustomTitle,
                match.leftPostId,
                '첫 번째 조합',
              ),
              rightTitle: title(
                match.rightCustomTitle,
                match.rightPostId,
                '두 번째 조합',
              ),
              leftVotes: match.leftVotes,
              rightVotes: match.rightVotes,
              unread: !read.contains(match.id),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<List<String>> markBattleResultsRead(
    String currentUserId,
    List<String> matchIds,
  ) async {
    final page = await fetchBattleResults(currentUserId);
    final owned = page.results
        .where((result) => matchIds.contains(result.id))
        .map((result) => result.id)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    final key = 'pyeonpick_battle_results_read_$currentUserId';
    await prefs.setStringList(
      key,
      {...?prefs.getStringList(key), ...owned}.toList(),
    );
    return owned;
  }

  @override
  Future<CombinationBattleState> fetchBattleState() async {
    await (_battleLoading ??= _loadBattles());
    return _battleState;
  }

  @override
  Future<List<BattleMatchEntry>> fetchBattleHighlights() async {
    final state = await fetchBattleState();
    return state.matches
        .where((match) => match.totalVotes >= 8 && match.isExpired)
        .toList()
      ..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
  }

  @override
  Future<BattleMatchEntry> createBattle(BattleMatchEntry match) async {
    await fetchBattleState();
    _battleState = _battleState.copyWith(
      matches: <BattleMatchEntry>[match, ..._battleState.matches],
    );
    await _persistBattles();
    return match;
  }

  @override
  Future<BattleMatchEntry> castBattleVote(
    String matchId,
    BattleVoteSide side,
    String currentUserId,
  ) async {
    await fetchBattleState();
    final index = _battleState.matches.indexWhere(
      (match) => match.id == matchId,
    );
    if (index < 0) throw StateError('픽 쇼츠를 찾을 수 없어요.');
    final match = _battleState.matches[index];
    final updated = match.castVote(currentUserId, side);
    final matches = [..._battleState.matches]..[index] = updated;
    _battleState = _battleState.copyWith(matches: matches);
    await _persistBattles();
    return updated;
  }

  @override
  Future<BattleMatchEntry> updateBattle(BattleMatchEntry match) async {
    await fetchBattleState();
    final matches = _battleState.matches
        .map((item) => item.id == match.id ? match : item)
        .toList();
    _battleState = _battleState.copyWith(matches: matches);
    await _persistBattles();
    return match;
  }

  @override
  Future<void> deleteBattle(String matchId) async {
    await fetchBattleState();
    _battleState = _battleState.copyWith(
      matches: _battleState.matches
          .where((match) => match.id != matchId)
          .toList(),
    );
    await _persistBattles();
  }

  Future<void> _loadBattles() async {
    if (_battlesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_battleStorageKey);
    _battleState = raw == null
        ? mockCombinationBattleState(_posts, now: DateTime.now())
        : CombinationBattleState.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
    _battlesLoaded = true;
    await _persistBattles();
  }

  Future<void> _persistBattles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_battleStorageKey, jsonEncode(_battleState.toJson()));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final items = jsonDecode(raw) as List<dynamic>;
      _posts
        ..clear()
        ..addAll(
          items.map((item) => Post.fromJson(item as Map<String, dynamic>)),
        );

      final reactionRaw = prefs.getString(_reactionStorageKey);
      if (reactionRaw != null && reactionRaw.isNotEmpty) {
        _loadReactionMap(jsonDecode(reactionRaw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Keep seeded posts when browser storage is unavailable or invalid.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_posts.map((post) => post.toJson()).toList()),
      );
      await prefs.setString(
        _reactionStorageKey,
        jsonEncode(_serializeReactionMap()),
      );
    } catch (_) {
      // The in-memory state remains usable for the current session.
    }
  }

  void _loadReactionMap(Map<String, dynamic> json) {
    _likedPostIdsByUser
      ..clear()
      ..addAll(_decodeReactionGroup(json['liked']));
    _dislikedPostIdsByUser
      ..clear()
      ..addAll(_decodeReactionGroup(json['disliked']));
  }

  Map<String, Set<String>> _decodeReactionGroup(Object? raw) {
    if (raw is! Map) return <String, Set<String>>{};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        (value as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .toSet(),
      ),
    );
  }

  Map<String, dynamic> _serializeReactionMap() {
    return <String, dynamic>{
      'liked': _likedPostIdsByUser.map(
        (userId, ids) => MapEntry(userId, ids.toList()),
      ),
      'disliked': _dislikedPostIdsByUser.map(
        (userId, ids) => MapEntry(userId, ids.toList()),
      ),
    };
  }

  Set<String> _likedIdsFor(String userId) {
    return _likedPostIdsByUser.putIfAbsent(userId, () => <String>{});
  }

  Set<String> _dislikedIdsFor(String userId) {
    return _dislikedPostIdsByUser.putIfAbsent(userId, () => <String>{});
  }

  Post _withViewerReaction(Post post, String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty) {
      return post.copyWith(likedByMe: false, dislikedByMe: false);
    }
    return post.copyWith(
      likedByMe: _likedIdsFor(currentUserId).contains(post.id),
      dislikedByMe: _dislikedIdsFor(currentUserId).contains(post.id),
    );
  }

  @override
  Future<Post> addReview(String id, PostReview review) async {
    await _ensureLoaded();
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) throw StateError('게시글을 찾을 수 없어요.');
    _posts[index] = _posts[index].copyWith(
      reviews: <PostReview>[..._posts[index].reviews, review],
    );
    await _persist();
    return _posts[index];
  }

  @override
  Future<Post> updateReview(String postId, PostReview review) async {
    await _ensureLoaded();
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) throw StateError('게시글을 찾을 수 없어요.');
    _posts[index] = _posts[index].copyWith(
      reviews: _posts[index].reviews
          .map((item) => item.id == review.id ? review : item)
          .toList(),
    );
    await _persist();
    return _posts[index];
  }

  @override
  Future<Post> deleteReview(
    String postId,
    String reviewId, {
    required String authorId,
  }) async {
    await _ensureLoaded();
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) throw StateError('게시글을 찾을 수 없어요.');
    _posts[index] = _posts[index].copyWith(
      reviews: _posts[index].reviews
          .where((item) => !(item.id == reviewId && item.authorId == authorId))
          .toList(),
    );
    await _persist();
    return _posts[index];
  }

  @override
  Future<Post> addComment(
    String id,
    String text, {
    required String authorId,
    required String authorNickname,
  }) async {
    await _ensureLoaded();
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) {
      throw StateError('게시글을 찾을 수 없어요.');
    }

    final post = _posts[index];
    _posts[index] = post.copyWith(
      comments: [
        ...post.comments,
        PostComment(
          authorId: authorId,
          authorNickname: authorNickname,
          text: text.trim(),
          createdAt: DateTime.now(),
        ),
      ],
    );
    return _posts[index];
  }

  @override
  Future<void> createPost(PostDraft draft) async {
    await _ensureLoaded();
    final now = DateTime.now();
    _posts.insert(
      0,
      Post(
        id: 'local-${now.microsecondsSinceEpoch}',
        authorId: draft.authorId,
        authorNickname: draft.authorNickname,
        title: draft.title.isEmpty ? '제목 없는 꿀조합' : draft.title,
        content: draft.content,
        priceMin: draft.priceMin,
        priceMax: draft.priceMax,
        categories: draft.categories,
        likes: 0,
        dislikes: 0,
        comments: const [],
        createdAt: now,
        imageData: draft.imageBytes.isEmpty
            ? null
            : base64Encode(draft.imageBytes.first),
        imageUrl: null,
        imageDatas: draft.imageBytes.map(base64Encode).toList(),
        imageUrls: draft.imageUrls,
        details: draft.details,
        likedByMe: false,
        dislikedByMe: false,
        topFiveEnteredAt: null,
        topWorstEnteredAt: null,
        calories: draft.calories,
        rating: draft.rating,
        reviews: const <PostReview>[],
      ),
    );
    _applyTopFiveBadges();
    await _persist();
  }

  @override
  Future<void> deletePost(String id, String authorId) async {
    await _ensureLoaded();
    _posts.removeWhere((post) => post.id == id && post.authorId == authorId);
    _applyTopFiveBadges();
    await _persist();
  }

  @override
  Future<PostPage> fetchPosts({
    String? query,
    List<String>? selectedTags,
    int? minPrice,
    int? maxPrice,
    String? likedGenderMajority,
    List<String>? authorIds,
    String? currentUserId,
    String? cursor,
    int? limit,
    required SortMode sortMode,
  }) async {
    await _ensureLoaded();
    final normalized = (query ?? '').trim().toLowerCase();

    final filtered = _posts.where((post) {
      final tasteAliases = <String, List<String>>{
        '달달': const ['달달', '달콤', '단맛', '단 맛', '단거'],
        '매콤': const ['매콤', '매운맛', '매운 맛', '맵단'],
        '새콤': const ['새콤', '상큼', '신맛', '신 맛', '시다'],
        '짭짤': const ['짭짤', '짠맛', '짠 맛', '짜다'],
      };
      final expandedQueries = <String>{normalized};
      for (final entry in tasteAliases.entries) {
        if (entry.value.any(normalized.contains)) {
          expandedQueries.add(entry.key);
          expandedQueries.addAll(entry.value);
        }
      }
      final searchableText = <String>[
        post.title,
        post.content,
        ...post.categories,
        ...post.details.usedProducts,
        ...post.details.eatingSteps,
        ...post.details.tips,
        ...post.details.situationTags,
        ...post.details.reviewPoints,
        ...post.reviews.expand(
          (review) => <String>[review.text, ...review.tags],
        ),
      ].join(' ').toLowerCase();
      final matchesQuery = normalized.isEmpty
          ? true
          : normalized.startsWith('#')
          ? post.categories.any(
              (category) =>
                  category.toLowerCase().contains(normalized.substring(1)),
            )
          : expandedQueries.any(searchableText.contains);
      final matchesTags = selectedTags == null || selectedTags.isEmpty
          ? true
          : selectedTags.every((tag) {
              final normalizedTag = tag.toLowerCase();
              final tagQueries = <String>{normalizedTag};
              for (final entry in tasteAliases.entries) {
                if (entry.key == normalizedTag ||
                    entry.value.any(normalizedTag.contains)) {
                  tagQueries.add(entry.key);
                  tagQueries.addAll(entry.value);
                }
              }
              return tagQueries.any(searchableText.contains);
            });

      final matchesMin = minPrice == null || post.priceMax >= minPrice;
      final matchesMax = maxPrice == null || post.priceMin <= maxPrice;
      final matchesAuthor =
          authorIds == null ||
          authorIds.isEmpty ||
          authorIds.contains(post.authorId);
      return matchesQuery &&
          matchesTags &&
          matchesMin &&
          matchesMax &&
          matchesAuthor;
    }).toList();

    filtered.sort((a, b) {
      if (sortMode == SortMode.popular) {
        return b.likes - a.likes != 0
            ? b.likes - a.likes
            : b.createdAt.compareTo(a.createdAt);
      }
      if (sortMode == SortMode.worst) {
        return b.dislikes - a.dislikes != 0
            ? b.dislikes - a.dislikes
            : b.createdAt.compareTo(a.createdAt);
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    final pageSize = limit ?? 6;
    final startIndex = int.tryParse(cursor ?? '') ?? 0;
    final endIndex = (startIndex + pageSize) > filtered.length
        ? filtered.length
        : (startIndex + pageSize);
    final pageItems = filtered
        .sublist(startIndex, endIndex)
        .map((post) => _withViewerReaction(post, currentUserId))
        .toList();
    return PostPage(
      posts: pageItems,
      hasMore: endIndex < filtered.length,
      nextCursor: endIndex < filtered.length ? '$endIndex' : null,
    );
  }

  @override
  Future<List<PostFeatureInfo>> fetchPostFeatureIndex() async {
    await _ensureLoaded();
    final items = _posts.map(PostFeatureInfo.fromPost).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<List<Post>> fetchPostCatalog({String? currentUserId}) async {
    await _ensureLoaded();
    return _posts
        .map((post) => _withViewerReaction(post, currentUserId))
        .toList();
  }

  @override
  Future<PostAudienceStats> fetchPostAudienceStats(String postId) async {
    await _ensureLoaded();
    return const PostAudienceStats(maleCount: 0, femaleCount: 0);
  }

  @override
  Future<Post> toggleLike(Post target, String currentUserId) async {
    await _ensureLoaded();
    final id = target.id;
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) {
      throw StateError('게시글을 찾을 수 없어요.');
    }

    final post = _posts[index];
    final likedIds = _likedIdsFor(currentUserId);
    final dislikedIds = _dislikedIdsFor(currentUserId);
    final wasLiked = likedIds.contains(id);
    final wasDisliked = dislikedIds.contains(id);
    final toggled = !wasLiked;
    if (toggled) {
      likedIds.add(id);
      dislikedIds.remove(id);
    } else {
      likedIds.remove(id);
    }
    _posts[index] = post.copyWith(
      likedByMe: toggled,
      likes: toggled ? post.likes + 1 : (post.likes > 0 ? post.likes - 1 : 0),
      dislikedByMe: false,
      dislikes: toggled && wasDisliked
          ? (post.dislikes > 0 ? post.dislikes - 1 : 0)
          : post.dislikes,
    );
    _applyTopFiveBadges();
    await _persist();
    return _withViewerReaction(_posts[index], currentUserId);
  }

  @override
  Future<Post> toggleDislike(Post target, String currentUserId) async {
    await _ensureLoaded();
    final id = target.id;
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) {
      throw StateError('게시글을 찾을 수 없어요.');
    }

    final post = _posts[index];
    final likedIds = _likedIdsFor(currentUserId);
    final dislikedIds = _dislikedIdsFor(currentUserId);
    final wasDisliked = dislikedIds.contains(id);
    final wasLiked = likedIds.contains(id);
    final toggled = !wasDisliked;
    if (toggled) {
      dislikedIds.add(id);
      likedIds.remove(id);
    } else {
      dislikedIds.remove(id);
    }
    _posts[index] = post.copyWith(
      dislikedByMe: toggled,
      dislikes: toggled
          ? post.dislikes + 1
          : (post.dislikes > 0 ? post.dislikes - 1 : 0),
      likedByMe: false,
      likes: toggled && wasLiked
          ? (post.likes > 0 ? post.likes - 1 : 0)
          : post.likes,
    );
    _applyTopFiveBadges();
    await _persist();
    return _withViewerReaction(_posts[index], currentUserId);
  }

  @override
  Future<ProductLookupResult> lookupProductByBarcode(String barcode) async {
    final result = catalog.ProductCatalog.resolve(barcode);
    return ProductLookupResult(
      officialName: result.productName,
      scannedCode: result.scannedCode,
      source: result.matchedFromCatalog ? 'mock-catalog' : 'manual-needed',
      cached: true,
      tentative: !result.matchedFromCatalog,
      store: '편pick 샘플',
      warning: result.matchedFromCatalog
          ? null
          : '샘플 카탈로그에 없는 상품이라 직접 확인이 필요해요.',
    );
  }

  @override
  Future<void> updatePost(String id, PostDraft draft) async {
    await _ensureLoaded();
    final index = _posts.indexWhere(
      (post) => post.id == id && post.authorId == draft.authorId,
    );
    if (index < 0) return;

    final existing = _posts[index];
    _posts[index] = existing.copyWith(
      title: draft.title.isEmpty ? '제목 없는 꿀조합' : draft.title,
      content: draft.content,
      priceMin: draft.priceMin,
      priceMax: draft.priceMax,
      categories: draft.categories,
      imageData: draft.imageBytes.isEmpty
          ? existing.imageData
          : base64Encode(draft.imageBytes.first),
      imageDatas: draft.imageBytes.isEmpty
          ? existing.imageDatas
          : draft.imageBytes.map(base64Encode).toList(),
      imageUrls: draft.imageUrls.isNotEmpty
          ? draft.imageUrls
          : draft.imageBytes.isEmpty
          ? existing.imageUrls
          : const <String>[],
      details: draft.details,
      authorNickname: draft.authorNickname,
      calories: draft.calories,
      rating: draft.rating,
    );
    _applyTopFiveBadges();
    await _persist();
  }

  void _applyTopFiveBadges() {
    final ranked = _posts.where(_qualifiesForPopularBadge).toList()
      ..sort(
        (a, b) => b.likes != a.likes
            ? b.likes.compareTo(a.likes)
            : b.createdAt.compareTo(a.createdAt),
      );
    final topIds = ranked.take(5).map((post) => post.id).toSet();
    final worstRanked = _posts.where(_qualifiesForWorstBadge).toList()
      ..sort(
        (a, b) => b.dislikes - a.dislikes != 0
            ? b.dislikes - a.dislikes
            : _dislikeRatio(b).compareTo(_dislikeRatio(a)) != 0
            ? _dislikeRatio(b).compareTo(_dislikeRatio(a))
            : b.createdAt.compareTo(a.createdAt),
      );
    final worstIds = worstRanked.take(5).map((post) => post.id).toSet();
    final now = DateTime.now();

    for (var index = 0; index < _posts.length; index += 1) {
      final post = _posts[index];
      var next = post;
      if (topIds.contains(post.id) && post.topFiveEnteredAt == null) {
        next = next.copyWith(topFiveEnteredAt: now);
      } else if (!topIds.contains(post.id) && post.topFiveEnteredAt != null) {
        next = next.copyWith(clearTopFiveEnteredAt: true);
      }
      if (worstIds.contains(post.id) && post.topWorstEnteredAt == null) {
        next = next.copyWith(topWorstEnteredAt: now);
      } else if (!worstIds.contains(post.id) &&
          post.topWorstEnteredAt != null) {
        next = next.copyWith(clearTopWorstEnteredAt: true);
      }
      _posts[index] = next;
    }
  }

  bool _qualifiesForPopularBadge(Post post) {
    if (post.likes < 10) return false;
    return post.likes >= math.max(1, post.dislikes * 3);
  }

  double _dislikeRatio(Post post) {
    final total = post.likes + post.dislikes;
    return total <= 0 ? 0 : post.dislikes / total;
  }

  bool _qualifiesForWorstBadge(Post post) {
    if (post.dislikes < 8) return false;
    return _dislikeRatio(post) >= 0.45 || post.dislikes >= post.likes;
  }
}
