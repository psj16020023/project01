import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_colors.dart';
import '../core/app_environment.dart';
import '../data/cu_product_catalog.dart';
import '../models/app_tab.dart';
import '../models/bot_conversation.dart';
import '../models/bot_message.dart';
import '../models/combination_battle.dart';
import '../models/post.dart';
import '../models/post_feature_index.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/pyeon_user.dart';
import '../models/sort_mode.dart';
import '../repositories/post_repository.dart';
import '../services/battle_state_store.dart';
import '../services/bot_budget_rules.dart';
import '../services/bot_situation_analyzer.dart';
import '../services/local_account_store.dart';
import '../widgets/cu_product_badges.dart';
import 'combination_battle_screen.dart';
import 'post_reviews_screen.dart';

const List<String> _suggestedSearchCategories = <String>[
  '저칼로리',
  '가성비',
  '시간절약',
  '호불호',
  '트렌드',
];

enum HighlightCollectionType { newProduct, pbProduct }

String _cleanTagLabel(String value) {
  return value
      .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeCategory(String input) {
  final normalized = _cleanTagLabel(input).replaceAll('#', '').trim();
  if (normalized == '트랜드') {
    return '트렌드';
  }
  if (normalized == '출근길 추천') {
    return '';
  }
  return communityReviewTags.contains(normalized) ? normalized : '';
}

List<String> _displayCategories(List<String> categories, {int maxVisible = 4}) {
  final cleaned = categories
      .map(_normalizeCategory)
      .where((item) => item.isNotEmpty)
      .toList();
  if (cleaned.length <= maxVisible) {
    return cleaned;
  }
  return <String>[
    ...cleaned.take(maxVisible - 1),
    '+${cleaned.length - (maxVisible - 1)}',
  ];
}

bool _titleHasNewProduct(String title) {
  return CuProductCatalog.matchesForText(
    title,
  ).any((match) => match.labels.contains(CuProductLabel.newProduct));
}

bool _titleHasPbProduct(String title) {
  return CuProductCatalog.matchesForText(
    title,
  ).any((match) => match.labels.contains(CuProductLabel.pbProduct));
}

bool _postHasNewProduct(Post post) => _titleHasNewProduct(post.title);

bool _postHasPbProduct(Post post) => _titleHasPbProduct(post.title);

bool _featureHasNewProduct(PostFeatureInfo post) =>
    _titleHasNewProduct(post.title);

bool _featureHasPbProduct(PostFeatureInfo post) =>
    _titleHasPbProduct(post.title);

String _formatWon(int amount) {
  return '${NumberFormat.decimalPattern('ko_KR').format(amount)}원';
}

String _displayImageUrl(String imageUrl) {
  final raw = imageUrl.trim();
  if (raw.isEmpty || raw.startsWith('data:')) return raw;
  if (kIsWeb && raw.startsWith(RegExp(r'https?://'))) {
    return '${Uri.base.origin}/api/image-proxy?url=${Uri.encodeComponent(raw)}';
  }
  return raw;
}

String _contentWithoutBarcodeLines(String content) {
  return content
      .split('\n')
      .map(
        (line) => line
            .replaceAll(
              RegExp(
                r'(?:[,·]\s*)?(?:바코드|barcode)\s*[:：]?\s*[0-9A-Za-z-]+',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(RegExp(r'^[\s,·]+|[\s,·]+$'), '')
            .trim(),
      )
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();
}

List<String> _matchingTitleSuggestions(
  Iterable<String> titles,
  String rawQuery, {
  int limit = 8,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const <String>[];
  final unique = <String>{};
  for (final title in titles) {
    final cleaned = title.trim();
    if (cleaned.isNotEmpty && cleaned.toLowerCase().contains(query)) {
      unique.add(cleaned);
    }
  }
  final matches = unique.toList()
    ..sort((a, b) {
      final aStarts = a.toLowerCase().startsWith(query);
      final bStarts = b.toLowerCase().startsWith(query);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.length.compareTo(b.length);
    });
  return matches.take(limit).toList();
}

String _applyTitleSuggestion(String current, String suggestion) {
  final separator = current.lastIndexOf('+');
  if (separator < 0) return suggestion;
  final prefix = current.substring(0, separator).trimRight();
  return prefix.isEmpty ? suggestion : '$prefix + $suggestion';
}

int _communityMomentumScore(PostFeatureInfo post, DateTime now) {
  final ageHours = math.max(1, now.difference(post.createdAt).inHours);
  final reactionScore =
      (post.likes * 4) +
      (post.reviewCount * 5) +
      (post.commentCount * 3) -
      (post.dislikes * 2);
  final recencyBoost = math.max(0, 72 - ageHours);
  return reactionScore + recencyBoost;
}

class _CommunityTrendGroup {
  const _CommunityTrendGroup({
    required this.label,
    required this.caption,
    required this.icon,
    required this.color,
    required this.posts,
  });

  final String label;
  final String caption;
  final IconData icon;
  final Color color;
  final List<PostFeatureInfo> posts;
}

List<_CommunityTrendGroup> _buildCommunityTrendPicks(
  List<PostFeatureInfo> posts,
) {
  if (posts.isEmpty) return const <_CommunityTrendGroup>[];
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));
  final oldLine = now.subtract(const Duration(days: 7));
  final activityWindow = now.subtract(const Duration(days: 30));

  List<PostFeatureInfo> ranked(
    Iterable<PostFeatureInfo> candidates,
    int Function(PostFeatureInfo post) score, {
    int limit = 5,
  }) {
    final sorted = candidates.toList()
      ..sort((a, b) {
        final compare = score(b).compareTo(score(a));
        return compare != 0 ? compare : b.createdAt.compareTo(a.createdAt);
      });
    return sorted.take(limit).toList();
  }

  bool qualifiesForPopularity(PostFeatureInfo post) {
    return post.likes >= 10 && post.likes >= math.max(1, post.dislikes * 3);
  }

  final weeklyRising = ranked(
    posts.where(
      (post) =>
          post.createdAt.isAfter(weekAgo) &&
          !qualifiesForPopularity(post) &&
          post.likes + post.commentCount + post.reviewCount > 0,
    ),
    (post) => _communityMomentumScore(post, now),
    limit: 3,
  );
  final rediscovered = ranked(
    posts.where(
      (post) =>
          post.createdAt.isBefore(oldLine) &&
          (post.recentLikeCount >= 2 ||
              (post.topFiveEnteredAt?.isAfter(activityWindow) ?? false)),
    ),
    (post) =>
        (post.recentLikeCount * 12) +
        (post.likes * 4) +
        (post.reviewCount * 6) +
        (post.commentCount * 3),
  );
  final rediscoveredIds = rediscovered.map((post) => post.id).toSet();
  final weeklyPopular = ranked(
    posts.where(
      (post) =>
          qualifiesForPopularity(post) && !rediscoveredIds.contains(post.id),
    ),
    (post) => (post.likes * 5) + (post.reviewCount * 4) - post.dislikes,
  );

  return <_CommunityTrendGroup>[
    if (weeklyPopular.isNotEmpty)
      _CommunityTrendGroup(
        label: '이번주 인기',
        caption: '이번 주 하트 상위',
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFFFF7A1A),
        posts: weeklyPopular,
      ),
    _CommunityTrendGroup(
      label: '재평가',
      caption: rediscovered.isEmpty ? '조건에 맞는 글을 기다리는 중' : '오래된 글이 다시 주목받는 중',
      icon: Icons.replay_circle_filled_rounded,
      color: const Color(0xFF4F7DF0),
      posts: rediscovered,
    ),
    if (weeklyRising.isNotEmpty)
      _CommunityTrendGroup(
        label: '이번주 급상승',
        caption: '반응이 빠르게 붙는 중',
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF25A96B),
        posts: weeklyRising,
      ),
  ];
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.environment,
    required this.currentUser,
    required this.onUserChanged,
    required this.onLogout,
  });

  final PostRepository repository;
  final AppEnvironment environment;
  final PyeonUser currentUser;
  final Future<void> Function(PyeonUser user) onUserChanged;
  final Future<void> Function() onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _minFilterController = TextEditingController();
  final _maxFilterController = TextEditingController();
  final _communicationScrollController = ScrollController();
  final Set<String> _selectedSearchTags = <String>{};

  AppTab _selectedTab = AppTab.communication;
  SortMode _sortMode = SortMode.latest;
  String? _likedGenderMajority;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMorePosts = true;
  String? _error;
  List<Post> _posts = <Post>[];
  List<PostFeatureInfo> _postFeatureIndex = <PostFeatureInfo>[];
  List<Post> _featurePostPool = <Post>[];
  List<Post> _botRecommendationPosts = <Post>[];
  Post? _detailPost;
  String? _nextPostsCursor;
  bool _loadingFeaturePostPool = false;
  List<PyeonUser> _knownUsers = <PyeonUser>[];

  List<Post> get _allFunctionalPosts {
    final byId = <String, Post>{
      for (final post in _featurePostPool) post.id: post,
      for (final post in _posts) post.id: post,
    };
    return byId.values.toList();
  }

  List<PostFeatureInfo> get _allFeatureInfo {
    final byId = <String, PostFeatureInfo>{
      for (final post in _postFeatureIndex) post.id: post,
      for (final post in _featurePostPool)
        post.id: PostFeatureInfo.fromPost(post),
      for (final post in _posts) post.id: PostFeatureInfo.fromPost(post),
    };
    return byId.values.toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.currentUser.botSetup == null
        ? AppTab.bot
        : AppTab.communication;
    _communicationScrollController.addListener(_handleCommunicationScroll);
    _loadKnownUsers();
    _loadPosts();
    unawaited(_loadPostFeatureIndex());
    unawaited(_loadFeaturePostPool());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minFilterController.dispose();
    _maxFilterController.dispose();
    _communicationScrollController
      ..removeListener(_handleCommunicationScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadKnownUsers() async {
    try {
      final store = await LocalAccountStore.load(
        environment: widget.environment,
      );
      final accounts = store.getAccounts();
      if (!mounted) return;
      setState(() => _knownUsers = accounts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _knownUsers = <PyeonUser>[widget.currentUser]);
    }
  }

  List<PyeonUser> get _allUsersForStats {
    final byId = <String, PyeonUser>{
      for (final user in _knownUsers) user.id: user,
      widget.currentUser.id: widget.currentUser,
    };
    return byId.values.toList();
  }

  void _handleCommunicationScroll() {
    if (!_communicationScrollController.hasClients ||
        _selectedTab != AppTab.communication) {
      return;
    }
    final position = _communicationScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      unawaited(_loadMorePosts());
    }
  }

  Future<void> _loadPosts({bool reset = true, int attempt = 0}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
        _nextPostsCursor = null;
        _hasMorePosts = true;
      }
    });

    try {
      final searchQuery = _searchController.text.trim();
      final page = await widget.repository.fetchPosts(
        query: searchQuery,
        selectedTags: _selectedSearchTags.toList(),
        minPrice: int.tryParse(_minFilterController.text.trim()),
        maxPrice: int.tryParse(_maxFilterController.text.trim()),
        likedGenderMajority: _likedGenderMajority,
        currentUserId: widget.currentUser.id,
        cursor: reset ? null : _nextPostsCursor,
        limit: 6,
        sortMode: _sortMode,
      );
      final pagePosts = page.posts.map(_withCurrentUserReaction).toList();
      await _mergeLoadedReactionsIntoUser(pagePosts);

      if (!mounted) return;
      setState(() {
        _posts = reset ? pagePosts : [..._posts, ...pagePosts];
        for (final post in pagePosts) {
          _upsertPostFeature(post);
        }
        if (_detailPost != null) {
          for (final post in pagePosts) {
            if (post.id == _detailPost!.id) {
              _detailPost = post;
              break;
            }
          }
        }
        _nextPostsCursor = page.nextCursor;
        _hasMorePosts = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (attempt == 0 && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return _loadPosts(reset: reset, attempt: 1);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = widget.environment.dataMode == DataMode.remote
            ? '원격 서버에서 게시글을 불러오지 못했어요. API 주소나 서버 상태를 확인해 주세요.'
            : '게시글을 불러오지 못했어요.';
      });
    }
  }

  Future<void> _scanCommunicationBarcode() async {
    final rawValue = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const ProductScannerPage(),
      ),
    );

    if (!mounted || rawValue == null || rawValue.trim().isEmpty) return;

    try {
      final result = await widget.repository.lookupProductByBarcode(rawValue);
      final productName = result.officialName.trim();
      if (!mounted) return;

      if (productName.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이 바코드의 상품명을 찾지 못했어요.')));
        return;
      }

      setState(() => _searchController.text = productName);
      await _loadPosts();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('바코드 상품명을 불러오지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Post _withCurrentUserReaction(Post post) {
    return post.copyWith(
      likedByMe:
          post.likedByMe || widget.currentUser.likedPostIds.contains(post.id),
      dislikedByMe:
          post.dislikedByMe ||
          widget.currentUser.dislikedPostIds.contains(post.id),
    );
  }

  Future<void> _mergeLoadedReactionsIntoUser(List<Post> posts) async {
    final likedIds = widget.currentUser.likedPostIds.toSet();
    final dislikedIds = widget.currentUser.dislikedPostIds.toSet();
    var changed = false;
    for (final post in posts) {
      if (post.likedByMe && likedIds.add(post.id)) changed = true;
      if (post.dislikedByMe && dislikedIds.add(post.id)) changed = true;
    }
    if (!changed) return;
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        likedPostIds: likedIds.toList(),
        dislikedPostIds: dislikedIds.toList(),
      ),
    );
  }

  Future<void> _loadMorePosts() async {
    if (_loading ||
        _loadingMore ||
        !_hasMorePosts ||
        _nextPostsCursor == null) {
      return;
    }

    setState(() => _loadingMore = true);
    await _loadPosts(reset: false);
  }

  Future<void> _loadPostFeatureIndex() async {
    try {
      final items = await widget.repository.fetchPostFeatureIndex();
      if (!mounted) return;
      setState(() => _postFeatureIndex = items);
    } catch (_) {
      if (!mounted || _postFeatureIndex.isNotEmpty || _posts.isEmpty) return;
      setState(
        () => _postFeatureIndex = _posts.map(PostFeatureInfo.fromPost).toList(),
      );
    }
  }

  void _upsertPostFeature(Post post) {
    final next = <String, PostFeatureInfo>{
      for (final item in _postFeatureIndex) item.id: item,
      post.id: PostFeatureInfo.fromPost(post),
    };
    _postFeatureIndex = next.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _removePostFeature(String postId) {
    _postFeatureIndex = _postFeatureIndex
        .where((item) => item.id != postId)
        .toList();
  }

  Future<void> _loadBotRecommendationPool({bool reset = false}) async {
    if (!reset && _botRecommendationPosts.isNotEmpty) return;
    try {
      final posts = await widget.repository.fetchPostCatalog(
        currentUserId: widget.currentUser.id,
      );
      if (!mounted) return;
      setState(() {
        _botRecommendationPosts = posts.map(_withCurrentUserReaction).toList();
      });
    } catch (_) {
      // Existing loaded posts remain available as the fallback pool.
    }
  }

  Future<List<Post>> _fetchAllPostsForFunctions() async {
    final posts = await widget.repository.fetchPostCatalog(
      currentUserId: widget.currentUser.id,
    );
    return posts.map(_withCurrentUserReaction).toList();
  }

  Future<List<Post>> _ensureFeaturePostPool() async {
    if (_featurePostPool.isNotEmpty) return _allFunctionalPosts;
    await _loadFeaturePostPool();
    return _allFunctionalPosts;
  }

  Future<void> _loadFeaturePostPool({bool reset = false}) async {
    if (_loadingFeaturePostPool || (!reset && _featurePostPool.isNotEmpty)) {
      return;
    }
    _loadingFeaturePostPool = true;
    try {
      final posts = await _fetchAllPostsForFunctions();
      await _mergeLoadedReactionsIntoUser(posts);
      if (!mounted) return;
      setState(() {
        _featurePostPool = posts;
        _botRecommendationPosts = posts;
        for (final post in posts) {
          _upsertPostFeature(post);
        }
      });
    } catch (_) {
      // Screen-loaded posts remain the fallback for feature surfaces.
    } finally {
      _loadingFeaturePostPool = false;
    }
  }

  Future<void> _toggleLike(Post post) async {
    final updated = await widget.repository.toggleLike(
      post.id,
      widget.currentUser.id,
    );
    if (!mounted) return;
    _applyUpdatedPost(updated);
    await _syncPostReactionToUser(updated);
    unawaited(_loadPostFeatureIndex());
  }

  Future<void> _toggleDislike(Post post) async {
    final updated = await widget.repository.toggleDislike(
      post.id,
      widget.currentUser.id,
    );
    if (!mounted) return;
    _applyUpdatedPost(updated);
    await _syncPostReactionToUser(updated);
    unawaited(_loadPostFeatureIndex());
  }

  Future<void> _syncPostReactionToUser(Post post) async {
    final likedIds = widget.currentUser.likedPostIds.toSet();
    final dislikedIds = widget.currentUser.dislikedPostIds.toSet();
    if (post.likedByMe) {
      likedIds.add(post.id);
    } else {
      likedIds.remove(post.id);
    }
    if (post.dislikedByMe) {
      dislikedIds.add(post.id);
    } else {
      dislikedIds.remove(post.id);
    }
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        likedPostIds: likedIds.toList(),
        dislikedPostIds: dislikedIds.toList(),
      ),
    );
  }

  Future<void> _addComment(Post post, String text) async {
    final updated = await widget.repository.addComment(
      post.id,
      text,
      authorId: widget.currentUser.id,
      authorNickname: widget.currentUser.nickname,
    );
    if (!mounted) return;
    _applyUpdatedPost(updated);
  }

  Future<Post> _addReview(Post post, PostReview review) async {
    final updated = await widget.repository.addReview(post.id, review);
    if (mounted) _applyUpdatedPost(updated);
    return updated;
  }

  Future<Post> _updateReview(Post post, PostReview review) async {
    final updated = await widget.repository.updateReview(post.id, review);
    if (mounted) _applyUpdatedPost(updated);
    return updated;
  }

  Future<Post> _deleteReview(Post post, PostReview review) async {
    final updated = await widget.repository.deleteReview(
      post.id,
      review.id,
      authorId: widget.currentUser.id,
    );
    if (mounted) _applyUpdatedPost(updated);
    return updated;
  }

  void _applyUpdatedPost(Post updated) {
    final nextPosts = [..._posts];
    final index = nextPosts.indexWhere((post) => post.id == updated.id);
    if (index != -1) {
      nextPosts[index] = updated;
    }
    final nextPool = [..._featurePostPool];
    final poolIndex = nextPool.indexWhere((post) => post.id == updated.id);
    if (poolIndex != -1) {
      nextPool[poolIndex] = updated;
    }
    nextPosts.sort((a, b) {
      switch (_sortMode) {
        case SortMode.latest:
          return b.createdAt.compareTo(a.createdAt);
        case SortMode.popular:
          final likeCompare = b.likes.compareTo(a.likes);
          return likeCompare != 0
              ? likeCompare
              : b.createdAt.compareTo(a.createdAt);
        case SortMode.worst:
          final dislikeCompare = b.dislikes.compareTo(a.dislikes);
          return dislikeCompare != 0
              ? dislikeCompare
              : b.createdAt.compareTo(a.createdAt);
      }
    });
    setState(() {
      _posts = nextPosts;
      _featurePostPool = nextPool;
      _upsertPostFeature(updated);
      if (_detailPost?.id == updated.id) {
        _detailPost = updated;
      }
    });
  }

  Post? _findPostById(String id) {
    for (final post in <Post>[
      ..._posts,
      ..._featurePostPool,
      ..._botRecommendationPosts,
    ]) {
      if (post.id == id) {
        return post;
      }
    }
    return null;
  }

  Future<void> _openPostDetail(
    Post post, {
    bool switchToCommunication = false,
  }) async {
    if (switchToCommunication && mounted) {
      setState(() => _selectedTab = AppTab.communication);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PostDetailPage(
          post: _findPostById(post.id) ?? post,
          currentUser: widget.currentUser,
          allPosts: _allFunctionalPosts,
          allUsers: _allUsersForStats,
          onLoadAudienceStats: () =>
              widget.repository.fetchPostAudienceStats(post.id),
          isMine: post.authorId == widget.currentUser.id,
          isSaved: widget.currentUser.savedPostIds.contains(post.id),
          isPickedAuthor: widget.currentUser.pickedAuthorIds.contains(
            post.authorId,
          ),
          onToggleLike: () async {
            await _toggleLike(_findPostById(post.id) ?? post);
            return _findPostById(post.id) ?? post;
          },
          onToggleDislike: () async {
            await _toggleDislike(_findPostById(post.id) ?? post);
            return _findPostById(post.id) ?? post;
          },
          onAddComment: (text) async {
            await _addComment(_findPostById(post.id) ?? post, text);
            return _findPostById(post.id) ?? post;
          },
          onToggleSave: () => _toggleSavedPost(post.id),
          onTogglePickAuthor: () => _togglePickedAuthor(post.authorId),
          onEdit: () =>
              _openComposer(initialPost: _findPostById(post.id) ?? post),
          onDelete: () => _deletePost(_findPostById(post.id) ?? post),
          onOpenAuthor: () =>
              _openAuthorProfile(_findPostById(post.id) ?? post),
          onOpenCommentAuthor: _openAuthorByIdentity,
          onAddReview: (review) =>
              _addReview(_findPostById(post.id) ?? post, review),
          onUpdateReview: (review) =>
              _updateReview(_findPostById(post.id) ?? post, review),
          onDeleteReview: (review) =>
              _deleteReview(_findPostById(post.id) ?? post, review),
        ),
      ),
    );
  }

  void _showOwnProfileTab() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _selectedTab = AppTab.profile;
    });
  }

  Future<void> _toggleSavedPost(String postId) async {
    final current = widget.currentUser.savedPostIds.toSet();
    if (current.contains(postId)) {
      current.remove(postId);
    } else {
      current.add(postId);
    }
    await widget.onUserChanged(
      widget.currentUser.copyWith(savedPostIds: current.toList()),
    );
  }

  Future<void> _togglePickedAuthor(String authorId) async {
    if (authorId == widget.currentUser.id) return;
    final current = widget.currentUser.pickedAuthorIds.toSet();
    if (current.contains(authorId)) {
      current.remove(authorId);
    } else {
      current.add(authorId);
    }
    await widget.onUserChanged(
      widget.currentUser.copyWith(pickedAuthorIds: current.toList()),
    );
  }

  Future<void> _toggleProfilePublic(bool value) async {
    await widget.onUserChanged(
      widget.currentUser.copyWith(profilePublic: value),
    );
  }

  Future<void> _openComposer({Post? initialPost}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ComposerPage(
          repository: widget.repository,
          currentUser: widget.currentUser,
          initialPost: initialPost,
        ),
      ),
    );
    if (changed == true) {
      await _loadPosts();
      await _loadPostFeatureIndex();
      await _loadFeaturePostPool(reset: true);
    }
  }

  Future<void> _deletePost(Post post) async {
    await widget.repository.deletePost(post.id, widget.currentUser.id);
    setState(() => _removePostFeature(post.id));
    await _loadPosts();
    await _loadPostFeatureIndex();
    await _loadFeaturePostPool(reset: true);
  }

  Future<void> _saveBotSetup(BotSetup setup) async {
    final welcome = BotMessage(
      role: 'assistant',
      text: '초기 설정을 저장했어요. 대화 화면에서 현재 예산을 적고 기분이나 상황을 말해주면 예산 안의 조합을 골라드릴게요.',
      createdAt: DateTime.now(),
    );
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        botSetup: setup,
        botMessages: <BotMessage>[welcome],
        archivedConversations: widget.currentUser.archivedConversations,
      ),
    );
  }

  Future<void> _resetBotSetup() async {
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        clearBotSetup: true,
        botMessages: const <BotMessage>[],
        memoryNotes: const <String>[],
      ),
    );
    if (!mounted) return;
    setState(() => _selectedTab = AppTab.bot);
  }

  Future<BotTurnResult> _sendBotPrompt(
    String prompt,
    bool useAgeCalorieGuide,
    int? currentBudget,
  ) async {
    final setup = widget.currentUser.botSetup;
    if (setup == null) return const BotTurnResult();
    if (_botRecommendationPosts.isEmpty) {
      await _loadBotRecommendationPool(reset: true);
    }

    final userMessage = BotMessage(
      role: 'user',
      text: prompt,
      createdAt: DateTime.now(),
    );
    final aiSituation = await BotSituationAnalyzer.analyze(
      environment: widget.environment,
      prompt: prompt,
      memoryNotes: widget.currentUser.memoryNotes,
    );
    final reply = _buildBotReply(
      prompt,
      setup,
      aiSituation: aiSituation,
      useAgeCalorieGuide: useAgeCalorieGuide,
      currentBudget: currentBudget,
    );
    final assistantMessage = BotMessage(
      role: 'assistant',
      text: reply.text,
      createdAt: DateTime.now(),
      recommendedPostIds: reply.recommendedPostIds,
      resolvedBudget: reply.resolvedBudget,
      minimumPrice: reply.minimumPrice,
      contextPrompt: reply.contextPrompt,
      useAgeCalorieGuide: reply.useAgeCalorieGuide,
      pendingClarification: reply.pendingClarification,
      pendingAmount: reply.pendingAmount,
    );

    final nextMessages = <BotMessage>[
      ...widget.currentUser.botMessages,
      userMessage,
      assistantMessage,
    ];
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        botMessages: nextMessages,
        memoryNotes: _buildUpdatedMemories(
          widget.currentUser.memoryNotes,
          prompt,
          reply.memoryNote,
        ),
      ),
    );
    return BotTurnResult(
      resolvedBudget: reply.resolvedBudget,
      shouldSyncBudget: reply.shouldSyncBudget,
    );
  }

  Future<void> _sendMoreBotRecommendations(
    bool useAgeCalorieGuide,
    int? currentBudget,
  ) async {
    final setup = widget.currentUser.botSetup;
    if (setup == null) return;
    await _loadBotRecommendationPool();

    String? prompt;
    BotMessage? latestContext;
    for (final message in widget.currentUser.botMessages.reversed) {
      if (message.role == 'assistant' &&
          message.contextPrompt?.trim().isNotEmpty == true) {
        latestContext = message;
        prompt = message.contextPrompt;
        break;
      }
    }
    for (final message in widget.currentUser.botMessages.reversed) {
      if (prompt == null &&
          message.role == 'user' &&
          message.text.trim().isNotEmpty) {
        prompt = message.text;
        break;
      }
    }
    if (prompt == null) return;

    final excludedPostIds = widget.currentUser.botMessages
        .expand((message) => message.recommendedPostIds)
        .toSet();
    final aiSituation = await BotSituationAnalyzer.analyze(
      environment: widget.environment,
      prompt: prompt,
      memoryNotes: widget.currentUser.memoryNotes,
    );
    final reply = _buildBotReply(
      prompt,
      setup,
      aiSituation: aiSituation,
      useAgeCalorieGuide: useAgeCalorieGuide,
      excludedPostIds: excludedPostIds,
      forceRecommendation: true,
      currentBudget: latestContext?.resolvedBudget ?? currentBudget,
      currentMinimumPrice: latestContext?.minimumPrice,
    );
    final assistantMessage = BotMessage(
      role: 'assistant',
      text: reply.recommendedPostIds.isEmpty
          ? reply.text
          : '앞에서 본 조합은 빼고 다음 추천을 골랐어.\n\n${reply.text}',
      createdAt: DateTime.now(),
      recommendedPostIds: reply.recommendedPostIds,
      resolvedBudget: reply.resolvedBudget,
      minimumPrice: reply.minimumPrice,
      contextPrompt: reply.contextPrompt,
      useAgeCalorieGuide: reply.useAgeCalorieGuide,
    );
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        botMessages: <BotMessage>[
          ...widget.currentUser.botMessages,
          assistantMessage,
        ],
      ),
    );
  }

  Future<void> _resetCurrentConversation() async {
    if (widget.currentUser.botMessages.isEmpty) {
      return;
    }
    final title = _buildConversationTitle(widget.currentUser.botMessages);
    final archived = BotConversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      messages: widget.currentUser.botMessages,
      updatedAt: DateTime.now(),
    );
    await widget.onUserChanged(
      widget.currentUser.copyWith(
        botMessages: const <BotMessage>[],
        archivedConversations: <BotConversation>[
          archived,
          ...widget.currentUser.archivedConversations,
        ],
      ),
    );
  }

  String _buildConversationTitle(List<BotMessage> messages) {
    BotMessage? firstUser;
    for (final message in messages) {
      if (message.role == 'user') {
        firstUser = message;
        break;
      }
    }
    final text = (firstUser?.text ?? '편봇 대화').trim();
    return text.length > 18 ? '${text.substring(0, 18)}...' : text;
  }

  List<String> _buildUpdatedMemories(
    List<String> current,
    String prompt,
    String memoryNote,
  ) {
    final next = <String>[
      memoryNote,
      if (prompt.length > 18)
        '최근 대화: ${prompt.substring(0, prompt.length > 38 ? 38 : prompt.length)}',
      ...current,
    ];
    final seen = <String>{};
    return next
        .where((item) => item.trim().isNotEmpty && seen.add(item))
        .take(8)
        .toList();
  }

  _BotReply _buildBotReply(
    String prompt,
    BotSetup setup, {
    BotSituationContext? aiSituation,
    bool useAgeCalorieGuide = true,
    Set<String> excludedPostIds = const <String>{},
    bool forceRecommendation = false,
    int? currentBudget,
    int? currentMinimumPrice,
  }) {
    BotMessage? lastAssistantMessage;
    for (final message in widget.currentUser.botMessages.reversed) {
      if (message.role == 'assistant') {
        lastAssistantMessage = message;
        break;
      }
    }
    final originalNormalized = prompt.toLowerCase();
    var effectivePrompt = prompt;
    var resolvedBudget = currentBudget;
    var minimumPrice = currentMinimumPrice;
    var shouldSyncBudget = false;
    var shouldForceRecommendation = forceRecommendation;

    if (lastAssistantMessage?.pendingClarification == 'budgetDirection') {
      final choice = BotBudgetRules.parseClarification(prompt);
      if (choice == BotBudgetClarification.unknown) {
        return _BotReply(
          text:
              '최대 예산인지, 그 가격 이상을 찾는 건지 한 번만 알려줘. 예: “최대 예산이야” 또는 “5천 원 이상 가격이야”.',
          memoryNote: '예산 방향 확인 중',
          recommendedPostIds: const <String>[],
          contextPrompt: lastAssistantMessage?.contextPrompt,
          useAgeCalorieGuide: useAgeCalorieGuide,
          pendingClarification: 'budgetDirection',
          pendingAmount: lastAssistantMessage?.pendingAmount,
        );
      }
      effectivePrompt = lastAssistantMessage?.contextPrompt ?? prompt;
      shouldForceRecommendation = true;
      if (choice == BotBudgetClarification.maximum) {
        resolvedBudget = lastAssistantMessage?.pendingAmount;
        shouldSyncBudget = resolvedBudget != null;
      } else {
        minimumPrice = lastAssistantMessage?.pendingAmount;
      }
    } else {
      final budgetMention = BotBudgetRules.parseMention(prompt);
      if (budgetMention?.direction == BotBudgetDirection.ambiguous &&
          !(forceRecommendation && currentMinimumPrice != null)) {
        final amount = budgetMention!.amount;
        return _BotReply(
          text:
              '${_formatWon(amount)}을 최대 예산으로 쓸까요, ${_formatWon(amount)} 이상 가격의 조합을 찾을까요?',
          memoryNote: '예산 방향 확인 필요',
          recommendedPostIds: const <String>[],
          contextPrompt: prompt,
          useAgeCalorieGuide: useAgeCalorieGuide,
          pendingClarification: 'budgetDirection',
          pendingAmount: amount,
        );
      }
      if (budgetMention?.direction == BotBudgetDirection.maximum) {
        resolvedBudget = budgetMention!.amount;
        shouldSyncBudget = true;
      } else if (budgetMention?.direction == BotBudgetDirection.minimum) {
        minimumPrice = budgetMention!.amount;
      }
    }

    final affirmativeFollowUp = _hasAny(originalNormalized, const [
      '응',
      '그래',
      '해줘',
      '해 줘',
      '좋아',
      'ㅇㅇ',
      '웅',
      '오케이',
      'ok',
    ]);
    if (lastAssistantMessage?.contextPrompt != null &&
        affirmativeFollowUp &&
        BotBudgetRules.parseMention(prompt) == null &&
        lastAssistantMessage?.pendingClarification == null) {
      effectivePrompt = lastAssistantMessage!.contextPrompt!;
      resolvedBudget = lastAssistantMessage.resolvedBudget ?? resolvedBudget;
      minimumPrice = lastAssistantMessage.minimumPrice;
      shouldForceRecommendation = true;
    }

    final normalized = effectivePrompt.toLowerCase();
    final recommendationPrompt = <String>[
      normalized,
      ...?aiSituation?.avoidConditions,
      if (aiSituation?.bodyCondition != null) aiSituation!.bodyCondition!,
      if (aiSituation?.mealPurpose != null) aiSituation!.mealPurpose!,
    ].join(' ');
    final recommendationPool = _botRecommendationPosts.isEmpty
        ? _posts
        : _botRecommendationPosts;
    final likedPosts = recommendationPool
        .where((post) => post.likedByMe)
        .toList();
    final analysis = _analyzeSituationPrompt(normalized);
    final isFoodRequest = _hasAny(normalized, const [
      '추천',
      '추천해줘',
      '골라줘',
      '아무거나',
      '뭐 먹',
      '뭐 먹지',
      '뭐사먹',
      '뭐 사먹',
      '먹을 거',
      '편의점',
      '배고',
      '메뉴',
      '먹을까',
      '조합',
      '음식',
    ]);
    final isGreeting = _hasAny(normalized, const [
      '안녕',
      '하이',
      '반가',
      '처음',
      'ㅎㅇ',
    ]);
    final isQuestionAboutBot = _hasAny(normalized, const [
      '너 뭐',
      '무슨 기능',
      '할 수 있',
      '누구야',
    ]);
    final isThanks = _hasAny(normalized, const [
      '고마워',
      '감사',
      'ㄱㅅ',
      'thanks',
      'thx',
    ]);
    final isAskingForEmpathy = _hasAny(normalized, const [
      '위로',
      '공감',
      '들어줘',
      '말 좀',
      '너무 힘들',
      '속상',
    ]);
    final isNeedFastAnswer =
        _hasAny(normalized, const ['빨리', '당장', '지금 바로', '시간없', '급해']) ||
        (aiSituation?.timeAvailableMinutes != null &&
            aiSituation!.timeAvailableMinutes! <= 10);
    final isDieting = _hasAny(normalized, const [
      '다이어트',
      '살 빼',
      '살빼',
      '감량',
      '칼로리',
      '저칼로리',
    ]);
    final wantsLightMeal = _hasAny(normalized, const [
      '가볍게',
      '부담 없',
      '안 무거운',
      '속 편한',
      '클린',
    ]);
    final wantsProtein = _hasAny(normalized, const [
      '단백질',
      'protein',
      '근손실',
      '운동 후',
      '운동끝',
      '헬스',
    ]);
    final wantsSatiety = _hasAny(normalized, const [
      '포만감',
      '든든',
      '배부른',
      '허기',
      '허기짐',
    ]);
    final wantsFullMeal = _hasAny(normalized, const [
      '한끼',
      '한 끼',
      '식사',
      '끼니',
      '아침',
      '점심',
      '저녁',
      '밥',
      '배고',
      '든든',
    ]);
    final avoidsSugar = _hasAny(normalized, const [
      '당 줄',
      '당류',
      '단 거 말고',
      '덜 단',
      '무가당',
    ]);
    final lateNight =
        _hasAny(normalized, const ['야식', '밤', '늦은 시간', '자기 전']) ||
        (aiSituation?.lateNight ?? false);
    final explicitBudget = resolvedBudget != currentBudget
        ? resolvedBudget
        : aiSituation?.budget;
    final budget = resolvedBudget ?? aiSituation?.budget;
    final matchedSituationTags = _extractPromptSituationTags(normalized);
    final lastAssistantText = lastAssistantMessage?.text ?? '';
    final awaitingRecommendationAnswer =
        _hasAny(lastAssistantText, const [
          '추천해줄까',
          '추천해볼까',
          '골라볼까',
          '추천해볼게',
          '추천도 바로 해줄까',
          '추천도 해줄까',
          '추천해줄까?',
          '추천해 볼까',
        ]) ||
        (lastAssistantText.contains('원하면') &&
            lastAssistantText.contains('추천') &&
            (lastAssistantText.contains('해줄까') ||
                lastAssistantText.contains('해 볼까') ||
                lastAssistantText.contains('골라볼까')));
    final affirmativeReaction = _hasAny(normalized, const [
      '응',
      '좋아',
      '그래',
      'ㅇㅇ',
      '어',
      '웅',
      '맞아',
      '좋지',
      '좋네',
      '콜',
      '오케이',
      '오키',
      'ok',
      'yes',
      '해보자',
      '가자',
      '그럴래',
      '그렇게 해',
      '부탁',
    ]);
    final isYesToRecommendation =
        awaitingRecommendationAnswer &&
        (affirmativeReaction ||
            _hasAny(normalized, const ['해줘', '해 줘', '추천해줘', '추천해 줘']));
    final isNoToRecommendation =
        awaitingRecommendationAnswer &&
        _hasAny(normalized, const [
          '아니',
          '괜찮아',
          '괜찮아요',
          '말고',
          '추천하지 마',
          '추천 안',
          '싫어',
          '나중에',
        ]);

    final hasMeaningfulAiContext =
        aiSituation != null &&
        (_normalizeAiEmotion(aiSituation.emotion).isNotEmpty ||
            aiSituation.bodyCondition != null ||
            aiSituation.mealPurpose != null ||
            aiSituation.wantedTastes.isNotEmpty ||
            aiSituation.avoidConditions.isNotEmpty ||
            aiSituation.lateNight ||
            aiSituation.timeAvailableMinutes != null);
    final matchedMoods = <String>{
      ...analysis.moods,
      if (hasMeaningfulAiContext) _normalizeAiEmotion(aiSituation.emotion),
    }..removeWhere((mood) => mood.isEmpty || mood == 'neutral');

    if (isGreeting) {
      return const _BotReply(
        text: '안녕! 지금 기분, 가진 돈, 남은 시간, 먹는 상황을 편하게 말해줘. 네 맛 점수와 예산 안에서 골라볼게.',
        memoryNote: '인사로 대화 시작',
        recommendedPostIds: <String>[],
      );
    }
    if (isQuestionAboutBot) {
      return const _BotReply(
        text:
            '나는 네 초기설정과 좋아요 기록을 바탕으로 감정, 예산, 시간, 야식 같은 현재 상황을 함께 읽는 개인 맞춤형 편봇이야. 네 예산을 넘지 않는 조합 중 맛 점수가 잘 맞는 것을 추천해.',
        memoryNote: '편봇 기능 설명',
        recommendedPostIds: <String>[],
      );
    }
    if (isThanks) {
      final followUp =
          lastAssistantMessage?.recommendedPostIds.isNotEmpty == true
          ? '천만에. 방금 추천한 것들 중에서 더 끌리는 쪽이 있으면 왜 그게 당기는지도 같이 정리해줄게.'
          : '천만에. 지금은 추천 없이 그냥 이야기만 이어가도 되고, 상황이 정리되면 그때 바로 골라줄게.';
      return _BotReply(
        text: followUp,
        memoryNote: '감사 인사에 응답',
        recommendedPostIds: const <String>[],
      );
    }

    final empathy = <String>[];
    final targetCategories = <String>{};
    final reasonParts = <String>[];
    String memoryNote = analysis.memoryNote;
    if (hasMeaningfulAiContext) {
      final situation = aiSituation;
      targetCategories.addAll(situation.wantedTastes);
      if (situation.summary.isNotEmpty) {
        empathy.add(situation.summary);
      }
      if (situation.mealPurpose != null && situation.mealPurpose!.isNotEmpty) {
        reasonParts.add('${situation.mealPurpose} 상황에 맞는 구성을 함께 볼게요.');
      }
      if (situation.bodyCondition != null &&
          situation.bodyCondition!.isNotEmpty) {
        reasonParts.add('현재 몸 상태인 ${situation.bodyCondition}도 고려할게요.');
      }
      memoryNote = 'AI 상황 분석: ${situation.summary}';
    }

    if (matchedMoods.contains('happy')) {
      empathy.add(
        analysis.emotionSummary.isNotEmpty
            ? analysis.emotionSummary
            : '좋은 일이 있었던 것 같아. 말투만 봐도 들뜨고 기분 좋은 쪽으로 느껴져.',
      );
      targetCategories.addAll(const ['신', '달달']);
      reasonParts.add('기분이 좋고 행복할 때는 상큼한 맛이나 달달한 맛이 그 분위기를 더 살려줄 수 있어요.');
      memoryNote = '기분 좋을 때 상큼하거나 달달한 조합 선호';
    }
    if (matchedMoods.contains('down')) {
      empathy.add('오늘 많이 가라앉아 있었던 것 같아. 그런 날엔 뭘 고르는 것조차 귀찮게 느껴질 수 있어.');
      targetCategories.add('달달');
      reasonParts.add('우울하고 무기력할 때는 단맛이 잠깐 에너지를 끌어올리고 기분 전환에 도움을 줄 수 있어요.');
      memoryNote = '기분이 가라앉을 때 달달한 조합 선호';
    }
    if (matchedMoods.contains('stress')) {
      empathy.add('스트레스가 꽤 쌓인 상태로 보여. 입 안에서 확 전환되는 맛이 필요할 수 있어.');
      if (setup.tasteLevel('매콤') >= 4) {
        targetCategories.add('매콤');
      } else {
        targetCategories.addAll(const ['달달', '신']);
      }
      reasonParts.add('화가 나거나 스트레스를 받을 때는 매운맛이나 자극 있는 맛이 기분 전환에 도움을 줄 수 있어요.');
      memoryNote = '스트레스 상황에서 강한 맛 선호';
    }
    if (matchedMoods.contains('anxious')) {
      empathy.add('긴장감이 꽤 올라와 있네. 지금은 과한 자극보다 안정감이 먼저일 수도 있어.');
      targetCategories.addAll(const ['저칼로리', '짭짤']);
      reasonParts.add('불안하고 긴장될 때는 따뜻하고 부드러운 컴포트 푸드 쪽이 더 잘 맞을 수 있어요.');
      memoryNote = '긴장될 때 편안한 조합 선호';
    }
    if (matchedMoods.contains('surprised')) {
      empathy.add('예상 밖의 일이 있어서 놀라거나 당황한 마음이 먼저 느껴져.');
      targetCategories.addAll(const ['신', '달달']);
      reasonParts.add(
        '놀람 계열 감정은 기분을 빠르게 정리해 주는 상큼함이나 부드러운 단맛 쪽으로 연결해 볼 수 있어요.',
      );
      memoryNote = '놀람 계열을 상큼하거나 부드러운 단맛으로 연결';
    }
    if (matchedMoods.contains('disgust')) {
      empathy.add('지금은 불쾌감이나 거부감이 커서, 자극적인 것보다 깔끔하고 담백한 쪽이 더 맞아 보여.');
      targetCategories.addAll(const ['저칼로리', '새콤']);
      reasonParts.add('혐오나 거부감이 느껴질 때는 입안을 정리하는 깔끔한 맛이나 담백한 맛이 덜 부담스러워요.');
      memoryNote = '불쾌감이 있을 때 깔끔하고 담백한 조합 선호';
    }
    if (matchedMoods.contains('tired')) {
      empathy.add('에너지가 많이 빠진 상태로 들려. 일단 정신이 조금 깨어나는 쪽이 좋겠어.');
      targetCategories.addAll(const ['신', '짭짤']);
      reasonParts.add(
        '피곤하고 지칠 때는 신맛이나 짭짤한 맛이 식욕을 돋우고 에너지를 회복하는 데 도움이 될 수 있어요.',
      );
      memoryNote = '피곤할 때 상큼한 조합 선호';
    }
    if (matchedMoods.contains('sick')) {
      empathy.add('속 상태가 예민해 보여서 자극적인 건 피하는 게 좋겠어.');
      targetCategories.addAll(const ['저칼로리', '짭짤']);
      reasonParts.add('속이 불편할 때는 담백하고 부담이 적은 쪽이 더 안전해요.');
      memoryNote = '속이 예민할 때 담백한 조합 선호';
    }
    if (matchedMoods.contains('hot')) {
      empathy.add('지금은 열감을 낮추고 진정시키는 쪽이 더 맞겠어.');
      targetCategories.addAll(const ['새콤', '저칼로리']);
      reasonParts.add('열이 오르거나 답답할 때는 시원하고 담백한 느낌의 조합이 덜 부담스러워요.');
      memoryNote = '열감이 있을 때 시원한 조합 선호';
    }
    if (isDieting) {
      empathy.add('지금은 다이어트를 해치지 않으면서도 버틸 수 있는 선택이 중요해 보여.');
      targetCategories.addAll(const ['저칼로리', '새콤']);
      reasonParts.add(
        '다이어트 중이면 칼로리 부담이 덜하고, 당이 과하지 않으면서도 식단 흐름을 덜 깨는 조합이 더 잘 맞아요.',
      );
      memoryNote = '다이어트 중 가벼운 조합 선호';
    }
    if (wantsLightMeal) {
      targetCategories.addAll(const ['저칼로리', '새콤']);
      reasonParts.add('지금은 속이 무겁지 않은 쪽이 더 중요해 보여서 가볍고 깔끔한 조합을 우선으로 볼게요.');
    }
    if (wantsProtein) {
      targetCategories.add('저칼로리');
      reasonParts.add('단백질을 챙기고 싶다면 닭가슴살, 계란, 요거트처럼 포만감과 영양 밸런스가 있는 조합이 유리해요.');
      memoryNote = '단백질 중심 조합 선호';
    }
    if (wantsSatiety) {
      targetCategories.addAll(const ['저칼로리', '짭짤']);
      reasonParts.add('포만감이 필요할 땐 너무 달기만 한 조합보다 든든하게 버텨주는 조합이 더 만족도가 높아요.');
    }
    if (matchedSituationTags.isNotEmpty) {
      targetCategories.addAll(matchedSituationTags);
      reasonParts.add('지금 말해준 상황 태그와 비슷한 맥락의 조합도 같이 우선해서 볼게요.');
    }
    if (avoidsSugar) {
      targetCategories.addAll(const ['저칼로리', '짭짤', '새콤']);
      reasonParts.add('당을 줄이고 싶다면 달달한 조합은 뒤로 두고, 담백하거나 상큼한 쪽을 먼저 보는 게 좋아요.');
    }
    if (lateNight && (isDieting || wantsLightMeal)) {
      reasonParts.add('늦은 시간에는 자극적이거나 무거운 것보다 다음 날 부담이 적은 조합이 더 잘 맞을 수 있어요.');
    }
    if (budget != null && explicitBudget != null) {
      reasonParts.add('$budget원을 넘지 않는 조합만 보여줄게요.');
      memoryNote = '예산 $budget원 이하 조합 선호';
    } else if (budget != null) {
      reasonParts.add('현재 입력한 예산 $budget원을 넘지 않는 조합만 보여줄게요.');
    } else if (minimumPrice != null) {
      reasonParts.add('${_formatWon(minimumPrice)} 이상 가격의 조합만 보여줄게요.');
    }
    if (isNeedFastAnswer) {
      targetCategories.add('시간절약');
      reasonParts.add('시간이 부족한 상황이라 바로 먹거나 짧게 준비할 수 있는 조합을 먼저 볼게요.');
    }
    final mealCalorieRange = setup.mealCalorieRange;
    if (useAgeCalorieGuide && wantsFullMeal && mealCalorieRange != null) {
      reasonParts.add(
        '만 ${setup.age}세의 한 끼 참고 범위인 ${mealCalorieRange.label}에 가까운 조합을 우선으로 볼게요.',
      );
    } else if (!useAgeCalorieGuide && wantsFullMeal) {
      reasonParts.add('이번에는 연령별 한 끼 칼로리 범위를 제외하고 취향과 현재 상황만으로 골라볼게요.');
    }

    if (targetCategories.isEmpty) {
      targetCategories.addAll(setup.favoriteTastes);
    }

    final recognizedState =
        matchedMoods.isNotEmpty ||
        analysis.recognizedSituation ||
        isDieting ||
        wantsLightMeal ||
        wantsProtein ||
        wantsSatiety ||
        avoidsSugar ||
        lateNight ||
        explicitBudget != null ||
        isNeedFastAnswer ||
        hasMeaningfulAiContext;
    final wantsRecommendation =
        shouldForceRecommendation ||
        isFoodRequest ||
        isNeedFastAnswer ||
        isYesToRecommendation;
    if (isNoToRecommendation) {
      final noReply = matchedMoods.contains('happy')
          ? '좋아, 오늘 기분 좋은 얘기부터 더 들어볼게. 뭐가 제일 뿌듯했는지 말해줘도 좋고 그냥 수다 떨어도 괜찮아.'
          : '좋아, 바로 추천으로 가지 말고 그냥 얘기 이어가자. 지금 네 상태를 더 듣고 있다가 정말 필요할 때만 같이 골라볼게.';
      return _BotReply(
        text: noReply,
        memoryNote: '추천 없이 대화 이어가기',
        recommendedPostIds: const <String>[],
      );
    }
    if (recognizedState && !wantsRecommendation) {
      final neutralLead = budget != null
          ? '${_formatWon(budget)}을 넘지 않는 예산 조건으로 기억했어.'
          : minimumPrice != null
          ? '${_formatWon(minimumPrice)} 이상 가격 조건으로 기억했어.'
          : '말해준 상황을 기준으로 조건을 정리했어.';
      final askText = matchedMoods.contains('happy')
          ? '${empathy.isEmpty ? '좋은 일이 있었던 것 같아.' : empathy.join(' ')}\n\n지금 분위기라면 달달하거나 상큼한 쪽이 잘 맞을 것 같아. 바로 추천으로 갈 수도 있지만, 오늘 기분 좋았던 이유를 조금만 더 말해줘도 그쪽 결에 맞춰서 더 자연스럽게 골라줄 수 있어.'
          : '${empathy.isEmpty ? neutralLead : empathy.join(' ')}\n\n${reasonParts.isEmpty ? '예산과 취향을 기준으로 고를 수 있어.' : reasonParts.first}\n\n바로 추천으로 갈 수도 있고, 지금 제일 신경 쓰이는 게 예산인지 맛인지 속 편한지부터 같이 정리해도 돼.';
      return _BotReply(
        text: askText,
        memoryNote: memoryNote,
        recommendedPostIds: const <String>[],
        resolvedBudget: budget,
        minimumPrice: minimumPrice,
        contextPrompt: effectivePrompt,
        useAgeCalorieGuide: useAgeCalorieGuide,
        shouldSyncBudget: shouldSyncBudget,
      );
    }
    if (!wantsRecommendation) {
      final followUp = isAskingForEmpathy
          ? '지금은 추천부터 바로 하지 말고, 왜 그렇게 느끼는지부터 천천히 말해줘도 돼. 내가 분위기 맞춰서 같이 정리해볼게.'
          : analysis.hasPositiveSignal
          ? '좋은 쪽으로 감정이 올라와 있는 것 같아. 지금 제일 크게 남는 게 신남인지 뿌듯함인지 후련함인지 말해주면 대화도 더 자연스럽게 이어갈 수 있어.'
          : _buildBotConversationFollowUp(
              prompt: prompt,
              setup: setup,
              lastAssistantMessage: lastAssistantMessage,
            );
      return _BotReply(
        text: followUp,
        memoryNote: matchedMoods.isEmpty ? '일상 대화 유지' : memoryNote,
        recommendedPostIds: const <String>[],
      );
    }

    if (budget == null && minimumPrice == null) {
      return const _BotReply(
        text:
            '추천할 때 넘지 말아야 할 현재 예산을 입력해줘. 위 예산 칸에 적거나 “5천 원 있는데 추천해줘”처럼 말해도 돼.',
        memoryNote: '추천 전 현재 예산 확인 필요',
        recommendedPostIds: <String>[],
      );
    }

    final priceConstraintLabel = budget != null
        ? '${_formatWon(budget)} 이하'
        : '${_formatWon(minimumPrice!)} 이상';
    final ranked =
        recommendationPool
            .where(
              (post) =>
                  !excludedPostIds.contains(post.id) &&
                  BotBudgetRules.allowsPrice(
                    priceMin: post.priceMin,
                    priceMax: post.priceMax,
                    maximumBudget: budget,
                    minimumPrice: minimumPrice,
                  ),
            )
            .toList()
          ..sort(
            (a, b) =>
                _scorePost(
                  b,
                  setup,
                  likedPosts,
                  targetCategories.toList(),
                  prompt: recommendationPrompt,
                  useAgeCalorieGuide: useAgeCalorieGuide,
                ) -
                _scorePost(
                  a,
                  setup,
                  likedPosts,
                  targetCategories.toList(),
                  prompt: recommendationPrompt,
                  useAgeCalorieGuide: useAgeCalorieGuide,
                ),
          );
    final recommendations = ranked.take(3).toList();

    final recommendationText = recommendations.isEmpty
        ? excludedPostIds.isNotEmpty
              ? '현재 조건과 $priceConstraintLabel에서 새로 보여줄 게시물이 더 없어요.'
              : '$priceConstraintLabel 조건으로 추천할 수 있는 게시물이 아직 없어요.'
        : recommendations
              .map(
                (post) =>
                    '• ${post.title} (${post.priceLabel}${post.calories == null ? '' : ' · ${post.calories}kcal'})',
              )
              .join('\n');
    final empathyText = empathy.isEmpty
        ? '예산과 평소 맛 취향을 기준으로 골랐어.'
        : empathy.join(' ');
    final reasonText = reasonParts.isEmpty
        ? '지금 메시지에서는 특정 감정보다 평소 좋아하는 맛과 좋아요 패턴을 더 크게 반영했어요.'
        : reasonParts.join(' ');
    final closing = isAskingForEmpathy
        ? '원하면 이 셋 중에서 지금 제일 끌리는 쪽을 같이 더 좁혀볼게.'
        : '좋아요 기록과 초기설정을 같이 보고 골라봤어. 마음에 걸리는 후보가 있으면 비교도 바로 해줄게.';
    final replyText =
        '$empathyText\n\n$reasonText\n\n$closing\n$recommendationText';

    return _BotReply(
      text: replyText,
      memoryNote: memoryNote,
      recommendedPostIds: recommendations.map((post) => post.id).toList(),
      resolvedBudget: budget,
      minimumPrice: minimumPrice,
      contextPrompt: effectivePrompt,
      useAgeCalorieGuide: useAgeCalorieGuide,
      shouldSyncBudget: shouldSyncBudget,
    );
  }

  int _scorePost(
    Post post,
    BotSetup setup,
    List<Post> likedPosts,
    List<String> targetCategories, {
    required String prompt,
    required bool useAgeCalorieGuide,
  }) {
    var score = 0;
    final normalizedCategories = post.categories
        .map(_normalizeCategory)
        .toSet();
    final searchableText = '${post.title} ${post.content}'.toLowerCase();
    final wantsDiet = _hasAny(prompt, const [
      '다이어트',
      '살 빼',
      '살빼',
      '감량',
      '칼로리',
      '저칼로리',
    ]);
    final wantsProtein = _hasAny(prompt, const [
      '단백질',
      'protein',
      '근손실',
      '운동 후',
      '운동끝',
      '헬스',
    ]);
    final wantsLightMeal = _hasAny(prompt, const [
      '가볍게',
      '부담 없',
      '안 무거운',
      '속 편한',
      '클린',
      '야식',
    ]);
    final wantsFullMeal = _hasAny(prompt, const [
      '한끼',
      '한 끼',
      '식사',
      '끼니',
      '아침',
      '점심',
      '저녁',
      '밥',
      '배고',
      '든든',
    ]);
    final avoidsSugar = _hasAny(prompt, const [
      '당 줄',
      '당류',
      '단 거 말고',
      '덜 단',
      '무가당',
    ]);
    final promptSituationTags = _extractPromptSituationTags(prompt);

    for (final category in targetCategories.map(_normalizeCategory)) {
      if (normalizedCategories.contains(category)) score += 5;
    }
    for (final tag in promptSituationTags.map(_normalizeCategory)) {
      if (normalizedCategories.contains(tag)) score += 6;
    }
    for (final liked in likedPosts) {
      if (liked.categories
          .map(_normalizeCategory)
          .any(normalizedCategories.contains)) {
        score += 2;
      }
    }
    for (final entry in setup.priorityValues.asMap().entries) {
      final priority = entry.value;
      final weight = entry.key == 0 ? 9 : 6;
      if (normalizedCategories.contains(priority)) {
        score += weight;
      }
      if (priority == '저칼로리' && post.calories != null) {
        score += post.calories! <= 450 ? weight : -2;
      }
      if (priority == '가성비' && post.priceMax > 0 && post.priceMax <= 4000) {
        score += weight;
      }
      if (priority == '시간절약' &&
          (_hasAny(searchableText, const ['바로', '간단', '전자레인지', '빠르게']) ||
              post.details.prepTimeTag.contains('5분'))) {
        score += weight;
      }
      if (priority == '호불호') {
        score += (post.likes + post.dislikes) ~/ 12;
      }
      if (priority == '트렌드') {
        score += post.likes ~/ 15;
      }
    }

    final postTasteRatings = _postTasteRatings(post);
    var allTastesWithinOne = true;
    for (final taste in const <String>['달달', '매콤', '새콤', '짭짤']) {
      final difference =
          (setup.tasteLevel(taste) - (postTasteRatings[taste] ?? 3)).abs();
      if (difference > 1) allTastesWithinOne = false;
      score += switch (difference) {
        0 => 4,
        1 => 2,
        2 => -3,
        _ => -7,
      };
    }
    if (allTastesWithinOne) {
      score += 12;
    }

    if (wantsDiet &&
        (normalizedCategories.contains('저칼로리') ||
            normalizedCategories.contains('건강'))) {
      score += 6;
    }
    if (wantsDiet && post.priceMax <= 5200) {
      score += 1;
    }
    if (wantsProtein &&
        _hasAny(searchableText, const ['닭가슴살', '계란', '구운계란', '요거트', '단백질'])) {
      score += 7;
    }
    if (wantsLightMeal &&
        _hasAny(searchableText, const [
          '요거트',
          '컵과일',
          '탄산수',
          '계란',
          '샐러드',
          '닭가슴살',
        ])) {
      score += 5;
    }
    if (avoidsSugar && normalizedCategories.contains('달달')) {
      score -= 5;
    }
    if (wantsDiet && _hasAny(searchableText, const ['초코', '바닐라', '프레첼', '빵'])) {
      score -= 2;
    }
    final mealCalorieRange = setup.mealCalorieRange;
    final calories = post.calories;
    if (useAgeCalorieGuide && mealCalorieRange != null && calories != null) {
      final isWithinRange =
          calories >= mealCalorieRange.minCalories &&
          calories <= mealCalorieRange.maxCalories;
      if (isWithinRange) {
        score += wantsFullMeal ? 12 : 5;
      } else if (calories > mealCalorieRange.maxCalories) {
        final excessRatio = calories / mealCalorieRange.maxCalories;
        score += wantsFullMeal
            ? (excessRatio > 1.25 ? -14 : -7)
            : (excessRatio > 1.25 ? -5 : -2);
      } else if (wantsFullMeal &&
          calories < (mealCalorieRange.minCalories * 0.8).round()) {
        score -= 6;
      }
    }
    return score;
  }

  Map<String, int> _postTasteRatings(Post post) {
    if (post.reviews.isNotEmpty) {
      int average(int Function(PostReview review) pick) =>
          (post.reviews.map(pick).reduce((a, b) => a + b) / post.reviews.length)
              .round()
              .clamp(1, 5);
      return <String, int>{
        '달달': average((review) => review.sweet),
        '매콤': average((review) => review.spicy),
        '새콤': average((review) => review.sour),
        '짭짤': average((review) => review.salty),
      };
    }

    final text = '${post.title} ${post.content} ${post.categories.join(' ')}';
    return <String, int>{
      '달달': _hasAny(text, const ['달달', '초코', '바닐라', '젤리', '디저트']) ? 4 : 2,
      '매콤': _hasAny(text, const ['매콤', '매운', '불닭', '고추']) ? 4 : 2,
      '새콤': _hasAny(text, const ['새콤', '상큼', '레몬', '탄산']) ? 4 : 2,
      '짭짤': _hasAny(text, const ['짭짤', '라면', '김밥', '핫바', '치즈']) ? 4 : 2,
    };
  }

  String _normalizeCategory(String category) {
    final normalized = _cleanTagLabel(category);
    if (normalized.contains('짭')) return '짭짤';
    return normalized;
  }

  bool _hasAny(String source, List<String> needles) {
    return needles.any(source.contains);
  }

  String _buildBotConversationFollowUp({
    required String prompt,
    required BotSetup setup,
    required BotMessage? lastAssistantMessage,
  }) {
    final normalized = prompt.toLowerCase();
    if (_hasAny(normalized, const ['뭐 먹을지 모르겠', '결정 못', '고민', '모르겠어'])) {
      return '지금은 선택지가 너무 많아서 더 헷갈리는 느낌일 수 있겠네. 일단 예산, 배고픈 정도, 달달한지 짭짤한지 중 하나만 골라서 말해주면 거기서부터 좁혀볼게.';
    }
    if (_hasAny(normalized, const ['피곤', '지쳐', '힘들', '귀찮'])) {
      return '오늘 에너지가 많이 빠진 것 같아. 지금은 복잡하게 고르기보다 바로 먹기 편한 쪽이 나은지, 아니면 잠깐 기분 전환되는 맛이 필요한지만 알려줘.';
    }
    if (_hasAny(normalized, const ['기분 좋아', '행복', '신나', '좋았어'])) {
      return '좋은 쪽으로 마음이 올라와 있네. 그 기분을 더 살리고 싶으면 상큼한 쪽이 나은지, 보상처럼 달달한 쪽이 나은지 말해줘.';
    }
    if (_hasAny(normalized, const ['속 안 좋아', '불편', '더부룩', '메스꺼'])) {
      return '속이 예민하면 무작정 자극적인 걸 추천하는 건 별로일 수 있어. 지금은 따뜻하고 부담 적은 쪽이 필요한지, 그냥 가볍게 때우는 정도면 되는지부터 같이 보자.';
    }
    if (lastAssistantMessage?.recommendedPostIds.isNotEmpty == true) {
      return '아까 추천한 후보 기준으로 더 좁혀도 돼. 지금은 가성비가 더 중요한지, 맛이 확 당기는 게 더 중요한지 말해주면 한 단계 더 정리해줄게.';
    }
    return '추천이 급하지 않으면 그냥 편하게 이야기해도 괜찮아. 지금 제일 큰 건 배고픔인지, 기분인지, 예산인지 한 가지만 말해주면 거기부터 맞춰볼게.';
  }

  String _normalizeAiEmotion(String emotion) {
    return switch (emotion.toLowerCase()) {
      'happy' || 'excited' || 'relieved' => 'happy',
      'sad' || 'lonely' || 'down' => 'down',
      'angry' || 'stressed' || 'stress' => 'stress',
      'anxious' || 'nervous' => 'anxious',
      'tired' || 'exhausted' => 'tired',
      'sick' || 'unwell' => 'sick',
      _ => '',
    };
  }

  List<String> _extractPromptSituationTags(String normalized) {
    const situationAliases = <String, List<String>>{
      '등교길 추천': ['등교길', '등교', '학교 가는 길'],
      '야식 추천': ['야식', '늦은 밤', '밤에 먹', '자기 전'],
      '간식 추천': ['간식', '군것질', '심심풀이'],
      '점심 대용': ['점심 대용', '점심 대신', '점심으로', '점심'],
      '아침 대용': ['아침 대용', '아침 대신', '아침으로', '아침'],
      '공부할 때 추천': ['공부할 때', '공부 중', '시험공부', '과제할 때'],
      '드라이브 간식': ['드라이브', '차에서 먹', '운전할 때'],
      '영화 보며 먹기 좋아요': ['영화 볼 때', '영화 보며', '넷플릭스 볼 때'],
      '여행 갈 때 챙기기 좋아요': ['여행 갈 때', '여행용', '여행 챙길'],
      '피크닉 추천': ['피크닉', '소풍'],
      '운동 후 추천': ['운동 후', '운동끝', '헬스 끝', '헬스 후'],
      '다이어트 할 때 추천': ['다이어트', '감량', '저칼로리', '식단 중'],
    };
    final matched = <String>[];
    for (final entry in situationAliases.entries) {
      if (_hasAny(normalized, entry.value)) {
        matched.add(entry.key);
      }
    }
    return matched;
  }

  _SituationAnalysis _analyzeSituationPrompt(String normalized) {
    final moods = <String>[];
    var summary = '';
    var memoryNote = '상황 분석 기반 대화';

    final moodBuckets = <String, List<String>>{
      'happy': [
        '행복',
        '기뻐',
        '기분 좋아',
        '좋은 일',
        '신나',
        '들떠',
        '설레',
        '즐거',
        '재밌',
        '뿌듯',
        '후련',
        '상쾌',
        '감사',
        '고마워',
        '고맙',
        '안도',
        '기대',
        '만족',
      ],
      'down': [
        '우울',
        '무기력',
        '힘들',
        '슬퍼',
        '처졌',
        '공허',
        '상실',
        '그리워',
        '허무',
        '외롭',
        '쓸쓸',
      ],
      'stress': [
        '화나',
        '열받',
        '짜증',
        '스트레스',
        '빡쳐',
        '빡치',
        '억울',
        '답답',
        '분개',
        '질투',
        '원망',
      ],
      'anxious': ['불안', '긴장', '떨', '초조', '걱정', '시험', '면접', '두려', '압박'],
      'surprised': ['당황', '충격', '경악', '감탄', '놀랐', '놀람'],
      'disgust': ['역겨', '거부감', '불쾌', '정떨어'],
      'tired': ['피곤', '졸려', '지쳐', '야근', '학원 끝', '출근길', '밤샜', '기운 없'],
      'sick': ['속쓰', '메스껍', '울렁', '체했', '배불러', '입맛 없'],
      'hot': ['열이', '화끈', '더워', '머리 식히'],
    };

    for (final entry in moodBuckets.entries) {
      if (_hasAny(normalized, entry.value)) {
        moods.add(entry.key);
      }
    }

    final nearestMoodHints = <String, List<String>>{
      'happy': [
        '해방감',
        '벅차',
        '날아갈',
        '살겠다',
        '신남',
        '좋았다',
        '좋겠',
        '행복한듯',
        '통쾌',
        '희망',
        '평온',
        '안정',
      ],
      'down': ['허전', '멍함', '울적', '축 처', '맥 빠', '심란', '향수', '고독', '혼자 있고 싶'],
      'stress': ['답없', '개빡', '분통', '열불', '폭발', '짜증남', '귀찮아죽', '신경질', '예민'],
      'anxious': [
        '조마조마',
        '마음이 복잡',
        '불편',
        '눈치',
        '부담',
        '조급',
        '진정 안',
        '긴장됨',
        '무서',
        '공포',
        '압박감',
        '상처받',
        '배신감',
      ],
      'surprised': ['얼떨떨', '어안이벙벙', '멘붕', '예상밖', '갑작스러', '깜짝'],
      'disgust': ['정내미', '징그러', '토할', '비위', '꺼림칙'],
      'tired': [
        '녹초',
        '방전',
        '기진맥진',
        '털림',
        '퍼짐',
        '힘이 안',
        '축남',
        '노곤',
        '멍하다',
        '좌절',
        '실패감',
      ],
      'sick': ['속 안좋', '니글', '답답한 속', '소화 안', '울렁거', '더부룩', '물린', '메슥'],
      'hot': ['열받아서 뜨거', '화끈거', '머리 뜨거', '식혀야', '진정 필요'],
    };

    if (moods.isEmpty) {
      String? nearestMood;
      for (final entry in nearestMoodHints.entries) {
        if (_hasAny(normalized, entry.value)) {
          nearestMood = entry.key;
          break;
        }
      }
      if (nearestMood != null) {
        moods.add(nearestMood);
        memoryNote = '유사 감정 표현을 가장 가까운 감정군으로 해석';
        summary = switch (nearestMood) {
          'happy' => '정확히 같은 표현은 아니어도, 지금 말한 감정은 기쁨이나 후련함 쪽에 더 가까워 보여.',
          'down' => '정확히 같은 표현은 아니어도, 지금 상태는 가라앉거나 허전한 마음 쪽에 가까워 보여.',
          'stress' => '정확히 같은 표현은 아니어도, 답답함이나 스트레스가 쌓인 쪽에 더 가까워 보여.',
          'anxious' => '정확히 같은 표현은 아니어도, 긴장되거나 마음이 복잡한 쪽으로 읽혀.',
          'tired' => '정확히 같은 표현은 아니어도, 많이 지치고 힘이 빠진 상태에 가까워 보여.',
          'sick' => '정확히 같은 표현은 아니어도, 몸이나 속이 편하지 않은 쪽에 가까워 보여.',
          'hot' => '정확히 같은 표현은 아니어도, 열감이 오르거나 진정이 필요한 상태에 가까워 보여.',
          _ => '',
        };
      }
    }

    if (_hasAny(normalized, const [
      '기말 끝',
      '시험 끝',
      '끝났다',
      '드디어 끝',
      '해방',
      '종강',
    ])) {
      if (!moods.contains('happy')) moods.add('happy');
      summary = '큰 일정이 끝나서 후련하고 들뜬 기분일 가능성이 커 보여.';
      memoryNote = '큰 일정 종료 후 해방감 인식';
    }
    if (_hasAny(normalized, const [
      '100점',
      '만점',
      '합격',
      '붙었',
      '성공',
      '칭찬받',
      '상 받',
      '잘했대',
    ])) {
      if (!moods.contains('happy')) moods.add('happy');
      summary = '좋은 결과가 있어서 뿌듯하고 기분이 꽤 좋아진 상태로 느껴져.';
      memoryNote = '성취 상황에서 기쁨과 뿌듯함 인식';
    }
    if (_hasAny(normalized, const [
      '감사',
      '고마워',
      '고맙',
      '감동',
      '희망',
      '안심',
      '평온',
      '안정',
    ])) {
      if (!moods.contains('happy')) moods.add('happy');
      summary = '지금 감정은 기쁨과 비슷한 결의 따뜻함이나 안정감 쪽으로 읽혀.';
      memoryNote = '따뜻하고 안정적인 긍정 감정 인식';
    }

    if (summary.isEmpty) {
      if (moods.contains('happy')) {
        summary = '좋은 일이 있었거나 말할 때의 분위기가 꽤 밝고 들뜬 쪽으로 느껴져.';
      } else if (moods.contains('down')) {
        summary = '기운이 많이 빠졌거나 마음이 가라앉은 상태로 들려.';
      } else if (moods.contains('stress')) {
        summary = '스트레스나 짜증이 꽤 쌓인 상태처럼 들려.';
      } else if (moods.contains('anxious')) {
        summary = '긴장되거나 불안한 마음이 먼저 읽혀.';
      } else if (moods.contains('surprised')) {
        summary = '예상 밖의 일 때문에 놀라거나 당황한 감정이 먼저 읽혀.';
      } else if (moods.contains('disgust')) {
        summary = '거부감이나 불쾌함처럼 밀어내고 싶은 감정이 느껴져.';
      } else if (moods.contains('tired')) {
        summary = '몸이나 머리가 많이 지친 상태로 보여.';
      } else if (moods.contains('sick')) {
        summary = '속이 예민하거나 몸 상태가 편하지 않은 쪽으로 느껴져.';
      } else if (moods.contains('hot')) {
        summary = '열감이 있거나 답답해서 식히고 싶은 상태처럼 들려.';
      }
    }

    return _SituationAnalysis(
      moods: moods,
      emotionSummary: summary,
      hasPositiveSignal: moods.contains('happy'),
      recognizedSituation: moods.isNotEmpty || summary.isNotEmpty,
      memoryNote: memoryNote,
    );
  }

  void _openRecommendedPost(String postId) {
    final post = _findPostById(postId);
    if (post == null) return;
    unawaited(_openPostDetail(post, switchToCommunication: true));
  }

  Future<void> _openFeaturePost(PostFeatureInfo feature) async {
    var post = _findPostById(feature.id);
    if (post == null) {
      final allPosts = await _ensureFeaturePostPool();
      post = allPosts.where((item) => item.id == feature.id).firstOrNull;
    }
    if (!mounted || post == null) return;
    await _openPostDetail(post, switchToCommunication: true);
  }

  void _openHighlightCollection(HighlightCollectionType type) {
    unawaited(_openHighlightCollectionAsync(type));
  }

  Future<void> _openHighlightCollectionAsync(
    HighlightCollectionType type,
  ) async {
    final allPosts = await _ensureFeaturePostPool();
    if (!mounted) return;
    final posts = switch (type) {
      HighlightCollectionType.newProduct =>
        allPosts.where(_postHasNewProduct).toList(),
      HighlightCollectionType.pbProduct =>
        allPosts.where(_postHasPbProduct).toList(),
    };
    final title = switch (type) {
      HighlightCollectionType.newProduct => '신상',
      HighlightCollectionType.pbProduct => 'PB',
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HighlightPostsPage(
          title: title,
          posts: posts,
          currentUser: widget.currentUser,
          onOpenAuthor: _openAuthorProfile,
          onOpenPost: _openPostDetail,
          onToggleLike: _toggleLike,
          onToggleDislike: _toggleDislike,
          onToggleSave: _toggleSavedPost,
          onEditPost: (post) => _openComposer(initialPost: post),
          onDeletePost: _deletePost,
        ),
      ),
    );
  }

  Future<void> _toggleSearchTag(String tag) async {
    setState(() {
      if (tag.isEmpty) {
        _selectedSearchTags.clear();
      } else if (_selectedSearchTags.contains(tag)) {
        _selectedSearchTags.remove(tag);
      } else {
        _selectedSearchTags
          ..clear()
          ..add(tag);
      }
    });
    await _loadPosts();
  }

  void _shufflePosts() {
    setState(() {
      _posts = [..._posts]..shuffle(math.Random());
    });
  }

  Future<PyeonUser?> _fetchAuthorUser(String authorId) async {
    if (authorId == widget.currentUser.id) {
      return widget.currentUser;
    }
    if (widget.environment.dataMode != DataMode.remote) {
      return null;
    }
    try {
      final response = await http
          .get(Uri.parse('${widget.environment.apiBaseUrl}/users/$authorId'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return PyeonUser.fromJson(payload['user'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAuthorProfile(Post post) async {
    if (post.authorId == widget.currentUser.id) {
      _showOwnProfileTab();
      return;
    }
    final allPosts = await _ensureFeaturePostPool();
    final authoredPosts = allPosts
        .where((item) => item.authorId == post.authorId)
        .toList();
    final authorUser = await _fetchAuthorUser(post.authorId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AuthorProfilePage(
          currentUser: widget.currentUser,
          authorUser: authorUser,
          authorPost: post,
          allPosts: allPosts,
          authoredPosts: authoredPosts,
          isPicked: widget.currentUser.pickedAuthorIds.contains(post.authorId),
          onTogglePick: post.authorId == widget.currentUser.id
              ? null
              : () => _togglePickedAuthor(post.authorId),
          onOpenPost: _openPostDetail,
          onOpenAuthorByIdentity: _openAuthorByIdentity,
        ),
      ),
    );
  }

  Future<void> _openAuthorByIdentity(
    String authorId,
    String authorNickname,
  ) async {
    if (authorId == widget.currentUser.id) {
      _showOwnProfileTab();
      return;
    }
    final allPosts = await _ensureFeaturePostPool();
    final authoredPosts = allPosts
        .where((item) => item.authorId == authorId)
        .toList();
    final anchorPost = authoredPosts.isNotEmpty
        ? authoredPosts.first
        : Post(
            id: 'virtual-$authorId',
            authorId: authorId,
            authorNickname: authorNickname,
            authorProfileImageUrl: null,
            title: '아직 공개된 게시글이 없어요',
            content: '',
            priceMin: 0,
            priceMax: 0,
            categories: const <String>[],
            likes: 0,
            dislikes: 0,
            comments: const <PostComment>[],
            createdAt: DateTime.now(),
            imageData: null,
            imageUrl: null,
            imageDatas: const <String>[],
            imageUrls: const <String>[],
            details: const PostDetails(
              eatingSteps: <String>[],
              tips: <String>[],
              cautions: <String>[],
              situationTags: <String>[],
              reviewPoints: <String>[],
              prepTimeTag: '',
            ),
            likedByMe: false,
            dislikedByMe: false,
            topFiveEnteredAt: null,
            topWorstEnteredAt: null,
          );
    final authorUser = await _fetchAuthorUser(authorId);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AuthorProfilePage(
          currentUser: widget.currentUser,
          authorUser: authorUser,
          authorPost: anchorPost,
          allPosts: allPosts,
          authoredPosts: authoredPosts,
          isPicked: widget.currentUser.pickedAuthorIds.contains(authorId),
          onTogglePick: authorId == widget.currentUser.id
              ? null
              : () => _togglePickedAuthor(authorId),
          onOpenPost: _openPostDetail,
          onOpenAuthorByIdentity: _openAuthorByIdentity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _selectedTab == AppTab.communication
          ? FloatingActionButton(
              onPressed: () => _openComposer(),
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add, size: 34),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF1FBFF), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(height: 5, color: AppColors.lime),
              Container(
                width: double.infinity,
                color: AppColors.sky,
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Text(
                            '편pick!',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        _UserPill(
                          user: widget.currentUser,
                          onTap: _showOwnProfileTab,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    FeatureTabs(
                      selectedTab: _selectedTab,
                      onChanged: (tab) => setState(() => _selectedTab = tab),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: _buildSelectedPage(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPage() {
    switch (_selectedTab) {
      case AppTab.communication:
        return CommunicationBody(
          loading: _loading,
          error: _error,
          posts: _posts,
          allFeatureInfo: _allFeatureInfo,
          currentUser: widget.currentUser,
          searchController: _searchController,
          minFilterController: _minFilterController,
          maxFilterController: _maxFilterController,
          sortMode: _sortMode,
          selectedTags: _selectedSearchTags,
          likedGenderMajority: _likedGenderMajority,
          scrollController: _communicationScrollController,
          hasMorePosts: _hasMorePosts,
          loadingMore: _loadingMore,
          onReload: _loadPosts,
          onChangeSort: (sortMode) {
            setState(() => _sortMode = sortMode);
            _loadPosts();
          },
          onToggleLike: _toggleLike,
          onToggleDislike: _toggleDislike,
          onToggleSave: _toggleSavedPost,
          onAddComment: _addComment,
          onEditPost: (post) => _openComposer(initialPost: post),
          onDeletePost: _deletePost,
          onOpenAuthor: _openAuthorProfile,
          onOpenPost: _openPostDetail,
          onOpenFeaturePost: _openFeaturePost,
          onToggleSearchTag: _toggleSearchTag,
          onChangeLikedGenderMajority: (value) {
            if (_likedGenderMajority == value) return;
            setState(() => _likedGenderMajority = value);
            unawaited(_loadPosts());
          },
          onOpenCollection: _openHighlightCollection,
          onShuffle: _shufflePosts,
          onScanBarcode: _scanCommunicationBarcode,
        );
      case AppTab.battle:
        return CombinationBattleScreen(
          currentUser: widget.currentUser,
          posts: _allFunctionalPosts,
          repository: widget.repository,
          onUserChanged: widget.onUserChanged,
          onOpenPost: _openPostDetail,
          onOpenAuthor: _openAuthorByIdentity,
        );
      case AppTab.bot:
        if (widget.currentUser.botSetup == null) {
          return BotSetupPage(onComplete: _saveBotSetup);
        }
        return PyeonBotPage(
          currentUser: widget.currentUser,
          posts: _botRecommendationPosts.isEmpty
              ? (_allFunctionalPosts.isEmpty ? _posts : _allFunctionalPosts)
              : _botRecommendationPosts,
          onSend: _sendBotPrompt,
          onMore: _sendMoreBotRecommendations,
          onOpenPost: _openRecommendedPost,
          onResetSetup: _resetBotSetup,
          onResetConversation: _resetCurrentConversation,
        );
      case AppTab.profile:
        return ProfilePage(
          currentUser: widget.currentUser,
          posts: _allFunctionalPosts,
          onUserChanged: widget.onUserChanged,
          onResetBotSetup: _resetBotSetup,
          onLogout: widget.onLogout,
          onOpenPost: _openPostDetail,
          onOpenAuthor: _openAuthorProfile,
          onToggleProfilePublic: _toggleProfilePublic,
        );
    }
  }
}

class CommunicationBody extends StatelessWidget {
  const CommunicationBody({
    super.key,
    required this.loading,
    required this.error,
    required this.posts,
    required this.allFeatureInfo,
    required this.currentUser,
    required this.searchController,
    required this.minFilterController,
    required this.maxFilterController,
    required this.sortMode,
    required this.selectedTags,
    required this.likedGenderMajority,
    required this.scrollController,
    required this.hasMorePosts,
    required this.loadingMore,
    required this.onReload,
    required this.onChangeSort,
    required this.onToggleLike,
    required this.onToggleDislike,
    required this.onToggleSave,
    required this.onAddComment,
    required this.onEditPost,
    required this.onDeletePost,
    required this.onOpenAuthor,
    required this.onOpenPost,
    required this.onOpenFeaturePost,
    required this.onToggleSearchTag,
    required this.onChangeLikedGenderMajority,
    required this.onOpenCollection,
    required this.onShuffle,
    required this.onScanBarcode,
  });

  final bool loading;
  final String? error;
  final List<Post> posts;
  final List<PostFeatureInfo> allFeatureInfo;
  final PyeonUser currentUser;
  final TextEditingController searchController;
  final TextEditingController minFilterController;
  final TextEditingController maxFilterController;
  final SortMode sortMode;
  final Set<String> selectedTags;
  final String? likedGenderMajority;
  final ScrollController scrollController;
  final bool hasMorePosts;
  final bool loadingMore;
  final Future<void> Function() onReload;
  final ValueChanged<SortMode> onChangeSort;
  final Future<void> Function(Post post) onToggleLike;
  final Future<void> Function(Post post) onToggleDislike;
  final Future<void> Function(String postId) onToggleSave;
  final Future<void> Function(Post post, String text) onAddComment;
  final Future<void> Function(Post post) onEditPost;
  final Future<void> Function(Post post) onDeletePost;
  final ValueChanged<Post> onOpenAuthor;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(PostFeatureInfo post) onOpenFeaturePost;
  final Future<void> Function(String tag) onToggleSearchTag;
  final ValueChanged<String?> onChangeLikedGenderMajority;
  final void Function(HighlightCollectionType type) onOpenCollection;
  final VoidCallback onShuffle;
  final Future<void> Function() onScanBarcode;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.limeDeep),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onReload,
                style: FilledButton.styleFrom(backgroundColor: AppColors.lime),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    final featureIndex = allFeatureInfo.isEmpty
        ? posts.map(PostFeatureInfo.fromPost).toList()
        : allFeatureInfo;
    final newProductCount = featureIndex.where(_featureHasNewProduct).length;
    final pbProductCount = featureIndex.where(_featureHasPbProduct).length;
    final trendPicks = _buildCommunityTrendPicks(featureIndex);
    final rowCount = (posts.length / 2).ceil();

    return RefreshIndicator(
      color: AppColors.limeDeep,
      onRefresh: onReload,
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          Toolbar(
            searchController: searchController,
            titleSuggestions: featureIndex.map((post) => post.title).toList(),
            minFilterController: minFilterController,
            maxFilterController: maxFilterController,
            selectedTags: selectedTags,
            likedGenderMajority: likedGenderMajority,
            onSearch: onReload,
            onToggleTag: onToggleSearchTag,
            onChangeLikedGenderMajority: onChangeLikedGenderMajority,
            onShuffle: onShuffle,
            onScanBarcode: onScanBarcode,
          ),
          const SizedBox(height: 12),
          _HighlightNavigation(
            newProductCount: newProductCount,
            pbProductCount: pbProductCount,
            onOpenNew: () =>
                onOpenCollection(HighlightCollectionType.newProduct),
            onOpenPb: () => onOpenCollection(HighlightCollectionType.pbProduct),
          ),
          if (trendPicks.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CommunityTrendStrip(
              picks: trendPicks,
              onOpenPost: (post) => unawaited(onOpenFeaturePost(post)),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '전체 게시글',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SortSelector(
                sortMode: sortMode,
                onChanged: onChangeSort,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 14),
          if (posts.isEmpty)
            const EmptyState()
          else
            ...List.generate(rowCount, (rowIndex) {
              final leftIndex = rowIndex * 2;
              final rightIndex = leftIndex + 1;
              final leftPost = posts[leftIndex];
              final Post? rightPost = rightIndex < posts.length
                  ? posts[rightIndex]
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PostCard(
                        post: leftPost,
                        isMine: leftPost.authorId == currentUser.id,
                        isSaved: currentUser.savedPostIds.contains(leftPost.id),
                        onToggleLike: () => onToggleLike(leftPost),
                        onToggleDislike: () => onToggleDislike(leftPost),
                        onToggleSave: () => onToggleSave(leftPost.id),
                        onEdit: () => onEditPost(leftPost),
                        onDelete: () => onDeletePost(leftPost),
                        onOpenAuthor: () => onOpenAuthor(leftPost),
                        onOpenPost: () => onOpenPost(leftPost),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: rightPost == null
                          ? const SizedBox.shrink()
                          : PostCard(
                              post: rightPost,
                              isMine: rightPost.authorId == currentUser.id,
                              isSaved: currentUser.savedPostIds.contains(
                                rightPost.id,
                              ),
                              onToggleLike: () => onToggleLike(rightPost),
                              onToggleDislike: () => onToggleDislike(rightPost),
                              onToggleSave: () => onToggleSave(rightPost.id),
                              onEdit: () => onEditPost(rightPost),
                              onDelete: () => onDeletePost(rightPost),
                              onOpenAuthor: () => onOpenAuthor(rightPost),
                              onOpenPost: () => onOpenPost(rightPost),
                            ),
                    ),
                  ],
                ),
              );
            }),
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.limeDeep),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppColors.limeDeep, size: 34),
          SizedBox(height: 12),
          Text(
            '아직 보여줄 조합이 없어요',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '검색어나 필터를 바꾸거나 첫 조합을 공유해 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class FeatureTabs extends StatelessWidget {
  const FeatureTabs({
    super.key,
    required this.selectedTab,
    required this.onChanged,
  });

  final AppTab selectedTab;
  final ValueChanged<AppTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = <({AppTab tab, String label})>[
      (tab: AppTab.communication, label: '꿀조합 공유'),
      (tab: AppTab.battle, label: '픽 쇼츠'),
      (tab: AppTab.bot, label: '편봇'),
      (tab: AppTab.profile, label: '내 정보'),
    ];

    return Row(
      children: tabs.map((item) {
        final active = selectedTab == item.tab;
        return Expanded(
          child: InkWell(
            onTap: () => onChanged(item.tab),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withAlpha(210)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? const Color(0xFFCFE2EA) : Colors.transparent,
                ),
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  color: active ? AppColors.navy : const Color(0xFF68859A),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class Toolbar extends StatefulWidget {
  const Toolbar({
    super.key,
    required this.searchController,
    required this.titleSuggestions,
    required this.minFilterController,
    required this.maxFilterController,
    required this.selectedTags,
    required this.likedGenderMajority,
    required this.onSearch,
    required this.onToggleTag,
    required this.onChangeLikedGenderMajority,
    required this.onShuffle,
    required this.onScanBarcode,
  });

  final TextEditingController searchController;
  final List<String> titleSuggestions;
  final TextEditingController minFilterController;
  final TextEditingController maxFilterController;
  final Set<String> selectedTags;
  final String? likedGenderMajority;
  final Future<void> Function() onSearch;
  final Future<void> Function(String tag) onToggleTag;
  final ValueChanged<String?> onChangeLikedGenderMajority;
  final VoidCallback onShuffle;
  final Future<void> Function() onScanBarcode;

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  bool _categoriesVisible = false;

  void _showCategories() {
    if (!_categoriesVisible) {
      setState(() => _categoriesVisible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration compactInput(String hint, {IconData? icon}) {
      return inputDecoration(hint).copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 18, color: AppColors.muted),
        prefixIconConstraints: icon == null
            ? null
            : const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: widget.searchController,
                style: const TextStyle(fontSize: 12),
                decoration: compactInput('제목 검색', icon: Icons.search_rounded),
                onTap: _showCategories,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => widget.onSearch(),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 38,
              height: 38,
              child: IconButton.outlined(
                onPressed: widget.onScanBarcode,
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.line),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(38, 38),
                  fixedSize: const Size(38, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                tooltip: '바코드 스캔',
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 60,
              child: TextField(
                controller: widget.minFilterController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 11),
                decoration: compactInput('최소'),
                onTap: _showCategories,
                onSubmitted: (_) => widget.onSearch(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '~',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: widget.maxFilterController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 11),
                decoration: compactInput('최대'),
                onTap: _showCategories,
                onSubmitted: (_) => widget.onSearch(),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 38,
              height: 38,
              child: IconButton.filled(
                onPressed: widget.onSearch,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.lime,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(38, 38),
                  fixedSize: const Size(38, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                tooltip: '검색',
                icon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ],
        ),
        if (widget.searchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          _LiveTitleSuggestions(
            suggestions: _matchingTitleSuggestions(
              widget.titleSuggestions,
              widget.searchController.text,
            ),
            onSelected: (title) {
              widget.searchController.text = title;
              widget.searchController.selection = TextSelection.collapsed(
                offset: title.length,
              );
              setState(() {});
              unawaited(widget.onSearch());
            },
          ),
        ],
        const SizedBox(height: 8),
        _HeartGenderFilter(
          value: widget.likedGenderMajority,
          onChanged: widget.onChangeLikedGenderMajority,
        ),
        if (_categoriesVisible) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                '카테고리',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _categoriesVisible = false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: const Icon(Icons.expand_less_rounded, size: 16),
                label: const Text(
                  '접기',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestedSearchCategories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 5),
              itemBuilder: (context, index) {
                final category = index == 0
                    ? '전체'
                    : _suggestedSearchCategories[index - 1];
                final isAll = index == 0;
                final selected = isAll
                    ? widget.selectedTags.isEmpty
                    : widget.selectedTags.contains(category);
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () =>
                      unawaited(widget.onToggleTag(isAll ? '' : category)),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEAF5D0) : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFB7D66D)
                            : AppColors.line,
                      ),
                    ),
                    child: Text(
                      isAll ? category : '#$category',
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF5B7715)
                            : AppColors.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onShuffle,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                backgroundColor: const Color(0xFFF5F9FB),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 15),
              label: const Text(
                '랜덤 셔플',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeartGenderFilter extends StatelessWidget {
  const _HeartGenderFilter({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <String?, String>{
      null: '선택 안함',
      'male': '남자',
      'female': '여자',
    };

    return Row(
      children: [
        const Text(
          '하트 성비',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7FA),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: options.entries.map((option) {
                final selected = value == option.key;
                return Expanded(
                  child: InkWell(
                    onTap: () => onChanged(option.key),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: selected
                            ? const [
                                BoxShadow(
                                  color: Color(0x140D3657),
                                  blurRadius: 7,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        option.value,
                        maxLines: 1,
                        style: TextStyle(
                          color: selected
                              ? AppColors.navy
                              : const Color(0xFF7A8F9F),
                          fontSize: 10.5,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveTitleSuggestions extends StatelessWidget {
  const _LiveTitleSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final title = suggestions[index];
          return ActionChip(
            onPressed: () => onSelected(title),
            avatar: const Icon(Icons.search_rounded, size: 15),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.line),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

InputDecoration inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0xFFB5BDC8),
      fontWeight: FontWeight.w600,
    ),
    filled: true,
    fillColor: const Color(0xFFFBFEFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDDE7EF)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFDDE7EF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.lime, width: 1.5),
    ),
  );
}

class SortSelector extends StatelessWidget {
  const SortSelector({
    super.key,
    required this.sortMode,
    required this.onChanged,
    this.compact = false,
  });

  final SortMode sortMode;
  final ValueChanged<SortMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    String labelFor(SortMode mode) {
      switch (mode) {
        case SortMode.latest:
          return '최신순';
        case SortMode.popular:
          return '인기순';
        case SortMode.worst:
          return '최악순';
      }
    }

    return PopupMenuButton<SortMode>(
      onSelected: onChanged,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFD9E5EB)),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: SortMode.latest, child: Text('최신순')),
        PopupMenuItem(value: SortMode.popular, child: Text('인기순')),
        PopupMenuItem(value: SortMode.worst, child: Text('최악순')),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 14,
          vertical: compact ? 7 : 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBFD),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9E5EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelFor(sortMode),
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Color(0xFF7590A1),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightNavigation extends StatelessWidget {
  const _HighlightNavigation({
    required this.newProductCount,
    required this.pbProductCount,
    required this.onOpenNew,
    required this.onOpenPb,
  });

  final int newProductCount;
  final int pbProductCount;
  final VoidCallback onOpenNew;
  final VoidCallback onOpenPb;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required String label,
      required String caption,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.receipt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(
          label: '신상',
          caption: '$newProductCount개',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF149857),
          onTap: onOpenNew,
        ),
        const SizedBox(width: 8),
        button(
          label: 'PB',
          caption: '$pbProductCount개',
          icon: Icons.local_offer_rounded,
          color: const Color(0xFF652F8F),
          onTap: onOpenPb,
        ),
      ],
    );
  }
}

class HighlightPostsPage extends StatefulWidget {
  const HighlightPostsPage({
    super.key,
    required this.title,
    required this.posts,
    required this.currentUser,
    required this.onOpenAuthor,
    required this.onOpenPost,
    required this.onToggleLike,
    required this.onToggleDislike,
    required this.onToggleSave,
    required this.onEditPost,
    required this.onDeletePost,
  });

  final String title;
  final List<Post> posts;
  final PyeonUser currentUser;
  final ValueChanged<Post> onOpenAuthor;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(Post post) onToggleLike;
  final Future<void> Function(Post post) onToggleDislike;
  final Future<void> Function(String postId) onToggleSave;
  final Future<void> Function(Post post) onEditPost;
  final Future<void> Function(Post post) onDeletePost;

  @override
  State<HighlightPostsPage> createState() => _HighlightPostsPageState();
}

class _HighlightPostsPageState extends State<HighlightPostsPage> {
  SortMode _sortMode = SortMode.latest;

  List<Post> get _sortedPosts {
    final sorted = [...widget.posts];
    sorted.sort((a, b) {
      return switch (_sortMode) {
        SortMode.latest => b.createdAt.compareTo(a.createdAt),
        SortMode.popular =>
          b.likes != a.likes
              ? b.likes.compareTo(a.likes)
              : b.createdAt.compareTo(a.createdAt),
        SortMode.worst =>
          b.dislikes != a.dislikes
              ? b.dislikes.compareTo(a.dislikes)
              : b.createdAt.compareTo(a.createdAt),
      };
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final posts = _sortedPosts;
    final rowCount = (posts.length / 2).ceil();
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: rowCount + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${posts.length}개 조합',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SortSelector(
                    sortMode: _sortMode,
                    onChanged: (value) => setState(() => _sortMode = value),
                  ),
                ],
              ),
            );
          }
          final rowIndex = index - 1;
          final leftIndex = rowIndex * 2;
          final rightIndex = leftIndex + 1;
          final leftPost = posts[leftIndex];
          final Post? rightPost = rightIndex < posts.length
              ? posts[rightIndex]
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PostCard(
                    post: leftPost,
                    isMine: leftPost.authorId == widget.currentUser.id,
                    isSaved: widget.currentUser.savedPostIds.contains(
                      leftPost.id,
                    ),
                    onToggleLike: () => widget.onToggleLike(leftPost),
                    onToggleDislike: () => widget.onToggleDislike(leftPost),
                    onToggleSave: () => widget.onToggleSave(leftPost.id),
                    onEdit: () => widget.onEditPost(leftPost),
                    onDelete: () => widget.onDeletePost(leftPost),
                    onOpenAuthor: () => widget.onOpenAuthor(leftPost),
                    onOpenPost: () => widget.onOpenPost(leftPost),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: rightPost == null
                      ? const SizedBox.shrink()
                      : PostCard(
                          post: rightPost,
                          isMine: rightPost.authorId == widget.currentUser.id,
                          isSaved: widget.currentUser.savedPostIds.contains(
                            rightPost.id,
                          ),
                          onToggleLike: () => widget.onToggleLike(rightPost),
                          onToggleDislike: () =>
                              widget.onToggleDislike(rightPost),
                          onToggleSave: () => widget.onToggleSave(rightPost.id),
                          onEdit: () => widget.onEditPost(rightPost),
                          onDelete: () => widget.onDeletePost(rightPost),
                          onOpenAuthor: () => widget.onOpenAuthor(rightPost),
                          onOpenPost: () => widget.onOpenPost(rightPost),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommunityTrendStrip extends StatelessWidget {
  const _CommunityTrendStrip({required this.picks, required this.onOpenPost});

  final List<_CommunityTrendGroup> picks;
  final ValueChanged<PostFeatureInfo> onOpenPost;

  void _openGroup(BuildContext context, _CommunityTrendGroup group) {
    if (group.posts.length == 1) {
      onOpenPost(group.posts.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.62,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE5EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: group.color.withAlpha(22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(group.icon, color: group.color, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.label,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${group.posts.length}개',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: group.posts.isEmpty
                    ? const Center(
                        child: Text(
                          '아직 재평가 조건을 충족한 글이 없어요.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: group.posts.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFE8EEF2)),
                        itemBuilder: (context, index) {
                          final post = group.posts[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 5,
                            ),
                            title: Text(
                              post.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              '하트 ${post.likes} · 후기 ${post.reviewCount}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.muted,
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              onOpenPost(post);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: picks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final item = picks[index];
          final postTitle = item.posts.isEmpty
              ? '아직 해당 글 없음'
              : item.posts.first.title;
          return InkWell(
            onTap: () => _openGroup(context, item),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 178,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: item.color.withAlpha(22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: item.color, size: 19),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          postTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.posts.length > 1
                              ? '${item.caption} · ${item.posts.length}개'
                              : item.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HighlightPostCard extends StatefulWidget {
  const _HighlightPostCard({required this.post, required this.onTap});

  final Post post;
  final Future<void> Function() onTap;

  @override
  State<_HighlightPostCard> createState() => _HighlightPostCardState();
}

class _HighlightPostCardState extends State<_HighlightPostCard> {
  late final PageController _pageController;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _buildPostImages(widget.post);
    final displayCategories = _displayCategories(
      widget.post.categories,
      maxVisible: 2,
    );
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.receipt,
          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              child: SizedBox(
                height: 94,
                child: images.length <= 1
                    ? (images.isEmpty
                          ? GradientPhoto(title: widget.post.title)
                          : images.first)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            itemCount: images.length,
                            onPageChanged: (value) =>
                                setState(() => _pageIndex = value),
                            itemBuilder: (_, index) => images[index],
                          ),
                          Positioned(
                            left: 6,
                            top: 0,
                            bottom: 0,
                            child: _GalleryArrow(
                              icon: Icons.chevron_left_rounded,
                              onTap: _pageIndex == 0
                                  ? null
                                  : () => _pageController.previousPage(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 0,
                            bottom: 0,
                            child: _GalleryArrow(
                              icon: Icons.chevron_right_rounded,
                              onTap: _pageIndex >= images.length - 1
                                  ? null
                                  : () => _pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            ConvenienceProductTitle(
              title: widget.post.title,
              contextText: '${widget.post.title} ${widget.post.content}',
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: Align(
                alignment: Alignment.topLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: displayCategories
                      .map((tag) => _TagPill(label: '#$tag', compact: true))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.isMine,
    required this.isSaved,
    required this.onToggleLike,
    required this.onToggleDislike,
    required this.onToggleSave,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenAuthor,
    required this.onOpenPost,
  });

  final Post post;
  final bool isMine;
  final bool isSaved;
  final Future<void> Function() onToggleLike;
  final Future<void> Function() onToggleDislike;
  final Future<void> Function() onToggleSave;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final VoidCallback onOpenAuthor;
  final Future<void> Function() onOpenPost;

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    final displayCategories = _displayCategories(
      post.categories,
      maxVisible: 2,
    );
    return SizedBox(
      height: 326,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.receipt,
          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
          border: Border.all(color: AppColors.line),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onOpenAuthor,
                  child: _UserAvatar(
                    imageSource: post.authorProfileImageUrl,
                    radius: 13,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: onOpenAuthor,
                        child: Text(
                          post.authorNickname,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF85A0B7),
                          ),
                        ),
                      ),
                      Text(
                        post.createdAtLabel,
                        style: const TextStyle(
                          color: Color(0xFF8CA0B3),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await onEdit();
                      } else if (value == 'delete') {
                        await onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('수정')),
                      PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 5),
            InkWell(
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
              onTap: onOpenPost,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 96,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusSmall,
                      ),
                      child: _PostImageGallery(post: post),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 52,
                    child: ConvenienceProductTitle(
                      title: post.title,
                      contextText: '${post.title} ${post.content}',
                      maxLines: 1,
                      labelTopPadding: 1,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.activeYellow,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          post.priceLabel,
                          style: const TextStyle(
                            color: Color(0xFF332800),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (post.calories != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${post.calories}kcal',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (post.rating > 0)
                        Text(
                          '★ ${post.rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: AppColors.priceRed,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 19,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: displayCategories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 4),
                      itemBuilder: (context, index) => _TagPill(
                        label: '#${displayCategories[index]}',
                        compact: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: ActionChipButton(
                    label: '${post.likedByMe ? '♥' : '♡'} ${post.likes}',
                    active: post.likedByMe,
                    onTap: onToggleLike,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ActionChipButton(
                    label: '👎 ${post.dislikes}',
                    active: post.dislikedByMe,
                    activeColor: const Color(0xFFE8EDF3),
                    activeTextColor: const Color(0xFF38485A),
                    onTap: onToggleDislike,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ActionChipButton(
                    label: isSaved ? '✓ 저장' : '+ 저장',
                    active: isSaved,
                    activeColor: const Color(0xFFE8F4D0),
                    activeTextColor: const Color(0xFF6B8C15),
                    onTap: onToggleSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GradientPhoto extends StatelessWidget {
  const GradientPhoto({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        _fallbackFoodImages[title.hashCode.abs() % _fallbackFoodImages.length];
    return Image.network(
      _displayImageUrl(imageUrl),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF1D6), Color(0xFFEAF7D8)],
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.restaurant_rounded,
          color: AppColors.navy,
          size: 32,
        ),
      ),
    );
  }
}

const List<String> _fallbackFoodImages = <String>[
  'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=700&q=80',
  'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=700&q=80',
  'https://images.unsplash.com/photo-1559847844-5315695dadae?auto=format&fit=crop&w=700&q=80',
  'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=700&q=80',
  'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?auto=format&fit=crop&w=700&q=80',
];

class _PostImageGallery extends StatefulWidget {
  const _PostImageGallery({required this.post});

  final Post post;

  @override
  State<_PostImageGallery> createState() => _PostImageGalleryState();
}

class _PostImageGalleryState extends State<_PostImageGallery> {
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageWidgets = _buildPostImages(widget.post);
    final imageCount = imageWidgets.length;
    if (imageCount == 0) {
      return GradientPhoto(title: widget.post.title);
    }

    if (imageCount == 1) {
      return imageWidgets.first;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: imageCount,
          onPageChanged: (value) => setState(() => _pageIndex = value),
          itemBuilder: (context, index) => imageWidgets[index],
        ),
        Positioned(
          left: 10,
          top: 0,
          bottom: 0,
          child: _GalleryArrow(
            icon: Icons.chevron_left_rounded,
            onTap: _pageIndex == 0
                ? null
                : () => _controller.previousPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
          ),
        ),
        Positioned(
          right: 10,
          top: 0,
          bottom: 0,
          child: _GalleryArrow(
            icon: Icons.chevron_right_rounded,
            onTap: _pageIndex == imageCount - 1
                ? null
                : () => _controller.nextPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
          ),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(110),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_pageIndex + 1}/$imageCount',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(onTap == null ? 110 : 220),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.navy),
        ),
      ),
    );
  }
}

List<Widget> _buildPostImages(Post post) {
  final widgets = <Widget>[];
  for (final imageData in post.allImageDatas) {
    widgets.add(
      Image.memory(
        base64Decode(imageData),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ImageErrorPlaceholder(),
      ),
    );
  }
  for (final imageUrl in post.allImageUrls) {
    widgets.add(
      Image.network(
        _displayImageUrl(imageUrl),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              GradientPhoto(title: post.title),
              const Center(
                child: CircularProgressIndicator(color: AppColors.limeDeep),
              ),
            ],
          );
        },
        errorBuilder: (_, _, _) => const _ImageErrorPlaceholder(),
      ),
    );
  }
  return widgets;
}

class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F5F8),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Color(0xFF8DA0B3), size: 30),
          SizedBox(height: 6),
          Text(
            '이미지 오류',
            style: TextStyle(
              color: Color(0xFF758A9C),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ActionChipButton extends StatelessWidget {
  const ActionChipButton({
    super.key,
    required this.label,
    this.active = false,
    this.activeColor,
    this.activeTextColor,
    this.expanded = false,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color? activeColor;
  final Color? activeTextColor;
  final bool expanded;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? (activeColor ?? const Color(0xFFFFE7EC))
              : const Color(0xFFF6F9FC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active
                ? (activeTextColor ?? const Color(0xFFE44566))
                : const Color(0xFF52697F),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class ComposerPage extends StatelessWidget {
  const ComposerPage({
    super.key,
    required this.repository,
    required this.currentUser,
    this.initialPost,
  });

  final PostRepository repository;
  final PyeonUser currentUser;
  final Post? initialPost;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFE),
      body: SafeArea(
        child: ComposerSheet(
          repository: repository,
          currentUser: currentUser,
          initialPost: initialPost,
          pageMode: true,
        ),
      ),
    );
  }
}

class ComposerSheet extends StatefulWidget {
  const ComposerSheet({
    super.key,
    required this.repository,
    required this.currentUser,
    this.initialPost,
    this.pageMode = false,
  });

  final PostRepository repository;
  final PyeonUser currentUser;
  final Post? initialPost;
  final bool pageMode;

  @override
  State<ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<ComposerSheet> {
  final picker = ImagePicker();
  late final TextEditingController titleController;
  late final TextEditingController contentController;
  late final TextEditingController priceController;
  late final TextEditingController calorieController;
  late final TextEditingController eatingStepsController;
  double rating = 3;

  final List<Uint8List> selectedImageBytes = <Uint8List>[];
  final List<String> selectedImageUrls = <String>[];
  List<String> postTitleIndex = const <String>[];
  bool submitting = false;
  String? error;

  bool get isEditing => widget.initialPost != null;

  @override
  void initState() {
    super.initState();
    final post = widget.initialPost;
    titleController = TextEditingController(text: post?.title ?? '');
    contentController = TextEditingController(text: post?.content ?? '');
    priceController = TextEditingController(
      text: post == null ? '' : '${post.priceMin}',
    );
    calorieController = TextEditingController(
      text: post?.calories == null ? '' : '${post!.calories}',
    );
    rating = post == null || post.rating <= 0 ? 3 : post.rating;
    eatingStepsController = TextEditingController(
      text: <String>[
        ...?post?.details.eatingSteps,
        ...?post?.details.tips,
      ].join('\n'),
    );
    unawaited(_loadPostTitleIndex());
  }

  Future<void> _loadPostTitleIndex() async {
    try {
      final index = await widget.repository.fetchPostFeatureIndex();
      if (!mounted) return;
      setState(() {
        postTitleIndex = index.map((post) => post.title).toList();
      });
    } catch (_) {
      // Suggestions are optional; posting remains available if the index fails.
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    priceController.dispose();
    calorieController.dispose();
    eatingStepsController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => selectedImageBytes.add(bytes));
  }

  Future<void> scanProductCode() async {
    final rawValue = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const ProductScannerPage(),
      ),
    );

    if (!mounted || rawValue == null || rawValue.trim().isEmpty) return;

    try {
      final result = await widget.repository.lookupProductByBarcode(rawValue);
      if (!mounted) return;

      setState(() {
        final nextTitle = result.officialName.trim();
        final currentTitle = titleController.text.trim();
        if (nextTitle.isEmpty) {
          error = null;
          return;
        }
        if (currentTitle.isEmpty) {
          titleController.text = nextTitle;
        } else {
          final normalizedParts = currentTitle
              .split('+')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
          if (!normalizedParts.contains(nextTitle)) {
            titleController.text = '$currentTitle + $nextTitle';
          }
        }
        titleController.selection = TextSelection.collapsed(
          offset: titleController.text.length,
        );
        final productImageUrl = result.imageUrl?.trim();
        if (productImageUrl != null &&
            productImageUrl.isNotEmpty &&
            !selectedImageUrls.contains(productImageUrl)) {
          selectedImageUrls.add(productImageUrl);
        }
        if (result.price != null && result.price! > 0) {
          final current =
              int.tryParse(
                priceController.text.replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0;
          priceController.text = '${current + result.price!}';
        }
        if (result.calories != null && result.calories! > 0) {
          final current =
              int.tryParse(
                calorieController.text.replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0;
          calorieController.text = '${current + result.calories!}';
        }
        error = null;
      });

      _showLookupResultMessage(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('아직 등록되지 않은 상품이거나 조회가 잠시 실패했어요. 제목을 직접 적어 주세요.'),
        ),
      );
    }
  }

  void _showLookupResultMessage(ProductLookupResult result) {
    final location = result.store == null || result.store!.isEmpty
        ? ''
        : ' · ${result.store}';
    final filled = <String>[
      if (result.price != null && result.price! > 0)
        '가격 ${_formatWon(result.price!)}',
      if (result.calories != null && result.calories! > 0)
        '${result.calories}kcal',
    ];
    final filledLabel = filled.isEmpty ? '' : ' · ${filled.join(' · ')} 합산';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.tentative
              ? (result.warning ?? '웹 검색 결과를 바탕으로 임시 상품명을 넣었어요. 정확하지 않을 수 있어요.')
              : result.cached
              ? '등록된 상품명을 불러왔어요$location$filledLabel'
              : '외부 상품 정보에서 정식 상품명을 찾았어요$location$filledLabel',
        ),
      ),
    );
  }

  Future<void> submit() async {
    final title = titleController.text.trim();
    final content = contentController.text.trim();
    final singlePrice = int.tryParse(priceController.text.trim());
    final calories = int.tryParse(calorieController.text.trim());
    final details = PostDetails(
      eatingSteps: _splitLines(eatingStepsController.text),
      tips: const <String>[],
      cautions: const <String>[],
      situationTags: const <String>[],
      reviewPoints: const <String>[],
      prepTimeTag: '',
    );

    final hasImage =
        selectedImageBytes.isNotEmpty ||
        selectedImageUrls.isNotEmpty ||
        widget.initialPost?.allImageDatas.isNotEmpty == true ||
        widget.initialPost?.allImageUrls.isNotEmpty == true;
    if (!hasImage) {
      setState(() => error = '사진은 꼭 필요해요. 직접 올리거나 바코드로 상품 이미지를 불러와 주세요.');
      return;
    }
    if (title.isEmpty) {
      setState(() => error = '품명은 꼭 입력해 주세요.');
      return;
    }
    if (rating <= 0) {
      setState(() => error = '평점을 골라 주세요.');
      return;
    }

    setState(() {
      submitting = true;
      error = null;
    });

    final draft = PostDraft(
      authorId: widget.currentUser.id,
      authorNickname: widget.currentUser.nickname,
      title: title.isEmpty ? '제목 없는 꿀조합' : title,
      content: content,
      priceMin: singlePrice ?? 0,
      priceMax: singlePrice ?? 0,
      categories:
          widget.initialPost?.categories
              .where(communityReviewTags.contains)
              .toList() ??
          const <String>[],
      imageBytes: selectedImageBytes,
      imageUrls: selectedImageUrls,
      details: details,
      calories: calories,
      rating: rating,
    );

    try {
      if (isEditing) {
        await widget.repository.updatePost(widget.initialPost!.id, draft);
      } else {
        await widget.repository.createPost(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = isEditing
            ? '수정하지 못했어요. 잠시 후 다시 시도해 주세요.'
            : '게시하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  List<String> _splitLines(String value) {
    return value
        .split('\n')
        .map(
          (item) => item.replaceFirst(RegExp(r'^[\s\-\*\u2192]+'), '').trim(),
        )
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: widget.pageMode
              ? BorderRadius.zero
              : const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.fromLTRB(18, widget.pageMode ? 10 : 18, 18, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? '게시글 수정' : '게시물 올리기',
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isEditing
                                ? '내 게시글을 다시 다듬어 보세요.'
                                : '조합 사진과 품명, 먹어본 기록을 남겨보세요.',
                            style: const TextStyle(
                              color: Color(0xFF8CA0B3),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FB),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFCEDBE6)),
                  ),
                  child: selectedImageBytes.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: GridView.builder(
                            padding: const EdgeInsets.all(8),
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: selectedImageBytes.length.clamp(1, 4),
                            itemBuilder: (context, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                selectedImageBytes[index],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        )
                      : widget.initialPost != null
                      ? selectedImageUrls.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.network(
                                  _displayImageUrl(selectedImageUrls.first),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const _ImageErrorPlaceholder(),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: _PostImageGallery(
                                  post: widget.initialPost!,
                                ),
                              )
                      : selectedImageUrls.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.network(
                            _displayImageUrl(selectedImageUrls.first),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _ImageErrorPlaceholder(),
                          ),
                        )
                      : const Center(
                          child: Text(
                            '사진이 아직 없어요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9DB0C0),
                              fontWeight: FontWeight.w700,
                              height: 1.6,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => pickImage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7E8994),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('사진 올리기'),
                    ),
                    if (selectedImageBytes.isNotEmpty ||
                        selectedImageUrls.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          selectedImageBytes.clear();
                          selectedImageUrls.clear();
                        }),
                        child: const Text('선택 비우기'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (selectedImageBytes.isNotEmpty ||
                    selectedImageUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '선택된 사진 ${selectedImageBytes.length + selectedImageUrls.length}장',
                      style: const TextStyle(
                        color: Color(0xFF6C8194),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                TextField(
                  controller: titleController,
                  onChanged: (_) => setState(() {}),
                  decoration: inputDecoration('품명: 불닭볶음면 + 스트링치즈').copyWith(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton.icon(
                        onPressed: scanProductCode,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          backgroundColor: const Color(0xFFEAF2FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          '바코드',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 120,
                      minHeight: 44,
                    ),
                  ),
                ),
                if (titleController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LiveTitleSuggestions(
                    suggestions: _matchingTitleSuggestions(
                      postTitleIndex,
                      titleController.text.split('+').last,
                    ),
                    onSelected: (title) {
                      final nextTitle = _applyTitleSuggestion(
                        titleController.text,
                        title,
                      );
                      setState(() => titleController.text = nextTitle);
                      titleController.selection = TextSelection.collapsed(
                        offset: nextTitle.length,
                      );
                    },
                  ),
                ],
                if (titleController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConvenienceProductTitle(
                    title: titleController.text,
                    contextText:
                        '${titleController.text} ${contentController.text}',
                    maxLines: 2,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: inputDecoration('가격 ____원'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: calorieController,
                  keyboardType: TextInputType.number,
                  decoration: inputDecoration('칼로리 약 ____kcal'),
                ),
                const SizedBox(height: 12),
                _PostRatingPicker(
                  value: rating.round(),
                  onChanged: (value) =>
                      setState(() => rating = value.toDouble()),
                ),
                const SizedBox(height: 12),
                _DetailInputCard(
                  title: '후기',
                  hint: '이 조합을 직접 먹어본 느낌을 적어 주세요.',
                  controller: contentController,
                ),
                const SizedBox(height: 12),
                _DetailInputCard(
                  title: '먹는 법',
                  hint: '* 라면을 먼저 익혀요\n* 치즈를 넣고 20초 더 돌려요',
                  controller: eatingStepsController,
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFD44444),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: submitting ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.lime,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      submitting
                          ? (isEditing ? '수정 중...' : '게시 중...')
                          : (isEditing ? '수정 완료' : '게시'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailInputCard extends StatelessWidget {
  const _DetailInputCard({
    required this.title,
    required this.hint,
    required this.controller,
  });

  final String title;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 4,
            decoration: inputDecoration(hint),
          ),
        ],
      ),
    );
  }
}

class _PostRatingPicker extends StatelessWidget {
  const _PostRatingPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EDF4)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '평점',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ...List.generate(5, (index) {
            final score = index + 1;
            return IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(score),
              icon: Icon(
                score <= value
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: const Color(0xFFF4B942),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ChipSelectorCard extends StatefulWidget {
  const _ChipSelectorCard({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;

  @override
  State<_ChipSelectorCard> createState() => _ChipSelectorCardState();
}

class _ChipSelectorCardState extends State<_ChipSelectorCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EDF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...widget.options.map((option) {
                final active = widget.selected.contains(option);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (active) {
                        widget.selected.remove(option);
                      } else {
                        widget.selected.add(option);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFFE8F8D4) : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active
                            ? const Color(0xFFA9D85E)
                            : const Color(0xFFDCE8EE),
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF628C15)
                            : const Color(0xFF5B7182),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class BotTurnResult {
  const BotTurnResult({this.resolvedBudget, this.shouldSyncBudget = false});

  final int? resolvedBudget;
  final bool shouldSyncBudget;
}

class PyeonBotPage extends StatefulWidget {
  const PyeonBotPage({
    super.key,
    required this.currentUser,
    required this.posts,
    required this.onSend,
    required this.onMore,
    required this.onOpenPost,
    required this.onResetSetup,
    required this.onResetConversation,
  });

  final PyeonUser currentUser;
  final List<Post> posts;
  final Future<BotTurnResult> Function(
    String prompt,
    bool useAgeCalorieGuide,
    int? currentBudget,
  )
  onSend;
  final Future<void> Function(bool useAgeCalorieGuide, int? currentBudget)
  onMore;
  final ValueChanged<String> onOpenPost;
  final Future<void> Function() onResetSetup;
  final Future<void> Function() onResetConversation;

  @override
  State<PyeonBotPage> createState() => _PyeonBotPageState();
}

class _PyeonBotPageState extends State<PyeonBotPage> {
  final _controller = TextEditingController();
  final _budgetController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _useAgeCalorieGuide = true;

  @override
  void initState() {
    super.initState();
    for (final message in widget.currentUser.botMessages.reversed) {
      if (message.role != 'assistant') continue;
      if (message.resolvedBudget != null) {
        _budgetController.text = message.resolvedBudget.toString();
      }
      if (message.useAgeCalorieGuide != null) {
        _useAgeCalorieGuide = message.useAgeCalorieGuide!;
      }
      break;
    }
  }

  int? get _currentBudget {
    final value = int.tryParse(
      _budgetController.text.replaceAll(',', '').trim(),
    );
    return value != null && value > 0 && value <= 1000000 ? value : null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _budgetController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _sending = true);
    _controller.clear();
    final result = await widget.onSend(
      value,
      _useAgeCalorieGuide,
      _currentBudget,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.shouldSyncBudget && result.resolvedBudget != null) {
        _budgetController.text = result.resolvedBudget.toString();
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 220,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _resetConversation() async {
    await widget.onResetConversation();
    if (!mounted) return;
    setState(() {
      _budgetController.clear();
      _useAgeCalorieGuide = true;
    });
  }

  Future<void> _handleMenu(String value) async {
    if (value == 'setup') {
      await widget.onResetSetup();
      return;
    }
    if (value == 'conversation') {
      await _resetConversation();
    }
  }

  Future<void> _loadMoreRecommendations() async {
    setState(() => _sending = true);
    await widget.onMore(_useAgeCalorieGuide, _currentBudget);
    if (!mounted) return;
    setState(() => _sending = false);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 260,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.currentUser.botMessages;
    final canRequestMore =
        messages.isNotEmpty &&
        messages.last.role == 'assistant' &&
        messages.last.recommendedPostIds.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '편봇',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '편봇 메뉴',
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.navy,
                ),
                onSelected: _handleMenu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'setup', child: Text('초기설정 다시 하기')),
                  PopupMenuItem(value: 'conversation', child: Text('대화 초기화')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            children: [
              if (messages.isEmpty)
                const _BotIntroCard()
              else
                ...messages.map(
                  (message) => _BotMessageBubble(
                    message: message,
                    posts: widget.posts,
                    onOpenPost: widget.onOpenPost,
                  ),
                ),
              if (canRequestMore)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: _sending ? null : _loadMoreRecommendations,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('다른 추천 3개 더 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEDF3F7))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('bot-message-input'),
                        controller: _controller,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        decoration: inputDecoration('지금 상황을 말해줘').copyWith(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: FilledButton(
                        key: const Key('bot-send-button'),
                        onPressed: _sending ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.lime,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded, size: 21),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _sending
                            ? null
                            : () => setState(
                                () =>
                                    _useAgeCalorieGuide = !_useAgeCalorieGuide,
                              ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _useAgeCalorieGuide
                                ? const Color(0xFFF1F7DF)
                                : const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _useAgeCalorieGuide
                                  ? AppColors.lime
                                  : AppColors.line,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.monitor_heart_outlined,
                                size: 15,
                                color: _useAgeCalorieGuide
                                    ? AppColors.navy
                                    : AppColors.muted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _useAgeCalorieGuide
                                    ? '권장 칼로리 반영'
                                    : '권장 칼로리 제외',
                                style: TextStyle(
                                  color: _useAgeCalorieGuide
                                      ? AppColors.navy
                                      : AppColors.muted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 116,
                        height: 36,
                        child: TextField(
                          key: const Key('bot-budget-input'),
                          controller: _budgetController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          decoration: inputDecoration('예산').copyWith(
                            isDense: true,
                            suffixText: '원',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BotSetupPage extends StatefulWidget {
  const BotSetupPage({super.key, required this.onComplete});

  final Future<void> Function(BotSetup setup) onComplete;

  @override
  State<BotSetupPage> createState() => _BotSetupPageState();
}

class _BotSetupPageState extends State<BotSetupPage> {
  final _ageController = TextEditingController();
  final Map<String, int> _tasteRatings = <String, int>{
    '달달': 3,
    '매콤': 3,
    '새콤': 3,
    '짭짤': 3,
  };
  final List<String> _priorityValues = <String>[];
  String _gender = '여자';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final age = int.tryParse(_ageController.text.trim());
    if (age == null || age < 4 || age > 120) {
      setState(() => _error = '나이를 만 4~120세 사이로 입력해 주세요.');
      return;
    }
    if (_priorityValues.length < 2) {
      setState(() => _error = '추천에서 중요하게 볼 기준을 1·2순위까지 골라 주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete(
        BotSetup(
          age: age,
          gender: _gender,
          tasteRatings: Map<String, int>.from(_tasteRatings),
          priorityValues: List<String>.from(_priorityValues),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '초기 설정 저장에 실패했어요. 서버 상태를 확인하고 다시 시도해 주세요.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE6EEF3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(14),
                  blurRadius: 24,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '편봇 초기 설정',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '처음 한 번만 답하면, 좋아요와 대화 기록을 바탕으로 취향을 더 잘 기억해요.',
                  style: TextStyle(
                    color: Color(0xFF73889B),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '나이는? (만)',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: inputDecoration('예: 20'),
                  onChanged: (_) => setState(() {}),
                ),
                if (MealCalorieRange.forAge(
                      int.tryParse(_ageController.text.trim()) ?? 0,
                    )
                    case final range?) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F8E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lime),
                    ),
                    child: Text(
                      '${range.ageLabel} 한 끼 참고 범위 · ${range.label}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  '성별은?',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '여자', label: Text('여자')),
                    ButtonSegment(value: '남자', label: Text('남자')),
                  ],
                  selected: {_gender},
                  onSelectionChanged: (values) =>
                      setState(() => _gender = values.first),
                  style: ButtonStyle(
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '가장 좋아하는 맛은?',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '각 맛을 얼마나 좋아하는지 1~5로 표시해 주세요.',
                  style: TextStyle(
                    color: Color(0xFF7C90A2),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _TasteRatingEditor(
                  ratings: _tasteRatings,
                  onChanged: (taste, value) =>
                      setState(() => _tasteRatings[taste] = value),
                ),
                const SizedBox(height: 22),
                const Text(
                  '추천에서 중요한 기준은?',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '두 개를 고르면 선택한 순서대로 1·2순위가 됩니다.',
                  style: TextStyle(
                    color: Color(0xFF7C90A2),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _PriorityChoiceWrap(
                  labels: const ['저칼로리', '가성비', '시간절약', '호불호', '트렌드'],
                  selected: _priorityValues,
                  onChanged: () => setState(() {}),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFD44444),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.lime,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(_saving ? '저장 중...' : '편봇 시작하기'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.currentUser,
    required this.posts,
    required this.onUserChanged,
    required this.onResetBotSetup,
    required this.onLogout,
    required this.onOpenPost,
    required this.onOpenAuthor,
    required this.onToggleProfilePublic,
  });

  final PyeonUser currentUser;
  final List<Post> posts;
  final Future<void> Function(PyeonUser user) onUserChanged;
  final Future<void> Function() onResetBotSetup;
  final Future<void> Function() onLogout;
  final Future<void> Function(Post post) onOpenPost;
  final ValueChanged<Post> onOpenAuthor;
  final Future<void> Function(bool value) onToggleProfilePublic;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  _ProfileViewMode _mode = _ProfileViewMode.overview;
  SortMode _postSortMode = SortMode.latest;
  final ImagePicker _picker = ImagePicker();
  CombinationBattleState _sharedBattleState = const CombinationBattleState();

  @override
  void initState() {
    super.initState();
    _sharedBattleState = widget.currentUser.battleState;
    _loadSharedBattleState();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id) {
      _sharedBattleState = widget.currentUser.battleState;
      _loadSharedBattleState();
    }
  }

  Future<void> _loadSharedBattleState() async {
    try {
      final shared = await BattleStateStore.load(
        fallback: widget.currentUser.battleState,
      );
      if (!mounted) return;
      setState(() => _sharedBattleState = shared);
    } catch (_) {
      // Keep using the current user snapshot when local storage is unavailable.
    }
  }

  Future<void> _changeProfileImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await widget.onUserChanged(
      widget.currentUser.copyWith(profileImageUrl: base64Encode(bytes)),
    );
  }

  Future<void> _openRandomPost() async {
    if (widget.posts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('추천할 게시글이 아직 없어요.')));
      return;
    }

    final randomPost = widget.posts[math.Random().nextInt(widget.posts.length)];
    await widget.onOpenPost(randomPost);
  }

  List<Post> _sortPosts(List<Post> posts) {
    final next = [...posts];
    next.sort((a, b) {
      switch (_postSortMode) {
        case SortMode.latest:
          return b.createdAt.compareTo(a.createdAt);
        case SortMode.popular:
          final likeCompare = b.likes.compareTo(a.likes);
          return likeCompare != 0
              ? likeCompare
              : b.createdAt.compareTo(a.createdAt);
        case SortMode.worst:
          final dislikeCompare = b.dislikes.compareTo(a.dislikes);
          return dislikeCompare != 0
              ? dislikeCompare
              : b.createdAt.compareTo(a.createdAt);
      }
    });
    return next;
  }

  Map<String, double>? _likedTasteAverages(List<Post> likedPosts) {
    if (likedPosts.isEmpty) return null;

    Map<String, int> tasteRatingsFor(Post post) {
      if (post.reviews.isNotEmpty) {
        int average(int Function(PostReview review) pick) =>
            (post.reviews.map(pick).reduce((a, b) => a + b) /
                    post.reviews.length)
                .round()
                .clamp(1, 5);
        return <String, int>{
          '달달': average((review) => review.sweet),
          '매콤': average((review) => review.spicy),
          '새콤': average((review) => review.sour),
          '짭짤': average((review) => review.salty),
        };
      }

      final text = '${post.title} ${post.content} ${post.categories.join(' ')}';
      bool hasAny(List<String> needles) => needles.any(text.contains);
      return <String, int>{
        '달달': hasAny(const ['달달', '초코', '바닐라', '젤리', '디저트']) ? 4 : 2,
        '매콤': hasAny(const ['매콤', '매운', '불닭', '고추']) ? 4 : 2,
        '새콤': hasAny(const ['새콤', '상큼', '레몬', '탄산']) ? 4 : 2,
        '짭짤': hasAny(const ['짭짤', '라면', '김밥', '핫바', '치즈']) ? 4 : 2,
      };
    }

    final totals = <String, double>{'달달': 0, '새콤': 0, '짭짤': 0, '매콤': 0};

    for (final post in likedPosts) {
      final ratings = tasteRatingsFor(post);
      totals.update('달달', (value) => value + (ratings['달달'] ?? 0));
      totals.update('새콤', (value) => value + (ratings['새콤'] ?? 0));
      totals.update('짭짤', (value) => value + (ratings['짭짤'] ?? 0));
      totals.update('매콤', (value) => value + (ratings['매콤'] ?? 0));
    }

    return <String, double>{
      for (final entry in totals.entries)
        entry.key: entry.value / likedPosts.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    final setup = currentUser.botSetup;
    final likedPosts = _sortPosts(
      widget.posts
          .where((post) => currentUser.likedPostIds.contains(post.id))
          .toList(),
    );
    final likedTasteAverages = _likedTasteAverages(likedPosts);
    final dislikedPosts = _sortPosts(
      widget.posts
          .where((post) => currentUser.dislikedPostIds.contains(post.id))
          .toList(),
    );
    final savedPosts = _sortPosts(
      widget.posts
          .where((post) => currentUser.savedPostIds.contains(post.id))
          .toList(),
    );
    final battleMatches = [..._sharedBattleState.matches]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final authoredBattleMatches = battleMatches
        .where((match) => match.authorId == currentUser.id)
        .toList();
    final votedBattleMatches = battleMatches
        .where((match) => match.voteSideOf(currentUser.id) != null)
        .toList();
    final myPosts = _sortPosts(
      widget.posts.where((post) => post.authorId == currentUser.id).toList(),
    );
    final pickedAuthorPosts = widget.posts
        .where((post) => currentUser.pickedAuthorIds.contains(post.authorId))
        .fold<Map<String, Post>>(<String, Post>{}, (map, post) {
          map.putIfAbsent(post.authorId, () => post);
          return map;
        })
        .values
        .toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 24,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: _changeProfileImage,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _UserAvatar(
                      imageSource: currentUser.profileImageUrl,
                      radius: 42,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                currentUser.nickname,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '@${currentUser.username}',
                style: const TextStyle(
                  color: Color(0xFF8092A3),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '픽한 작성자 ${currentUser.pickedAuthorIds.length} · 나를 픽한 사람 ${currentUser.pickedByCount}',
                style: const TextStyle(
                  color: Color(0xFF6F8498),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: _openRandomPost,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEAF6FF),
                  foregroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.casino_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '무작위 추천',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ProfileModeChip(
                label: '개요',
                active: _mode == _ProfileViewMode.overview,
                onTap: () => setState(() => _mode = _ProfileViewMode.overview),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '♥ 하트 ${likedPosts.length}',
                active: _mode == _ProfileViewMode.likes,
                onTap: () => setState(() => _mode = _ProfileViewMode.likes),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '보관함 ${savedPosts.length}',
                active: _mode == _ProfileViewMode.saved,
                onTap: () => setState(() => _mode = _ProfileViewMode.saved),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '👎 싫어요 ${dislikedPosts.length}',
                active: _mode == _ProfileViewMode.dislikes,
                onTap: () => setState(() => _mode = _ProfileViewMode.dislikes),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '내 게시물 ${myPosts.length}',
                active: _mode == _ProfileViewMode.myPosts,
                onTap: () => setState(() => _mode = _ProfileViewMode.myPosts),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '픽 ${currentUser.pickedAuthorIds.length}',
                active: _mode == _ProfileViewMode.picks,
                onTap: () => setState(() => _mode = _ProfileViewMode.picks),
              ),
              const SizedBox(width: 8),
              _ProfileModeChip(
                label: '픽 쇼츠 ${votedBattleMatches.length}',
                active: _mode == _ProfileViewMode.votes,
                onTap: () => setState(() => _mode = _ProfileViewMode.votes),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_mode == _ProfileViewMode.overview && setup != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFE),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2EDF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '편봇 설정',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '나이: 만 ${setup.age}세',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '성별: ${setup.gender}',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (setup.mealCalorieRange case final range?)
                  Text(
                    '한 끼 참고 칼로리: ${range.label}',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  '맛 취향: ${setup.tasteRatings.entries.map((entry) => '${entry.key} ${entry.value}').join(' · ')}',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '추천 우선순위: ${setup.priorityValues.asMap().entries.map((entry) => '${entry.key + 1}위 ${entry.value}').join(' · ')}',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (_mode == _ProfileViewMode.overview &&
            likedTasteAverages != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내가 하트 누른 게시글 기준 취향 평균',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '좋아요 누른 게시글들의 평균 맛 성향이에요.',
                  style: TextStyle(
                    color: Color(0xFF73889B),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                _ReadOnlyTasteAverages(averages: likedTasteAverages),
              ],
            ),
          ),
        ],
        if (_mode == _ProfileViewMode.overview) ...[
          if (setup != null) const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFE),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2EDF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '프로필 공개 설정',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                _VisibilitySwitchRow(
                  label: '프로필 전체 공개',
                  value: currentUser.profilePublic,
                  onChanged: (value) => widget.onToggleProfilePublic(value),
                ),
                _VisibilitySwitchRow(
                  label: '아이디 공개',
                  value: currentUser.profileVisibility.username,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        username: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '좋아요 공개',
                  value: currentUser.profileVisibility.likes,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        likes: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '싫어요 공개',
                  value: currentUser.profileVisibility.dislikes,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        dislikes: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '보관함 공개',
                  value: currentUser.profileVisibility.saved,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        saved: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '내 게시물 공개',
                  value: currentUser.profileVisibility.myPosts,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        myPosts: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '픽한 작성자 공개',
                  value: currentUser.profileVisibility.picks,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        picks: value,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '나를 픽한 사람 수 공개',
                  value: currentUser.profileVisibility.pickedBy,
                  onChanged: (value) => widget.onUserChanged(
                    currentUser.copyWith(
                      profileVisibility: currentUser.profileVisibility.copyWith(
                        pickedBy: value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_mode != _ProfileViewMode.overview &&
            _mode != _ProfileViewMode.picks &&
            _mode != _ProfileViewMode.saved &&
            _mode != _ProfileViewMode.votes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SortSelector(
                  sortMode: _postSortMode,
                  onChanged: (mode) => setState(() => _postSortMode = mode),
                ),
              ],
            ),
          ),
        if (_mode == _ProfileViewMode.likes)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내가 하트 누른 글',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (likedPosts.isEmpty)
                  const Text(
                    '아직 하트를 누른 글이 없어요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...likedPosts.map(
                    (post) => _CompactPostTile(
                      post: post,
                      onTap: () => widget.onOpenPost(post),
                    ),
                  ),
              ],
            ),
          )
        else if (_mode == _ProfileViewMode.saved)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '커뮤니티 보관함',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (savedPosts.isEmpty)
                  const Text(
                    '커뮤니티 게시글에서 바로 보관함에 넣어보세요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...savedPosts.map(
                    (post) => _CompactPostTile(
                      post: post,
                      onTap: () => widget.onOpenPost(post),
                    ),
                  ),
              ],
            ),
          )
        else if (_mode == _ProfileViewMode.dislikes)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내가 싫어요 누른 글',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (dislikedPosts.isEmpty)
                  const Text(
                    '아직 싫어요를 누른 글이 없어요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...dislikedPosts.map(
                    (post) => _CompactPostTile(
                      post: post,
                      onTap: () => widget.onOpenPost(post),
                    ),
                  ),
              ],
            ),
          )
        else if (_mode == _ProfileViewMode.myPosts)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내가 올린 게시글',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (myPosts.isEmpty)
                  const Text(
                    '아직 내가 올린 게시글이 없어요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...myPosts.map(
                    (post) => _CompactPostTile(
                      post: post,
                      onTap: () => widget.onOpenPost(post),
                    ),
                  ),
              ],
            ),
          )
        else if (_mode == _ProfileViewMode.picks)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내가 픽한 작성자',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (pickedAuthorPosts.isEmpty)
                  const Text(
                    '작성자 이름이나 프로필을 눌러 픽해 보세요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...pickedAuthorPosts.map(
                    (post) => ListTile(
                      onTap: () => widget.onOpenAuthor(post),
                      tileColor: const Color(0xFFF5FAFD),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8EEF3),
                        child: Icon(
                          Icons.person_rounded,
                          color: Color(0xFF8598A8),
                        ),
                      ),
                      title: Text(
                        post.authorNickname,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${post.title} 외 스타일 보기'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: const Text(
              '프로필 공개 설정과 편봇 초기설정을 여기서 관리할 수 있어요.',
              style: TextStyle(
                color: Color(0xFF7D90A0),
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ),
        if (_mode == _ProfileViewMode.votes)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EFF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내 픽 쇼츠',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '내가 올린 것',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (authoredBattleMatches.isEmpty)
                  const Text(
                    '아직 올린 픽 쇼츠가 없어요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...authoredBattleMatches.map(
                    (match) => _CompactBattleVoteTile(
                      match: match,
                      currentUserId: currentUser.id,
                      leftPost: widget.posts
                          .where((post) => post.id == match.leftPostId)
                          .firstOrNull,
                      rightPost: widget.posts
                          .where((post) => post.id == match.rightPostId)
                          .firstOrNull,
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: Color(0xFFE8EFF4)),
                ),
                const Text(
                  '내가 투표한 것',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (votedBattleMatches.isEmpty)
                  const Text(
                    '아직 투표한 픽 쇼츠가 없어요.',
                    style: TextStyle(
                      color: Color(0xFF7D90A0),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  ...votedBattleMatches.map(
                    (match) => _CompactBattleVoteTile(
                      match: match,
                      currentUserId: currentUser.id,
                      leftPost: widget.posts
                          .where((post) => post.id == match.leftPostId)
                          .firstOrNull,
                      rightPost: widget.posts
                          .where((post) => post.id == match.rightPostId)
                          .firstOrNull,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.onResetBotSetup,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.lime,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: const Text('편봇 초기설정 다시 하기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: widget.onLogout,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            side: const BorderSide(color: AppColors.navy),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: const Text('로그아웃'),
        ),
      ],
    );
  }
}

enum _ProfileViewMode {
  overview,
  likes,
  saved,
  dislikes,
  myPosts,
  picks,
  votes,
}

class _ProfileModeChip extends StatelessWidget {
  const _ProfileModeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : const Color(0xFFF4F8FB),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF627A90),
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _VisibilitySwitchRow extends StatelessWidget {
  const _VisibilitySwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value
                    ? const Color(0xFFFFF0F1)
                    : const Color(0xFFF2F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value
                      ? const Color(0xFFE65064)
                      : const Color(0xFFD6DCE2),
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                size: 22,
                color: value
                    ? const Color(0xFFE65064)
                    : const Color(0xFFB8C0C8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactPostTile extends StatelessWidget {
  const _CompactPostTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5FAFD),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${post.priceLabel} · 하트 ${post.likes} · 싫어요 ${post.dislikes}',
                style: const TextStyle(
                  color: Color(0xFF758A9C),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactBattleVoteTile extends StatelessWidget {
  const _CompactBattleVoteTile({
    required this.match,
    required this.currentUserId,
    required this.leftPost,
    required this.rightPost,
  });

  final BattleMatchEntry match;
  final String currentUserId;
  final Post? leftPost;
  final Post? rightPost;

  @override
  Widget build(BuildContext context) {
    final leftTitle = leftPost?.title ?? match.leftCustomTitle ?? '왼쪽 조합';
    final rightTitle = rightPost?.title ?? match.rightCustomTitle ?? '오른쪽 조합';
    final votedSide = match.voteSideOf(currentUserId);
    final pickedTitle = switch (votedSide) {
      BattleVoteSide.left => leftTitle,
      BattleVoteSide.right => rightTitle,
      null => '아직 선택 안 함',
    };
    final resultText = switch (match.winnerSide) {
      BattleVoteSide.left => '$leftTitle 승',
      BattleVoteSide.right => '$rightTitle 승',
      null => match.totalVotes == 0 ? '투표 없음' : '무승부',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match.title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            match.isExpired ? '결과: $resultText' : '내 선택: $pickedTitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF516B83),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${match.isExpired ? '종료됨' : '진행 중'} · 총 ${match.totalVotes}표 · ${match.createdAtLabel}',
            style: const TextStyle(
              color: Color(0xFF7A8793),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorProfileSection extends StatelessWidget {
  const _AuthorProfileSection({
    required this.title,
    required this.subtitle,
    required this.posts,
    required this.onOpenPost,
  });

  final String title;
  final String subtitle;
  final List<Post> posts;
  final Future<void> Function(Post post) onOpenPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF7D90A0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (posts.isEmpty)
            const Text(
              '공개된 항목이 아직 없어요.',
              style: TextStyle(
                color: Color(0xFF7D90A0),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: posts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
                childAspectRatio: 0.58,
              ),
              itemBuilder: (context, index) => _ProfilePostMiniCard(
                post: posts[index],
                onTap: () => onOpenPost(posts[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfilePostMiniCard extends StatelessWidget {
  const _ProfilePostMiniCard({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5FAFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4EEF5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _PostImageGallery(post: post),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ConvenienceProductTitle(
                title: post.title,
                contextText: '${post.title} ${post.content}',
                maxLines: 2,
                showLabels: false,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '♥ ${post.likes} · 👎 ${post.dislikes}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF758A9C),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedAuthorsSection extends StatelessWidget {
  const _PickedAuthorsSection({
    required this.title,
    required this.subtitle,
    required this.posts,
    required this.onOpenAuthorByIdentity,
  });

  final String title;
  final String subtitle;
  final List<Post> posts;
  final Future<void> Function(String authorId, String authorNickname)
  onOpenAuthorByIdentity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF7D90A0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: posts.map((post) {
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    onOpenAuthorByIdentity(post.authorId, post.authorNickname),
                child: Container(
                  width: 132,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBFD),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE0ECF2)),
                  ),
                  child: Column(
                    children: [
                      _UserAvatar(
                        imageSource: post.authorProfileImageUrl,
                        radius: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.authorNickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF758A9D),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatPill extends StatelessWidget {
  const _ProfileStatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: Color(0xFF6A8093),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AudiencePieChartCard extends StatelessWidget {
  const _AudiencePieChartCard({
    required this.title,
    required this.values,
    required this.colors,
    required this.ratioBuilder,
  });

  final String title;
  final Map<String, int> values;
  final Map<String, Color> colors;
  final String Function(int count) ratioBuilder;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((entry) => entry.value > 0).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 118,
              height: 118,
              child: _AudiencePieChart(entries: entries, colors: colors),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              '아직 집계할 데이터가 없어요.',
              style: TextStyle(
                color: Color(0xFF7D90A0),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[entry.key] ?? const Color(0xFF9AA8B6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${ratioBuilder(entry.value)} · ${entry.value}명',
                      style: const TextStyle(
                        color: Color(0xFF6F8598),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudiencePieChart extends StatelessWidget {
  const _AudiencePieChart({required this.entries, required this.colors});

  final List<MapEntry<String, int>> entries;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE1E8EE), width: 14),
        ),
      );
    }
    return CustomPaint(
      painter: _PieChartPainter(entries: entries, colors: colors),
      child: Center(
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  const _PieChartPainter({required this.entries, required this.colors});

  final List<MapEntry<String, int>> entries;
  final Map<String, Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final strokeWidth = size.width * 0.24;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    var startAngle = -math.pi / 2;
    for (final entry in entries) {
      final sweepAngle = total == 0 ? 0.0 : (entry.value / total) * math.pi * 2;
      paint.color = colors[entry.key] ?? const Color(0xFF9AA8B6);
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.entries != entries || oldDelegate.colors != colors;
  }
}

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.post,
    required this.currentUser,
    required this.allPosts,
    required this.allUsers,
    required this.onLoadAudienceStats,
    required this.isMine,
    required this.isSaved,
    required this.isPickedAuthor,
    required this.onToggleLike,
    required this.onToggleDislike,
    required this.onAddComment,
    required this.onToggleSave,
    required this.onTogglePickAuthor,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenAuthor,
    required this.onOpenCommentAuthor,
    required this.onAddReview,
    required this.onUpdateReview,
    required this.onDeleteReview,
  });

  final Post post;
  final PyeonUser currentUser;
  final List<Post> allPosts;
  final List<PyeonUser> allUsers;
  final Future<PostAudienceStats> Function() onLoadAudienceStats;
  final bool isMine;
  final bool isSaved;
  final bool isPickedAuthor;
  final Future<Post> Function() onToggleLike;
  final Future<Post> Function() onToggleDislike;
  final Future<Post> Function(String text) onAddComment;
  final Future<void> Function() onToggleSave;
  final Future<void> Function() onTogglePickAuthor;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final VoidCallback onOpenAuthor;
  final void Function(String authorId, String authorNickname)
  onOpenCommentAuthor;
  final Future<Post> Function(PostReview review) onAddReview;
  final Future<Post> Function(PostReview review) onUpdateReview;
  final Future<Post> Function(PostReview review) onDeleteReview;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late Post _post;
  late bool _saved;
  late bool _pickedAuthor;
  PostAudienceStats? _audienceStats;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _saved = widget.isSaved;
    _pickedAuthor = widget.isPickedAuthor;
    unawaited(_loadAudienceStats());
  }

  Future<void> _loadAudienceStats() async {
    try {
      final stats = await widget.onLoadAudienceStats();
      if (!mounted) return;
      setState(() => _audienceStats = stats);
    } catch (_) {
      // Local account data remains available as a fallback.
    }
  }

  Future<void> _openPhotoViewer() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(170),
      builder: (context) => _PhotoViewerDialog(post: _post),
    );
  }

  Future<void> _openReviews() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PostReviewsScreen(
          post: _post,
          currentUser: widget.currentUser,
          onAddReview: (review) async {
            final updated = await widget.onAddReview(review);
            if (mounted) setState(() => _post = updated);
            return updated;
          },
          onUpdateReview: (review) async {
            final updated = await widget.onUpdateReview(review);
            if (mounted) setState(() => _post = updated);
            return updated;
          },
          onDeleteReview: (review) async {
            final updated = await widget.onDeleteReview(review);
            if (mounted) setState(() => _post = updated);
            return updated;
          },
        ),
      ),
    );
  }

  List<PyeonUser> get _likedUsers {
    return widget.allUsers
        .where((user) => user.likedPostIds.contains(_post.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayContent = _contentWithoutBarcodeLines(_post.content);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          '게시글 상세보기',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (widget.isMine)
            PopupMenuButton<String>(
              onSelected: (value) async {
                final navigator = Navigator.of(context);
                if (value == 'edit') {
                  await widget.onEdit();
                } else if (value == 'delete') {
                  await widget.onDelete();
                  if (!mounted) return;
                  navigator.pop();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('수정')),
                PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: widget.onOpenAuthor,
                      borderRadius: BorderRadius.circular(999),
                      child: Row(
                        children: [
                          _UserAvatar(
                            imageSource: _post.authorProfileImageUrl,
                            radius: 18,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _post.authorNickname,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                _post.createdAtLabel,
                                style: const TextStyle(
                                  color: Color(0xFF8CA0B3),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: () async {
                        await widget.onToggleSave();
                        if (!mounted) return;
                        setState(() => _saved = !_saved);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _saved
                            ? const Color(0xFFE8F4D0)
                            : const Color(0xFFF4F8FB),
                        foregroundColor: _saved
                            ? const Color(0xFF6B8C15)
                            : AppColors.navy,
                      ),
                      child: Text(_saved ? '보관 중' : '보관함 이동'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _openPhotoViewer,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 360,
                      width: double.infinity,
                      child: _PostImageGallery(post: _post),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ConvenienceProductTitle(
                  title: _post.title,
                  contextText: '${_post.title} ${_post.content}',
                  maxLines: 3,
                  labelTopPadding: 5,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TagPill(label: _post.priceLabel),
                    if (_post.calories != null)
                      _TagPill(label: '${_post.calories}kcal'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _post.rating <= 0
                      ? '평점 미입력'
                      : '평점  ★ ${_post.rating.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: AppColors.priceRed,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _displayCategories(
                    _post.categories,
                  ).map((category) => _TagPill(label: '#$category')).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  '후기',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  displayContent.isEmpty ? '아직 후기가 비어 있어요.' : displayContent,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 16),
                _PostDetailsSection(details: _post.details),
                if (_post.details.eatingSteps.isNotEmpty ||
                    _post.details.tips.isNotEmpty)
                  const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ActionChipButton(
                        label:
                            '${_post.likedByMe ? '♥' : '♡'} 하트 ${_post.likes}',
                        active: _post.likedByMe,
                        expanded: true,
                        onTap: () async {
                          final updated = await widget.onToggleLike();
                          if (!mounted) return;
                          setState(() => _post = updated);
                          unawaited(_loadAudienceStats());
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ActionChipButton(
                        label: '👎 싫어요 ${_post.dislikes}',
                        active: _post.dislikedByMe,
                        activeColor: const Color(0xFFE8EDF3),
                        activeTextColor: const Color(0xFF38485A),
                        expanded: true,
                        onTap: () async {
                          final updated = await widget.onToggleDislike();
                          if (!mounted) return;
                          setState(() => _post = updated);
                        },
                      ),
                    ),
                    if (!widget.isMine) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ActionChipButton(
                          label: _pickedAuthor ? '픽 취소' : '작성자 픽',
                          active: _pickedAuthor,
                          activeColor: const Color(0xFFEAF6FF),
                          activeTextColor: AppColors.navy,
                          expanded: true,
                          onTap: () async {
                            await widget.onTogglePickAuthor();
                            if (!mounted) return;
                            setState(() => _pickedAuthor = !_pickedAuthor);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                ActionChipButton(
                  label: '후기 ${_post.reviews.length}',
                  expanded: true,
                  onTap: _openReviews,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PostLikeAudienceCard(
            likedUsers: _likedUsers,
            audienceStats: _audienceStats,
            reviews: _post.reviews,
          ),
        ],
      ),
    );
  }
}

class _PostDetailsSection extends StatelessWidget {
  const _PostDetailsSection({required this.details});

  final PostDetails details;

  @override
  Widget build(BuildContext context) {
    final eatingTips = <String>[...details.eatingSteps, ...details.tips];
    final hasAny = eatingTips.isNotEmpty;
    if (!hasAny) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_DetailBlock(title: '먹는 법', items: eatingTips)],
      ),
    );
  }
}

class _PostLikeAudienceCard extends StatelessWidget {
  const _PostLikeAudienceCard({
    required this.likedUsers,
    required this.audienceStats,
    required this.reviews,
  });

  final List<PyeonUser> likedUsers;
  final PostAudienceStats? audienceStats;
  final List<PostReview> reviews;

  @override
  Widget build(BuildContext context) {
    final localTotal = likedUsers.where((user) {
      final gender = user.botSetup?.gender;
      return gender == '여자' || gender == '남자';
    }).length;
    final genderCounts = <String, int>{'여자': 0, '남자': 0};

    for (final user in likedUsers) {
      final setup = user.botSetup;
      if (setup == null) continue;
      if (genderCounts.containsKey(setup.gender)) {
        genderCounts[setup.gender] = genderCounts[setup.gender]! + 1;
      }
    }
    if (audienceStats != null) {
      genderCounts['남자'] = audienceStats!.maleCount;
      genderCounts['여자'] = audienceStats!.femaleCount;
    }
    final total = audienceStats?.totalWithGender ?? localTotal;

    String ratio(int count) {
      if (total == 0) return '0%';
      return '${((count / total) * 100).round()}%';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '게시글 통계',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '하트 성비 $total명 · 후기 ${reviews.length}개 기준',
            style: const TextStyle(
              color: Color(0xFF7D90A0),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final genderCard = _AudiencePieChartCard(
                title: '남녀 비율',
                values: <String, int>{
                  '여자': genderCounts['여자'] ?? 0,
                  '남자': genderCounts['남자'] ?? 0,
                },
                colors: const <String, Color>{
                  '여자': Color(0xFFFF8EB2),
                  '남자': Color(0xFF69A6FF),
                },
                ratioBuilder: ratio,
              );
              final tasteCard = _ReviewTasteStatsCard(reviews: reviews);
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [genderCard, const SizedBox(height: 12), tasteCard],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: genderCard),
                  const SizedBox(width: 12),
                  Expanded(child: tasteCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewTasteStatsCard extends StatelessWidget {
  const _ReviewTasteStatsCard({required this.reviews});

  final List<PostReview> reviews;

  double _average(num Function(PostReview review) valueOf) {
    if (reviews.isEmpty) return 0;
    return reviews.fold<double>(0, (sum, review) => sum + valueOf(review)) /
        reviews.length;
  }

  @override
  Widget build(BuildContext context) {
    final rating = _average((review) => review.rating);
    final scores = <String, double>{
      '달달': _average((review) => review.sweet),
      '짭짤': _average((review) => review.salty),
      '매콤': _average((review) => review.spicy),
      '새콤': _average((review) => review.sour),
    };
    const colors = <String, Color>{
      '달달': Color(0xFFFF7BA8),
      '짭짤': Color(0xFF6A8FD8),
      '매콤': Color(0xFFE45745),
      '새콤': Color(0xFF9DCB32),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '후기 맛 평균',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3D8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reviews.isEmpty ? '평점 없음' : '★ ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Color(0xFF9A6400),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (reviews.isEmpty)
            const Text(
              '후기가 등록되면 맛 점수와 평점 평균이 표시돼요.',
              style: TextStyle(
                color: Color(0xFF7D90A0),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...scores.entries.map((entry) {
              final color = colors[entry.key] ?? AppColors.limeDeep;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: (entry.value / 5).clamp(0, 1),
                          color: color,
                          backgroundColor: color.withAlpha(35),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${entry.value.toStringAsFixed(1)}점',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFF61798C),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.initialPost,
    required this.onSubmit,
    required this.onOpenAuthor,
  });

  final Post initialPost;
  final Future<Post> Function(String text) onSubmit;
  final void Function(String authorId, String authorNickname) onOpenAuthor;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late Post _post;
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final updated = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() {
      _post = updated;
      _controller.clear();
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7E4EA),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '댓글 ${_post.comments.length}',
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  children: [
                    if (_post.comments.isEmpty)
                      const Text(
                        '첫 댓글을 남겨보세요.',
                        style: TextStyle(
                          color: Color(0xFF7D90A0),
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      ..._post.comments.map(
                        (comment) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFD),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: comment.authorId.isEmpty
                                      ? null
                                      : () => widget.onOpenAuthor(
                                          comment.authorId,
                                          comment.authorNickname,
                                        ),
                                  child: Row(
                                    children: [
                                      _UserAvatar(
                                        imageSource:
                                            comment.authorProfileImageUrl,
                                        radius: 14,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        comment.authorNickname,
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  comment.text,
                                  style: const TextStyle(
                                    color: Color(0xFF5D7286),
                                    fontWeight: FontWeight.w600,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFEDF3F7))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: inputDecoration('댓글을 입력해 주세요.'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_submitting ? '...' : '등록'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.fiber_manual_record_rounded,
                    size: 10,
                    color: AppColors.limeDeep,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFF5C748D),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 9 : 11,
        ),
      ),
    );
  }
}

class _PhotoViewerDialog extends StatefulWidget {
  const _PhotoViewerDialog({required this.post});

  final Post post;

  @override
  State<_PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<_PhotoViewerDialog> {
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _buildPostImages(widget.post);
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: math.min(
                    MediaQuery.of(context).size.width * 0.92,
                    980,
                  ),
                  height: math.min(
                    MediaQuery.of(context).size.height * 0.82,
                    760,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        controller: _controller,
                        itemCount: images.length,
                        onPageChanged: (value) =>
                            setState(() => _pageIndex = value),
                        itemBuilder: (_, index) => Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: images[index],
                        ),
                      ),
                      Positioned(
                        top: 14,
                        right: 14,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(130),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          left: 14,
                          top: 0,
                          bottom: 0,
                          child: _GalleryArrow(
                            icon: Icons.chevron_left_rounded,
                            onTap: _pageIndex == 0
                                ? null
                                : () => _controller.previousPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          ),
                        ),
                      if (images.length > 1)
                        Positioned(
                          right: 14,
                          top: 0,
                          bottom: 0,
                          child: _GalleryArrow(
                            icon: Icons.chevron_right_rounded,
                            onTap: _pageIndex >= images.length - 1
                                ? null
                                : () => _controller.nextPage(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePhotoViewerDialog extends StatelessWidget {
  const _ProfilePhotoViewerDialog({
    required this.imageSource,
    required this.nickname,
  });

  final String? imageSource;
  final String nickname;

  @override
  Widget build(BuildContext context) {
    final provider = _avatarImageProvider(imageSource);
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: math.min(
                    MediaQuery.of(context).size.width * 0.86,
                    520,
                  ),
                  height: math.min(
                    MediaQuery.of(context).size.width * 0.86,
                    520,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    image: provider == null
                        ? null
                        : DecorationImage(image: provider, fit: BoxFit.cover),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 36,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: provider == null
                      ? const Icon(
                          Icons.person_rounded,
                          color: Colors.white70,
                          size: 96,
                        )
                      : null,
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 34,
              child: Text(
                nickname,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withAlpha(120),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthorProfilePage extends StatefulWidget {
  const AuthorProfilePage({
    super.key,
    required this.currentUser,
    required this.authorUser,
    required this.authorPost,
    required this.allPosts,
    required this.authoredPosts,
    required this.isPicked,
    required this.onTogglePick,
    required this.onOpenPost,
    required this.onOpenAuthorByIdentity,
  });

  final PyeonUser currentUser;
  final PyeonUser? authorUser;
  final Post authorPost;
  final List<Post> allPosts;
  final List<Post> authoredPosts;
  final bool isPicked;
  final Future<void> Function()? onTogglePick;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(String authorId, String authorNickname)
  onOpenAuthorByIdentity;

  @override
  State<AuthorProfilePage> createState() => _AuthorProfilePageState();
}

class _AuthorProfilePageState extends State<AuthorProfilePage> {
  SortMode _sortMode = SortMode.latest;

  Future<void> _openProfilePhotoViewer(
    String? imageSource,
    String nickname,
  ) async {
    if ((imageSource ?? '').trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(190),
      builder: (context) => _ProfilePhotoViewerDialog(
        imageSource: imageSource,
        nickname: nickname,
      ),
    );
  }

  List<Post> _sortPosts(List<Post> posts) {
    final next = [...posts];
    next.sort((a, b) {
      switch (_sortMode) {
        case SortMode.latest:
          return b.createdAt.compareTo(a.createdAt);
        case SortMode.popular:
          final likeCompare = b.likes.compareTo(a.likes);
          return likeCompare != 0
              ? likeCompare
              : b.createdAt.compareTo(a.createdAt);
        case SortMode.worst:
          final dislikeCompare = b.dislikes.compareTo(a.dislikes);
          return dislikeCompare != 0
              ? dislikeCompare
              : b.createdAt.compareTo(a.createdAt);
      }
    });
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.authorPost.authorId == widget.currentUser.id;
    final resolvedAuthor = isMine ? widget.currentUser : widget.authorUser;
    final isPublic =
        resolvedAuthor?.profilePublic ?? widget.authoredPosts.isNotEmpty;
    final visibility =
        resolvedAuthor?.profileVisibility ?? const ProfileVisibility();
    final authoredPosts = _sortPosts(widget.authoredPosts);
    final profileImageSource =
        resolvedAuthor?.profileImageUrl ??
        widget.authorPost.authorProfileImageUrl;
    final nickname =
        resolvedAuthor?.nickname ?? widget.authorPost.authorNickname;
    final likedPosts = _sortPosts(
      widget.allPosts
          .where(
            (post) => (resolvedAuthor?.likedPostIds ?? const <String>[])
                .contains(post.id),
          )
          .toList(),
    );
    final dislikedPosts = _sortPosts(
      widget.allPosts
          .where(
            (post) => (resolvedAuthor?.dislikedPostIds ?? const <String>[])
                .contains(post.id),
          )
          .toList(),
    );
    final savedPosts = _sortPosts(
      widget.allPosts
          .where(
            (post) => (resolvedAuthor?.savedPostIds ?? const <String>[])
                .contains(post.id),
          )
          .toList(),
    );
    final pickedAuthorPosts =
        widget.allPosts
            .where(
              (post) => (resolvedAuthor?.pickedAuthorIds ?? const <String>[])
                  .contains(post.authorId),
            )
            .fold<Map<String, Post>>(<String, Post>{}, (map, post) {
              map.putIfAbsent(post.authorId, () => post);
              return map;
            })
            .values
            .toList()
          ..sort((a, b) => a.authorNickname.compareTo(b.authorNickname));
    final sections = <Widget>[
      if (visibility.myPosts || isMine)
        _AuthorProfileSection(
          title: '작성자 게시물',
          subtitle: '공개한 게시물만 볼 수 있어요.',
          posts: authoredPosts,
          onOpenPost: widget.onOpenPost,
        ),
      if ((visibility.likes || isMine) && likedPosts.isNotEmpty)
        _AuthorProfileSection(
          title: '좋아한 게시물',
          subtitle: '이 작성자가 하트를 남긴 조합이에요.',
          posts: likedPosts,
          onOpenPost: widget.onOpenPost,
        ),
      if ((visibility.saved || isMine) && savedPosts.isNotEmpty)
        _AuthorProfileSection(
          title: '보관함',
          subtitle: '나중에 먹어보려고 담아둔 조합이에요.',
          posts: savedPosts,
          onOpenPost: widget.onOpenPost,
        ),
      if ((visibility.picks || isMine) && pickedAuthorPosts.isNotEmpty)
        _PickedAuthorsSection(
          title: '픽한 작성자',
          subtitle: '이 사용자가 저장해둔 조합 취향의 작성자들이에요.',
          posts: pickedAuthorPosts,
          onOpenAuthorByIdentity: widget.onOpenAuthorByIdentity,
        ),
      if ((visibility.dislikes || isMine) && dislikedPosts.isNotEmpty)
        _AuthorProfileSection(
          title: '별로였던 조합',
          subtitle: '호불호가 있었던 조합들을 모아봤어요.',
          posts: dislikedPosts,
          onOpenPost: widget.onOpenPost,
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          '작성자 프로필',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 24,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () =>
                      _openProfilePhotoViewer(profileImageSource, nickname),
                  child: _UserAvatar(
                    imageSource: profileImageSource,
                    radius: 42,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  nickname,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                if ((visibility.username || isMine) &&
                    (resolvedAuthor?.username ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '@${resolvedAuthor!.username}',
                    style: const TextStyle(
                      color: Color(0xFF8092A3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  isPublic
                      ? '공개 설정한 취향과 게시물을 볼 수 있어요.'
                      : '이 사용자는 프로필 일부만 비공개로 두고 있어요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF7D90A0),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (visibility.pickedBy || isMine)
                      _ProfileStatPill(
                        label: '나를 픽한 사람',
                        value: '${resolvedAuthor?.pickedByCount ?? 0}',
                      ),
                    _ProfileStatPill(
                      label: '게시물',
                      value: '${authoredPosts.length}',
                    ),
                    if (visibility.likes || isMine)
                      _ProfileStatPill(
                        label: '하트',
                        value: '${likedPosts.length}',
                      ),
                    if (visibility.saved || isMine)
                      _ProfileStatPill(
                        label: '보관함',
                        value: '${savedPosts.length}',
                      ),
                    if (visibility.dislikes || isMine)
                      _ProfileStatPill(
                        label: '싫어요',
                        value: '${dislikedPosts.length}',
                      ),
                  ],
                ),
                if (!isMine && widget.onTogglePick != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.tonal(
                    onPressed: widget.onTogglePick,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.isPicked
                          ? const Color(0xFFEAF6FF)
                          : const Color(0xFFF4F8FB),
                      foregroundColor: AppColors.navy,
                    ),
                    child: Text(widget.isPicked ? '픽 취소' : '이 작성자 픽하기'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SortSelector(
                sortMode: _sortMode,
                onChanged: (mode) => setState(() => _sortMode = mode),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sections.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE8EFF4)),
              ),
              child: Text(
                isPublic
                    ? '이 사용자가 공개한 정보가 아직 없어요.'
                    : '이 사용자는 현재 작성자 게시물만 공개해 두었어요.',
                style: const TextStyle(
                  color: Color(0xFF7D90A0),
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            )
          else
            ...sections.expand(
              (widget) => <Widget>[widget, const SizedBox(height: 14)],
            ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.imageSource, required this.radius});

  final String? imageSource;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final provider = _avatarImageProvider(imageSource);

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE6ECF1),
      backgroundImage: provider,
      child: provider == null
          ? Icon(
              Icons.person_rounded,
              color: const Color(0xFF91A1AF),
              size: radius,
            )
          : null,
    );
  }
}

ImageProvider<Object>? _avatarImageProvider(String? imageSource) {
  final source = imageSource;
  if (source == null || source.isEmpty) return null;
  try {
    if (source.startsWith('http')) {
      return NetworkImage(_displayImageUrl(source));
    }
    final normalized = source.contains(',') ? source.split(',').last : source;
    return MemoryImage(base64Decode(normalized));
  } catch (_) {
    return null;
  }
}

class ProductScannerPage extends StatelessWidget {
  const ProductScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF8FDFF),
      body: SafeArea(child: ProductScannerSheet(pageMode: true)),
    );
  }
}

class ProductScannerSheet extends StatefulWidget {
  const ProductScannerSheet({super.key, this.pageMode = false});

  final bool pageMode;

  @override
  State<ProductScannerSheet> createState() => _ProductScannerSheetState();
}

class _ProductScannerSheetState extends State<ProductScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
  );
  final TextEditingController _manualCodeController = TextEditingController();

  bool _handled = false;
  bool _showGuide = true;
  bool _starting = true;
  bool _readyForWebTap = false;
  String? _scannerError;
  Timer? _guideTimer;

  @override
  void initState() {
    super.initState();
    _guideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showGuide = false);
    });

    if (kIsWeb) {
      _starting = false;
      _readyForWebTap = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startScanner());
      });
    }
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    _manualCodeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openManualBarcodeInput() async {
    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('바코드 직접 입력'),
        content: TextField(
          controller: _manualCodeController,
          keyboardType: TextInputType.number,
          decoration: inputDecoration('바코드 숫자 입력'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_manualCodeController.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (!mounted || submitted == null || submitted.isEmpty) return;
    Navigator.of(context).pop(submitted);
  }

  Future<void> _startScanner() async {
    if (!mounted) return;

    setState(() {
      _starting = true;
      _scannerError = null;
    });

    try {
      await _controller.stop();
    } catch (_) {}

    try {
      await _controller.start(cameraDirection: CameraFacing.back);
      if (!mounted) return;
      setState(() {
        _starting = false;
        _readyForWebTap = false;
      });
    } on MobileScannerException catch (error) {
      if (kIsWeb) {
        try {
          await _controller.start(cameraDirection: CameraFacing.front);
          if (!mounted) return;
          setState(() {
            _starting = false;
            _readyForWebTap = false;
            _scannerError = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('후면 카메라 대신 사용 가능한 카메라로 연결했어요.')),
          );
          return;
        } on MobileScannerException catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _starting = false;
        _readyForWebTap = kIsWeb;
        _scannerError = error.errorDetails?.message ?? error.errorCode.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _readyForWebTap = kIsWeb;
        _scannerError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF8FDFF),
        borderRadius: widget.pageMode
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: !widget.pageMode,
        child: SizedBox(
          height: widget.pageMode
              ? double.infinity
              : MediaQuery.of(context).size.height * 0.82,
          child: Column(
            children: [
              if (!widget.pageMode) ...[
                const SizedBox(height: 12),
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E4EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '상품 바코드 스캔',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '바코드를 정면으로 맞추면 상품명을 자동으로 불러와요.',
                            style: TextStyle(
                              color: Color(0xFF7E90A0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF6FF),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFFD2E9F7)),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: MobileScanner(
                                  controller: _controller,
                                  onDetect: (capture) {
                                    if (_handled) return;
                                    final value = capture.barcodes
                                        .map(
                                          (barcode) =>
                                              (barcode.rawValue ??
                                                      barcode.displayValue ??
                                                      '')
                                                  .trim(),
                                        )
                                        .firstWhere(
                                          (value) => value.isNotEmpty,
                                          orElse: () => '',
                                        );
                                    if (value.isEmpty) return;
                                    _handled = true;
                                    Navigator.of(context).pop(value);
                                  },
                                  errorBuilder: (_, exception) {
                                    return _ScannerStatusCard(
                                      title: '카메라를 시작하지 못했어요',
                                      description:
                                          exception.errorDetails?.message ??
                                          exception.errorCode.message,
                                      showRetry: true,
                                      onRetry: _startScanner,
                                    );
                                  },
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(80),
                                  ),
                                ),
                              ),
                              if (_showGuide)
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 500),
                                  opacity: _showGuide ? 1 : 0,
                                  child: const Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: EdgeInsets.only(top: 22),
                                      child: _GuideBadge(),
                                    ),
                                  ),
                                ),
                              if (_readyForWebTap)
                                Align(
                                  alignment: Alignment.center,
                                  child: FilledButton.icon(
                                    onPressed: _startScanner,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.lime,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                        vertical: 16,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.photo_camera_outlined,
                                    ),
                                    label: const Text('카메라 켜기'),
                                  ),
                                ),
                              if (_starting)
                                const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: EdgeInsets.all(18),
                                    child: _ScannerLoadingCard(),
                                  ),
                                ),
                              if (_scannerError != null && !_starting)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: _ScannerStatusCard(
                                      title: '카메라 연결 확인 필요',
                                      description: _scannerError!,
                                      showRetry: true,
                                      onRetry: _startScanner,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openManualBarcodeInput,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.navy,
                            side: const BorderSide(color: Color(0xFFD4E2EA)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(Icons.keyboard_alt_rounded),
                          label: const Text('바코드 직접 입력'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideBadge extends StatelessWidget {
  const _GuideBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(232),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '바코드를 중앙에 맞춰 주세요',
        style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ScannerLoadingCard extends StatelessWidget {
  const _ScannerLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.limeDeep,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '카메라 준비 중',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerStatusCard extends StatelessWidget {
  const _ScannerStatusCard({
    required this.title,
    required this.description,
    required this.showRetry,
    required this.onRetry,
  });

  final String title;
  final String description;
  final bool showRetry;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF678095),
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (showRetry)
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('다시 시도'),
                ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('권한 확인 방법'),
                      content: const Text(
                        '브라우저 주소창의 사이트 정보에서 카메라가 허용인지 확인하고, 휴대폰 설정의 Chrome 또는 Safari 앱 권한에서도 카메라가 허용인지 확인해 주세요.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('확인'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('권한 확인 방법'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotIntroCard extends StatelessWidget {
  const _BotIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4EEF4)),
      ),
      child: const Text(
        '편봇이 준비됐어요. 지금 기분이나 상황을 말해주면, 초기설정과 좋아요 기록을 기준으로 꿀조합 공유 게시글을 추천해드릴게요.',
        style: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          height: 1.7,
        ),
      ),
    );
  }
}

class _BotMessageBubble extends StatelessWidget {
  const _BotMessageBubble({
    required this.message,
    required this.posts,
    required this.onOpenPost,
  });

  final BotMessage message;
  final List<Post> posts;
  final ValueChanged<String> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final recommended = posts
        .where((post) => message.recommendedPostIds.contains(post.id))
        .toList();
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser &&
                (message.resolvedBudget != null ||
                    message.minimumPrice != null ||
                    message.useAgeCalorieGuide != null)) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (message.resolvedBudget != null)
                    _BotConditionChip(
                      label: '예산 ${_formatWon(message.resolvedBudget!)} 이하',
                    ),
                  if (message.minimumPrice != null)
                    _BotConditionChip(
                      label: '${_formatWon(message.minimumPrice!)} 이상',
                    ),
                  if (message.useAgeCalorieGuide != null)
                    _BotConditionChip(
                      label: message.useAgeCalorieGuide!
                          ? '권장 칼로리 반영'
                          : '권장 칼로리 제외',
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFFE8F3FF)
                    : const Color(0xFFF9FCFE),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFFCFE0F7)
                      : const Color(0xFFE6EEF3),
                ),
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.7,
                ),
              ),
            ),
            if (!isUser && recommended.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...recommended.map(
                (post) => GestureDetector(
                  onTap: () => onOpenPost(post.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE3EDF3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.title,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${post.categories.join(', ')} · ${post.priceLabel}',
                                style: const TextStyle(
                                  color: Color(0xFF7B90A1),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.open_in_new_rounded,
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BotConditionChip extends StatelessWidget {
  const _BotConditionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7EA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E8B8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TasteRatingEditor extends StatelessWidget {
  const _TasteRatingEditor({required this.ratings, required this.onChanged});

  final Map<String, int> ratings;
  final void Function(String taste, int value) onChanged;

  static const Map<String, Color> _tasteFillColors = <String, Color>{
    '달달': Color(0xFFFF8EB2),
    '매콤': Color(0xFFFF7A59),
    '새콤': Color(0xFFF3CB47),
    '짭짤': Color(0xFF5DBFD2),
  };

  Color _fillColorFor(String taste) =>
      _tasteFillColors[taste] ?? const Color(0xFFFFC85A);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: ratings.entries.map((entry) {
        final fillColor = _fillColorFor(entry.key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.value}/5',
                    style: const TextStyle(
                      color: Color(0xFF6E8395),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Row(
                  children: List.generate(5, (index) {
                    final score = index + 1;
                    final active = score <= entry.value;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index == 4 ? 0 : 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onChanged(entry.key, score),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? fillColor
                                  : const Color(0xFFF0F4F7),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: active
                                    ? fillColor.withValues(alpha: 0.92)
                                    : const Color(0xFFDCE5EB),
                              ),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: fillColor.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              '$score',
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : const Color(0xFF93A3B0),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ReadOnlyTasteAverages extends StatelessWidget {
  const _ReadOnlyTasteAverages({required this.averages});

  final Map<String, double> averages;

  static const Map<String, Color> _tasteFillColors = <String, Color>{
    '달달': Color(0xFFFF8EB2),
    '매콤': Color(0xFFFF7A59),
    '새콤': Color(0xFFF3CB47),
    '짭짤': Color(0xFF5DBFD2),
  };

  @override
  Widget build(BuildContext context) {
    const order = <String>['달달', '새콤', '짭짤', '매콤'];

    return Column(
      children: order.map((taste) {
        final value = averages[taste] ?? 0;
        final clamped = value.clamp(0, 5);
        final percent = clamped / 5;
        final color = _tasteFillColors[taste] ?? const Color(0xFFFFC85A);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    taste,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${clamped.toStringAsFixed(1)}/5',
                    style: const TextStyle(
                      color: Color(0xFF6E8395),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 14,
                  color: const Color(0xFFEAF0F5),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent,
                    child: Container(color: color),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PriorityChoiceWrap extends StatelessWidget {
  const _PriorityChoiceWrap({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final List<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: labels.map((label) {
        final rank = selected.indexOf(label);
        final active = rank >= 0;
        return GestureDetector(
          onTap: () {
            if (active) {
              selected.remove(label);
            } else if (selected.length < 2) {
              selected.add(label);
            } else {
              selected
                ..removeAt(1)
                ..add(label);
            }
            onChanged();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? rank == 0
                        ? AppColors.activeYellow
                        : const Color(0xFFEAF6FF)
                  : const Color(0xFFF4F7F9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? rank == 0
                          ? const Color(0xFFE2B92F)
                          : const Color(0xFFB9DDF5)
                    : const Color(0xFFDDE6EC),
              ),
            ),
            child: Text(
              active ? '${rank + 1}위 $label' : label,
              style: TextStyle(
                color: active ? AppColors.ink : const Color(0xFF718697),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChoiceWrap extends StatefulWidget {
  const _ChoiceWrap({required this.labels, required this.selected});

  final List<String> labels;
  final Set<String> selected;

  @override
  State<_ChoiceWrap> createState() => _ChoiceWrapState();
}

class _ChoiceWrapState extends State<_ChoiceWrap> {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: widget.labels.map((label) {
        final active = widget.selected.contains(label);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (active) {
                widget.selected.remove(label);
              } else {
                widget.selected.add(label);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.activeYellow : const Color(0xFFFFF9D7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF715C12),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UserPill extends StatelessWidget {
  const _UserPill({required this.user, required this.onTap});

  final PyeonUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(228),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD8E9EF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _UserAvatar(imageSource: user.profileImageUrl, radius: 14),
            const SizedBox(width: 8),
            Text(
              user.nickname,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Color(0xFF7A8FA4),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotReply {
  const _BotReply({
    required this.text,
    required this.memoryNote,
    required this.recommendedPostIds,
    this.resolvedBudget,
    this.minimumPrice,
    this.contextPrompt,
    this.useAgeCalorieGuide,
    this.pendingClarification,
    this.pendingAmount,
    this.shouldSyncBudget = false,
  });

  final String text;
  final String memoryNote;
  final List<String> recommendedPostIds;
  final int? resolvedBudget;
  final int? minimumPrice;
  final String? contextPrompt;
  final bool? useAgeCalorieGuide;
  final String? pendingClarification;
  final int? pendingAmount;
  final bool shouldSyncBudget;
}

class _SituationAnalysis {
  const _SituationAnalysis({
    required this.moods,
    required this.emotionSummary,
    required this.hasPositiveSignal,
    required this.recognizedSituation,
    required this.memoryNote,
  });

  final List<String> moods;
  final String emotionSummary;
  final bool hasPositiveSignal;
  final bool recognizedSituation;
  final String memoryNote;
}
