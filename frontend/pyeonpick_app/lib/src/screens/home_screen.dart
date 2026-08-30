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
import '../core/image_url.dart';
import '../data/cu_product_catalog.dart';
import '../models/app_tab.dart';
import '../models/battle_results.dart';
import '../models/combination_battle.dart';
import '../models/bot_conversation.dart';
import '../models/bot_message.dart';
import '../models/post.dart';
import '../models/post_feature_index.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/pyeon_user.dart';
import '../models/sort_mode.dart';
import '../repositories/post_repository.dart';
import '../services/bot_budget_rules.dart';
import '../services/bot_situation_analyzer.dart';
import '../services/local_account_store.dart';
import '../widgets/cu_product_badges.dart';
import 'combination_battle_screen.dart';
import 'post_reviews_screen.dart';

const List<String> _suggestedSearchCategories = <String>[
  '달달',
  '매콤',
  '새콤',
  '짭짤',
  '저칼로리',
  '가성비',
  '시간절약',
  '호불호',
  '트렌드',
];

enum HighlightCollectionType {
  popular,
  malePicks,
  femalePicks,
  newProduct,
  pbProduct,
  rediscovered,
}

const List<String> _highlightStores = <String>[
  'CU',
  'GS25',
  '7-Eleven',
  'emart24',
];

String _storeDisplayName(String store) => switch (store) {
  '7-Eleven' => '세븐일레븐',
  'emart24' => 'emart24',
  _ => store,
};

Color _storeColor(String store) => switch (store) {
  'CU' => const Color(0xFF652F8F),
  'GS25' => const Color(0xFF1C75BC),
  '7-Eleven' => const Color(0xFF008061),
  'emart24' => const Color(0xFFF05A28),
  _ => AppColors.skyBlueDeep,
};

List<CuProductMatch> _productMatchesForPost(Post post) {
  final productText = post.details.usedProducts.isEmpty
      ? post.title
      : post.details.usedProducts.join(' + ');
  return <CuProductMatch>[
    ...CuProductCatalog.matchesForText(productText),
    ...CuProductCatalog.contextMatchesForTitle(
      productText,
      '$productText ${post.title} ${post.content}',
    ),
  ];
}

bool _postMatchesStore(Post post, String store) =>
    _productMatchesForPost(post).any((match) => match.store == store);

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

bool _postHasNewProduct(Post post) => _productMatchesForPost(
  post,
).any((match) => match.labels.contains(CuProductLabel.newProduct));

bool _postHasPbProduct(Post post) => _productMatchesForPost(
  post,
).any((match) => match.labels.contains(CuProductLabel.pbProduct));

String _featureProductText(PostFeatureInfo post) =>
    post.usedProducts.isEmpty ? post.title : post.usedProducts.join(' + ');

bool _featureHasNewProduct(PostFeatureInfo post) =>
    _titleHasNewProduct(_featureProductText(post));

bool _featureHasPbProduct(PostFeatureInfo post) =>
    _titleHasPbProduct(_featureProductText(post));

String _formatWon(int amount) {
  return '${NumberFormat.decimalPattern('ko_KR').format(amount)}원';
}

String _displayImageUrl(String imageUrl) {
  return displayImageUrl(imageUrl);
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

  bool hasGenderMajority(PostFeatureInfo post, String gender) {
    if (post.genderLikeTotal <= 0) return false;
    final ratio = gender == 'male' ? post.maleLikeRatio : post.femaleLikeRatio;
    return ratio >= 0.75;
  }

  int genderMajorityScore(PostFeatureInfo post, String gender) {
    final targetCount = gender == 'male'
        ? post.maleLikeCount
        : post.femaleLikeCount;
    final ratio = gender == 'male' ? post.maleLikeRatio : post.femaleLikeRatio;
    return (ratio * 1000).round() + (targetCount * 20) + post.likes;
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
  final maleMajority = ranked(
    posts.where((post) => hasGenderMajority(post, 'male')),
    (post) => genderMajorityScore(post, 'male'),
  );
  final femaleMajority = ranked(
    posts.where((post) => hasGenderMajority(post, 'female')),
    (post) => genderMajorityScore(post, 'female'),
  );

  return <_CommunityTrendGroup>[
    if (weeklyPopular.isNotEmpty)
      _CommunityTrendGroup(
        label: '이번 주 난리난 조합',
        caption: '하트가 가장 빠르게 몰린 조합',
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFFFF7A1A),
        posts: weeklyPopular,
      ),
    _CommunityTrendGroup(
      label: '다시 뜨는 조합',
      caption: rediscovered.isEmpty
          ? '다음 재발견 조합을 기다리는 중'
          : '묻혀 있던 조합이 다시 반응 오는 중',
      icon: Icons.replay_circle_filled_rounded,
      color: const Color(0xFF4F7DF0),
      posts: rediscovered,
    ),
    _CommunityTrendGroup(
      label: '남',
      caption: maleMajority.isEmpty ? '남자 하트 75% 이상 대기 중' : '남자 하트 75% 이상',
      icon: Icons.male_rounded,
      color: const Color(0xFF2869E6),
      posts: maleMajority,
    ),
    _CommunityTrendGroup(
      label: '여',
      caption: femaleMajority.isEmpty ? '여자 하트 75% 이상 대기 중' : '여자 하트 75% 이상',
      icon: Icons.female_rounded,
      color: const Color(0xFFE65086),
      posts: femaleMajority,
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

class _DiscoveryTopic {
  const _DiscoveryTopic({
    required this.label,
    required this.caption,
    required this.icon,
    required this.color,
    required this.posts,
    this.collectionType,
    this.battles = const <_BattleDiscoveryItem>[],
    this.decisiveBattleCollection,
  });

  final String label;
  final String caption;
  final IconData icon;
  final Color color;
  final List<PostFeatureInfo> posts;
  final HighlightCollectionType? collectionType;
  final List<_BattleDiscoveryItem> battles;
  final bool? decisiveBattleCollection;

  int get itemCount => posts.isNotEmpty ? posts.length : battles.length;
}

class _BattleDiscoveryItem {
  const _BattleDiscoveryItem({
    required this.match,
    required this.leftTitle,
    required this.rightTitle,
    this.leftImageUrl,
    this.rightImageUrl,
  });

  final BattleMatchEntry match;
  final String leftTitle;
  final String rightTitle;
  final String? leftImageUrl;
  final String? rightImageUrl;
}

List<_DiscoveryTopic> _buildDiscoveryTopics(
  List<PostFeatureInfo> posts,
  List<_CommunityTrendGroup> trends, [
  List<BattleMatchEntry> battleHighlights = const <BattleMatchEntry>[],
]) {
  _CommunityTrendGroup? trend(String label) {
    for (final item in trends) {
      if (item.label == label) return item;
    }
    return null;
  }

  List<PostFeatureInfo> ranked(
    Iterable<PostFeatureInfo> candidates,
    int Function(PostFeatureInfo post) score,
  ) {
    final result = candidates.toList()
      ..sort((a, b) {
        final compared = score(b).compareTo(score(a));
        return compared != 0 ? compared : b.createdAt.compareTo(a.createdAt);
      });
    return result.take(5).toList();
  }

  final popular = trend('이번 주 난리난 조합');
  final rediscovered = trend('다시 뜨는 조합');
  final malePicks = trend('남');
  final femalePicks = trend('여');
  final fallbackPopular = ranked(
    posts,
    (post) => (post.likes * 5) + (post.reviewCount * 4) - post.dislikes,
  );
  final newProducts = ranked(
    posts.where(_featureHasNewProduct),
    (post) => post.createdAt.millisecondsSinceEpoch,
  );
  final pbProducts = ranked(
    posts.where(_featureHasPbProduct),
    (post) => (post.likes * 4) + (post.reviewCount * 3),
  );
  final featuresById = {for (final post in posts) post.id: post};
  _BattleDiscoveryItem battleItem(BattleMatchEntry match) {
    final left = featuresById[match.leftPostId];
    final right = featuresById[match.rightPostId];
    return _BattleDiscoveryItem(
      match: match,
      leftTitle: match.leftCustomTitle ?? left?.title ?? '첫 번째 조합',
      rightTitle: match.rightCustomTitle ?? right?.title ?? '두 번째 조합',
      leftImageUrl: match.leftCustomImageUrl ?? left?.imageUrl,
      rightImageUrl: match.rightCustomImageUrl ?? right?.imageUrl,
    );
  }

  final decisiveBattles = battleHighlights
      .where((match) => match.isDecisiveResult)
      .take(5)
      .map(battleItem)
      .toList();
  final closeBattles = battleHighlights
      .where((match) => match.isCloseResult)
      .take(5)
      .map(battleItem)
      .toList();

  return <_DiscoveryTopic>[
    _DiscoveryTopic(
      label: '이번 주 인기',
      caption: '지금 사람들이 실제로 반응하는 조합',
      icon: Icons.local_fire_department_rounded,
      color: const Color(0xFFFF8A4C),
      posts: popular?.posts ?? fallbackPopular,
      collectionType: HighlightCollectionType.popular,
    ),
    _DiscoveryTopic(
      label: '남자들이 많이 고른 조합',
      caption: '남자 하트 비중이 75% 이상인 조합',
      icon: Icons.male_rounded,
      color: const Color(0xFF2869E6),
      posts: malePicks?.posts ?? const <PostFeatureInfo>[],
      collectionType: HighlightCollectionType.malePicks,
    ),
    _DiscoveryTopic(
      label: '여자들이 많이 고른 조합',
      caption: '여자 하트 비중이 75% 이상인 조합',
      icon: Icons.female_rounded,
      color: const Color(0xFFE65086),
      posts: femalePicks?.posts ?? const <PostFeatureInfo>[],
      collectionType: HighlightCollectionType.femalePicks,
    ),
    _DiscoveryTopic(
      label: '새로 들어온 조합',
      caption: '처음 보는 제품이 들어간 최신 조합',
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF62D4FF),
      posts: newProducts,
      collectionType: HighlightCollectionType.newProduct,
    ),
    _DiscoveryTopic(
      label: 'PB로 만든 조합',
      caption: '편의점별 PB 제품으로 찾은 조합',
      icon: Icons.local_offer_rounded,
      color: const Color(0xFFFFD36C),
      posts: pbProducts,
      collectionType: HighlightCollectionType.pbProduct,
    ),
    _DiscoveryTopic(
      label: '재평가',
      caption: '묻혀 있다가 최근 다시 반응이 붙은 조합',
      icon: Icons.replay_circle_filled_rounded,
      color: const Color(0xFF8FA7FF),
      posts: rediscovered?.posts ?? const <PostFeatureInfo>[],
      collectionType: HighlightCollectionType.rediscovered,
    ),
    _DiscoveryTopic(
      label: '압도적 픽쇼츠',
      caption: '8표 이상, 두 배 차이로 선택이 갈린 결과',
      icon: Icons.bolt_rounded,
      color: AppColors.skyBlue,
      posts: const <PostFeatureInfo>[],
      battles: decisiveBattles,
      decisiveBattleCollection: true,
    ),
    _DiscoveryTopic(
      label: '박빙 픽쇼츠',
      caption: '8표 이상, 세 표 이내로 갈린 결과',
      icon: Icons.balance_rounded,
      color: AppColors.lime,
      posts: const <PostFeatureInfo>[],
      battles: closeBattles,
      decisiveBattleCollection: false,
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
    required this.onPostReactionChanged,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final PostRepository repository;
  final AppEnvironment environment;
  final PyeonUser currentUser;
  final Future<void> Function(PyeonUser user) onUserChanged;
  final ValueChanged<Post> onPostReactionChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function(String password) onDeleteAccount;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _minFilterController = TextEditingController();
  final _maxFilterController = TextEditingController();
  final _communicationScrollController = ScrollController();
  final Set<String> _selectedSearchTags = <String>{};
  final Set<String> _reactionRequests = <String>{};

  AppTab _selectedTab = AppTab.communication;
  SortMode _sortMode = SortMode.latest;
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
  bool _pickedAuthorsOnly = false;
  List<BattleMatchEntry> _battleHighlights = <BattleMatchEntry>[];
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
      for (final post in _featurePostPool)
        post.id: PostFeatureInfo.fromPost(post),
      for (final post in _posts) post.id: PostFeatureInfo.fromPost(post),
      for (final post in _postFeatureIndex) post.id: post,
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
    _loadBattleHighlights();
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
        _loading = _posts.isEmpty;
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
        currentUserId: widget.currentUser.id,
        authorIds: _pickedAuthorsOnly
            ? widget.currentUser.pickedAuthorIds
            : null,
        cursor: reset ? null : _nextPostsCursor,
        limit: 12,
        sortMode: _sortMode,
      );
      final pagePosts = page.posts.map(_withCurrentUserReaction).toList();

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
      if (reset && _postFeatureIndex.isEmpty) {
        unawaited(_loadPostFeatureIndex());
      }
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

  Future<void> _loadBattleHighlights() async {
    try {
      final matches = await widget.repository.fetchBattleHighlights();
      if (mounted) setState(() => _battleHighlights = matches);
    } catch (_) {
      // Community remains usable when the optional highlight feed is unavailable.
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
    return post;
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
    PostFeatureInfo? previous;
    for (final item in _postFeatureIndex) {
      if (item.id == post.id) {
        previous = item;
        break;
      }
    }
    final nextFeature = PostFeatureInfo.fromPost(post).copyWith(
      maleLikeCount: previous?.maleLikeCount,
      femaleLikeCount: previous?.femaleLikeCount,
    );
    final next = <String, PostFeatureInfo>{
      for (final item in _postFeatureIndex) item.id: item,
      post.id: nextFeature,
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
    if (_reactionRequests.contains(post.id)) return;
    _reactionRequests.add(post.id);
    final optimistic = post.copyWith(
      likedByMe: !post.likedByMe,
      dislikedByMe: false,
      likes: math.max(0, post.likes + (post.likedByMe ? -1 : 1)),
      dislikes: math.max(
        0,
        post.dislikes + (post.dislikedByMe && !post.likedByMe ? -1 : 0),
      ),
    );
    _applyUpdatedPost(optimistic);
    try {
      final updated = await widget.repository.toggleLike(
        post.id,
        widget.currentUser.id,
      );
      if (!mounted) return;
      _applyUpdatedPost(updated);
      widget.onPostReactionChanged(updated);
    } catch (_) {
      if (!mounted) return;
      _applyUpdatedPost(post);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('하트를 반영하지 못했어요.')));
    } finally {
      _reactionRequests.remove(post.id);
    }
  }

  Future<void> _toggleDislike(Post post) async {
    if (_reactionRequests.contains(post.id)) return;
    _reactionRequests.add(post.id);
    final optimistic = post.copyWith(
      dislikedByMe: !post.dislikedByMe,
      likedByMe: false,
      dislikes: math.max(0, post.dislikes + (post.dislikedByMe ? -1 : 1)),
      likes: math.max(
        0,
        post.likes + (post.likedByMe && !post.dislikedByMe ? -1 : 0),
      ),
    );
    _applyUpdatedPost(optimistic);
    try {
      final updated = await widget.repository.toggleDislike(
        post.id,
        widget.currentUser.id,
      );
      if (!mounted) return;
      _applyUpdatedPost(updated);
      widget.onPostReactionChanged(updated);
    } catch (_) {
      if (!mounted) return;
      _applyUpdatedPost(post);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('싫어요를 반영하지 못했어요.')));
    } finally {
      _reactionRequests.remove(post.id);
    }
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
    final userId = widget.currentUser.id;
    final setup = widget.currentUser.botSetup;
    if (setup == null) return const BotTurnResult();
    final previousMessages = List<BotMessage>.from(
      widget.currentUser.botMessages,
    );

    final userMessage = BotMessage(
      role: 'user',
      text: prompt,
      createdAt: DateTime.now(),
    );
    final userMessageSave = widget
        .onUserChanged(
          widget.currentUser.copyWith(
            botMessages: <BotMessage>[...previousMessages, userMessage],
          ),
        )
        .catchError((Object _) {
          // The complete turn save below retries a failed draft save.
        });
    if (_botRecommendationPosts.isEmpty) {
      await _loadBotRecommendationPool(reset: true);
    }
    if (!mounted || widget.currentUser.id != userId) {
      return const BotTurnResult();
    }
    final aiSituation = await BotSituationAnalyzer.analyze(
      environment: widget.environment,
      prompt: prompt,
      memoryNotes: widget.currentUser.memoryNotes,
    );
    if (!mounted || widget.currentUser.id != userId) {
      return const BotTurnResult();
    }
    final reply = _buildBotReply(
      prompt,
      setup,
      aiSituation: aiSituation,
      useAgeCalorieGuide: useAgeCalorieGuide,
      currentBudget: currentBudget,
    );
    final conversationalText = await _conversationalBotReply(
      prompt,
      previousMessages,
      reply,
    );
    if (!mounted || widget.currentUser.id != userId) {
      return const BotTurnResult();
    }
    final assistantMessage = BotMessage(
      role: 'assistant',
      text: conversationalText,
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
      ...previousMessages,
      userMessage,
      assistantMessage,
    ];
    try {
      await userMessageSave;
    } catch (_) {
      // The complete turn save below is the authoritative retry.
    }
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
    final userId = widget.currentUser.id;
    final setup = widget.currentUser.botSetup;
    if (setup == null) return;
    await _loadBotRecommendationPool();
    if (!mounted || widget.currentUser.id != userId) return;

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
    if (!mounted || widget.currentUser.id != userId) return;
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
    final conversationalText = await _conversationalBotReply(
      '$prompt\n앞에서 본 후보를 제외하고 다른 조합을 추천해줘.',
      widget.currentUser.botMessages,
      reply,
    );
    if (!mounted || widget.currentUser.id != userId) return;
    final assistantMessage = BotMessage(
      role: 'assistant',
      text: conversationalText,
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

  Future<String> _conversationalBotReply(
    String prompt,
    List<BotMessage> history,
    _BotReply reply,
  ) async {
    final text = await BotSituationAnalyzer.reply(
      environment: widget.environment,
      prompt: prompt,
      history: history,
      candidateIds: reply.recommendedPostIds,
      draft: reply.text,
      maximumBudget: reply.resolvedBudget,
      minimumPrice: reply.minimumPrice,
      pendingClarification: reply.pendingClarification,
    );
    return text?.trim().isNotEmpty == true ? text! : reply.text;
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
    String varied(List<String> options) {
      final turn = widget.currentUser.botMessages.length;
      final promptSeed = prompt.runes.fold<int>(0, (sum, rune) => sum + rune);
      return options[(turn + promptSeed) % options.length];
    }

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
      return _BotReply(
        text: varied(const [
          '안녕! 오늘은 뭐가 당겨? 기분이나 예산만 편하게 말해줘도 같이 골라볼게.',
          '반가워. 지금 어떤 상태인지부터 들어볼까? 먹고 싶은 맛, 남은 돈, 시간 중 하나만 말해줘도 돼.',
          '왔구나. 오늘 기분에 맞는 조합을 찾아보자. 지금 제일 중요한 게 맛인지, 예산인지부터 알려줘.',
        ]),
        memoryNote: '인사로 대화 시작',
        recommendedPostIds: const <String>[],
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
          ? varied(const [
              '별말을. 방금 후보 중 끌리는 게 있으면 둘만 놓고 비교해보자.',
              '좋아. 먹어보고 어땠지 궁금하네. 다음엔 더 매콤하게, 더 가볍게처럼 바꿔서도 골라줄게.',
              '언제든지. 방금 추천에서 가성비나 맛 하나만 더 중요하면 바로 줄여보자.',
            ])
          : varied(const [
              '별말을. 원할 때 지금 상황만 한 줄로 말해줘.',
              '좋아. 지금은 그냥 얘기만 이어가도 돼.',
              '언제든지. 맛이나 예산이 정해지면 그때 바로 골라줄게.',
            ]);
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
        text: '예산은 얼마 있어?',
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
                  votePreferences: aiSituation?.preferences,
                  useAgeCalorieGuide: useAgeCalorieGuide,
                ) -
                _scorePost(
                  a,
                  setup,
                  likedPosts,
                  targetCategories.toList(),
                  prompt: recommendationPrompt,
                  votePreferences: aiSituation?.preferences,
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
        ? varied(const [
            '이 셋 중 끌리는 걸 말해주면 같이 하나까지 좁혀보자.',
            '지금은 선택을 서두르지 않아도 돼. 마음 가는 후보만 찜해두자.',
          ])
        : varied(const [
            '취향과 좋아요 기록을 같이 보고 골랐어. 두 개가 고민되면 바로 비교해줄게.',
            '지금 조건에서 가능성 높은 순서야. 더 싼 것, 더 맛이 센 것으로 다시 좁혀도 돼.',
            '우선 이 세 개부터 보자. 하나가 마음에 걸리면 그 이유를 중심으로 다시 골라줄게.',
          ]);
    final replyText = recommendations.isEmpty
        ? '$empathyText\n\n$recommendationText'
        : '$empathyText\n\n$reasonText\n\n$closing';

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
    BotVotePreferences? votePreferences,
  }) {
    var score = votePreferences?.score(post.categories) ?? 0;
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
    final features = {for (final item in _allFeatureInfo) item.id: item};
    final now = DateTime.now();
    final activityWindow = now.subtract(const Duration(days: 30));
    bool matchesFeature(Post post) {
      final feature = features[post.id];
      if (feature == null) return false;
      return switch (type) {
        HighlightCollectionType.popular =>
          feature.likes >= 10 &&
              feature.likes >= math.max(1, feature.dislikes * 3),
        HighlightCollectionType.malePicks =>
          feature.genderLikeTotal > 0 && feature.maleLikeRatio >= 0.75,
        HighlightCollectionType.femalePicks =>
          feature.genderLikeTotal > 0 && feature.femaleLikeRatio >= 0.75,
        HighlightCollectionType.rediscovered =>
          feature.createdAt.isBefore(now.subtract(const Duration(days: 7))) &&
              (feature.recentLikeCount >= 2 ||
                  (feature.topFiveEnteredAt?.isAfter(activityWindow) ?? false)),
        _ => false,
      };
    }

    final posts = switch (type) {
      HighlightCollectionType.newProduct =>
        allPosts.where(_postHasNewProduct).toList(),
      HighlightCollectionType.pbProduct =>
        allPosts.where(_postHasPbProduct).toList(),
      _ => allPosts.where(matchesFeature).toList(),
    };
    final title = switch (type) {
      HighlightCollectionType.popular => '이번 주 인기',
      HighlightCollectionType.malePicks => '남자들이 많이 고른 조합',
      HighlightCollectionType.femalePicks => '여자들이 많이 고른 조합',
      HighlightCollectionType.newProduct => '신상',
      HighlightCollectionType.pbProduct => 'PB',
      HighlightCollectionType.rediscovered => '재평가',
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

  Future<void> _togglePickedAuthorsOnly() async {
    if (widget.currentUser.pickedAuthorIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 마음에 드는 작성자를 픽해 주세요.')));
      return;
    }
    setState(() => _pickedAuthorsOnly = !_pickedAuthorsOnly);
    await _loadPosts();
  }

  void _openBattleHighlights(bool decisive) {
    final matches = _battleHighlights.where(
      (match) => decisive ? match.isDecisiveResult : match.isCloseResult,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BattleHighlightsPage(
          title: decisive ? '압도적' : '박빙',
          matches: matches.toList(),
          posts: _allFunctionalPosts,
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final desktop = screenWidth >= 900;
    return Scaffold(
      floatingActionButton: _selectedTab == AppTab.communication
          ? FloatingActionButton.extended(
              onPressed: () => _openComposer(),
              backgroundColor: AppColors.lime,
              foregroundColor: AppColors.ink,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                '올리기',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      body: Container(
        color: AppColors.paper,
        child: SafeArea(
          child: Column(
            children: [
              ...[
                Container(height: 1, color: AppColors.lime),
                Container(
                  width: double.infinity,
                  color: AppColors.receipt,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1760),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 34 : 16,
                          desktop ? 18 : 12,
                          desktop ? 34 : 12,
                          desktop ? 14 : 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '편pick!',
                                        style: TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w900,
                                          fontSize: desktop ? 38 : 22,
                                          letterSpacing: -0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '24H CONVENIENCE PICKS',
                                        style: TextStyle(
                                          color: AppColors.skyBlueDeep,
                                          fontSize: desktop ? 10 : 8.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: desktop ? 1.1 : 0.7,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _UserPill(
                                  user: widget.currentUser,
                                  onTap: _showOwnProfileTab,
                                ),
                              ],
                            ),
                            SizedBox(height: desktop ? 14 : 8),
                            FeatureTabs(
                              selectedTab: _selectedTab,
                              onChanged: (tab) =>
                                  setState(() => _selectedTab = tab),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = switch (_selectedTab) {
                        AppTab.communication => 1680.0,
                        AppTab.battle => 1100.0,
                        AppTab.bot => 1880.0,
                        AppTab.profile => 840.0,
                      };
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: SizedBox(
                            width: constraints.maxWidth < maxWidth
                                ? double.infinity
                                : maxWidth,
                            child: _buildSelectedPage(),
                          ),
                        ),
                      );
                    },
                  ),
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
          onOpenCollection: _openHighlightCollection,
          onShuffle: _shufflePosts,
          onScanBarcode: _scanCommunicationBarcode,
          pickedAuthorsOnly: _pickedAuthorsOnly,
          hasPickedAuthors: widget.currentUser.pickedAuthorIds.isNotEmpty,
          onTogglePickedAuthors: _togglePickedAuthorsOnly,
          battleHighlights: _battleHighlights,
          onOpenBattleHighlights: _openBattleHighlights,
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
          repository: widget.repository,
          posts: _allFunctionalPosts,
          onUserChanged: widget.onUserChanged,
          onResetBotSetup: _resetBotSetup,
          onLogout: widget.onLogout,
          onDeleteAccount: widget.onDeleteAccount,
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
    required this.onOpenCollection,
    required this.onShuffle,
    required this.onScanBarcode,
    required this.pickedAuthorsOnly,
    required this.hasPickedAuthors,
    required this.onTogglePickedAuthors,
    required this.battleHighlights,
    required this.onOpenBattleHighlights,
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
  final void Function(HighlightCollectionType type) onOpenCollection;
  final VoidCallback onShuffle;
  final Future<void> Function() onScanBarcode;
  final bool pickedAuthorsOnly;
  final bool hasPickedAuthors;
  final Future<void> Function() onTogglePickedAuthors;
  final List<BattleMatchEntry> battleHighlights;
  final ValueChanged<bool> onOpenBattleHighlights;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.skyBlueDeep),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.skyBlue,
                ),
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
    final trendPicks = _buildCommunityTrendPicks(featureIndex);
    final discoveryTopics = _buildDiscoveryTopics(
      featureIndex,
      trendPicks,
      battleHighlights,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1500
            ? 3
            : constraints.maxWidth >= 360
            ? 2
            : 1;
        final compactCards = constraints.maxWidth < 620;
        final gap = constraints.maxWidth >= 900 ? 16.0 : 12.0;
        final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 16.0;
        final rowCount = (posts.length / columns).ceil();

        return RefreshIndicator(
          color: AppColors.skyBlueDeep,
          onRefresh: onReload,
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              constraints.maxWidth >= 900 ? 22 : 14,
              horizontalPadding,
              100,
            ),
            children: [
              _DiscoveryStage(
                toolbar: Toolbar(
                  searchController: searchController,
                  titleSuggestions: featureIndex
                      .map((post) => post.title)
                      .toList(),
                  minFilterController: minFilterController,
                  maxFilterController: maxFilterController,
                  selectedTags: selectedTags,
                  onSearch: onReload,
                  onToggleTag: onToggleSearchTag,
                  onShuffle: onShuffle,
                  onScanBarcode: onScanBarcode,
                  pickedAuthorsOnly: pickedAuthorsOnly,
                  hasPickedAuthors: hasPickedAuthors,
                  onTogglePickedAuthors: onTogglePickedAuthors,
                ),
                topics: discoveryTopics,
                onOpenPost: (post) => unawaited(onOpenFeaturePost(post)),
                onOpenCollection: onOpenCollection,
                onOpenBattleCollection: onOpenBattleHighlights,
              ),
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
              const SizedBox(height: 12),
              if (posts.isEmpty)
                const EmptyState()
              else
                ...List.generate(rowCount, (rowIndex) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: gap),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) SizedBox(width: gap),
                          Expanded(
                            child: () {
                              final index = rowIndex * columns + column;
                              if (index >= posts.length) {
                                return const SizedBox.shrink();
                              }
                              final post = posts[index];
                              return PostCard(
                                post: post,
                                isMine: post.authorId == currentUser.id,
                                isSaved: currentUser.savedPostIds.contains(
                                  post.id,
                                ),
                                compact: compactCards,
                                onToggleLike: () => onToggleLike(post),
                                onToggleDislike: () => onToggleDislike(post),
                                onToggleSave: () => onToggleSave(post.id),
                                onEdit: () => onEditPost(post),
                                onDelete: () => onDeletePost(post),
                                onOpenAuthor: () => onOpenAuthor(post),
                                onOpenPost: () => onOpenPost(post),
                              );
                            }(),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              if (loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.skyBlueDeep,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
      child: const Column(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.skyBlueDeep,
            size: 34,
          ),
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

class BattleHighlightsPage extends StatelessWidget {
  const BattleHighlightsPage({
    super.key,
    required this.title,
    required this.matches,
    required this.posts,
  });

  final String title;
  final List<BattleMatchEntry> matches;
  final List<Post> posts;

  Post? _post(String id) => posts.where((post) => post.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 22),
        itemBuilder: (context, index) {
          final match = matches[index];
          final left = _post(match.leftPostId);
          final right = _post(match.rightPostId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                match.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _BattleResultSide(
                      post: left,
                      imageUrl: match.leftCustomImageUrl,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BattleResultSide(
                      post: right,
                      imageUrl: match.rightCustomImageUrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '${match.leftVotes}표  :  ${match.rightVotes}표',
                style: const TextStyle(
                  color: AppColors.skyBlueDeep,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BattleResultSide extends StatelessWidget {
  const _BattleResultSide({required this.post, required this.imageUrl});

  final Post? post;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final source = imageUrl?.trim().isNotEmpty == true
        ? imageUrl!.trim()
        : post?.allImageUrls.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: source == null
                ? const ColoredBox(color: AppColors.sky)
                : Image.network(_displayImageUrl(source), fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          post?.title ?? '직접 등록한 조합',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        return Row(
          children: tabs.map((item) {
            final active = selectedTab == item.tab;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(item.tab),
                borderRadius: BorderRadius.zero,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 16 : 3,
                    vertical: desktop ? 14 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: active ? AppColors.sky : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: active ? AppColors.lime : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: desktop ? 18 : 11,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      color: active ? AppColors.skyBlueDeep : AppColors.muted,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DiscoveryStage extends StatelessWidget {
  const _DiscoveryStage({
    required this.toolbar,
    required this.topics,
    required this.onOpenPost,
    required this.onOpenCollection,
    required this.onOpenBattleCollection,
  });

  final Widget toolbar;
  final List<_DiscoveryTopic> topics;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;
  final ValueChanged<bool> onOpenBattleCollection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 2 : 0),
              child: toolbar,
            ),
            SizedBox(height: wide ? 18 : 14),
            _DiscoveryAccordion(
              topics: topics,
              onOpenPost: onOpenPost,
              onOpenCollection: onOpenCollection,
              onOpenBattleCollection: onOpenBattleCollection,
            ),
          ],
        );
      },
    );
  }
}

// Kept temporarily separate while the new feed-style discovery surface settles.
// ignore: unused_element
class _LegacyDiscoveryStage extends StatelessWidget {
  const _LegacyDiscoveryStage({
    required this.toolbar,
    required this.topics,
    required this.onOpenPost,
    required this.onOpenCollection,
  });

  final Widget toolbar;
  final List<_DiscoveryTopic> topics;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF102E51),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B3554).withAlpha(32),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -46,
                top: -64,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF49B9E8).withAlpha(35),
                  ),
                ),
              ),
              Positioned(
                right: 74,
                bottom: -78,
                child: Transform.rotate(
                  angle: -0.28,
                  child: Container(
                    width: 180,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB85C).withAlpha(20),
                      borderRadius: BorderRadius.circular(36),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 22 : 16,
                  wide ? 20 : 17,
                  wide ? 22 : 16,
                  wide ? 21 : 17,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(28),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withAlpha(38),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 13,
                                color: Color(0xFFFFCE72),
                              ),
                              SizedBox(width: 4),
                              Text(
                                '편픽 탐색대',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '지금 반응 오는 조합만',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      '지금, 편의점에서 뭐가 뜰까?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: wide ? 25 : 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '찾고 싶은 조합을 검색하거나 오늘 반응이 모이는 코너를 가볍게 훑어보세요.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 15),
                    toolbar,
                    const SizedBox(height: 17),
                    _LegacyDiscoveryAccordion(
                      topics: topics,
                      onOpenPost: onOpenPost,
                      onOpenCollection: onOpenCollection,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscoveryAccordion extends StatefulWidget {
  const _DiscoveryAccordion({
    required this.topics,
    required this.onOpenPost,
    required this.onOpenCollection,
    required this.onOpenBattleCollection,
  });

  final List<_DiscoveryTopic> topics;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;
  final ValueChanged<bool> onOpenBattleCollection;

  @override
  State<_DiscoveryAccordion> createState() => _DiscoveryAccordionState();
}

class _DiscoveryAccordionState extends State<_DiscoveryAccordion> {
  final Set<int> _expanded = <int>{0};

  @override
  Widget build(BuildContext context) {
    if (widget.topics.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('discovery-topic-accordion'),
      children: widget.topics.indexed.map((entry) {
        final index = entry.$1;
        final expanded = _expanded.contains(index);
        return _DiscoveryTopicShelf(
          key: Key('discovery-topic-$index'),
          topic: entry.$2,
          expanded: expanded,
          onToggle: () => setState(() {
            expanded ? _expanded.remove(index) : _expanded.add(index);
          }),
          onOpenPost: widget.onOpenPost,
          onOpenCollection: widget.onOpenCollection,
          onOpenBattleCollection: widget.onOpenBattleCollection,
        );
      }).toList(),
    );
  }
}

class _DiscoveryTopicShelf extends StatelessWidget {
  const _DiscoveryTopicShelf({
    super.key,
    required this.topic,
    required this.expanded,
    required this.onToggle,
    required this.onOpenPost,
    required this.onOpenCollection,
    required this.onOpenBattleCollection,
  });

  final _DiscoveryTopic topic;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;
  final ValueChanged<bool> onOpenBattleCollection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final cardWidth = wide ? 224.0 : 172.0;
        final shelfHeight = wide ? 252.0 : 220.0;
        return Padding(
          padding: EdgeInsets.only(bottom: expanded ? 10 : 2),
          child: Column(
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(topic.icon, size: 19, color: AppColors.skyBlueDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topic.label,
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: wide ? 16 : 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${topic.itemCount}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 5),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.ink,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: topic.itemCount == 0
                            ? Container(
                                height: 40,
                                width: double.infinity,
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  '이 주제의 조합을 모으고 있어요.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : SizedBox(
                                key: Key('discovery-horizontal-${topic.label}'),
                                height: shelfHeight,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.only(right: 18),
                                  itemCount:
                                      topic.itemCount +
                                      ((topic.collectionType != null ||
                                              topic.decisiveBattleCollection !=
                                                  null)
                                          ? 1
                                          : 0),
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 11),
                                  itemBuilder: (context, index) {
                                    if (index == topic.itemCount) {
                                      return _DiscoveryMoreCard(
                                        width: cardWidth,
                                        color: topic.color,
                                        count: topic.itemCount,
                                        onTap: () {
                                          if (topic.collectionType != null) {
                                            onOpenCollection(
                                              topic.collectionType!,
                                            );
                                          } else {
                                            onOpenBattleCollection(
                                              topic.decisiveBattleCollection!,
                                            );
                                          }
                                        },
                                      );
                                    }
                                    if (topic.battles.isNotEmpty) {
                                      return _DiscoveryBattleCard(
                                        width: cardWidth,
                                        item: topic.battles[index],
                                        onTap: () => onOpenBattleCollection(
                                          topic.decisiveBattleCollection!,
                                        ),
                                      );
                                    }
                                    final post = topic.posts[index];
                                    return _DiscoveryPhotoCard(
                                      key: Key('discovery-card-${post.id}'),
                                      width: cardWidth,
                                      post: post,
                                      color: topic.color,
                                      onTap: () => onOpenPost(post),
                                    );
                                  },
                                ),
                              ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscoveryBattleCard extends StatelessWidget {
  const _DiscoveryBattleCard({
    required this.width,
    required this.item,
    required this.onTap,
  });

  final double width;
  final _BattleDiscoveryItem item;
  final VoidCallback onTap;

  Widget _image(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const ColoredBox(
        color: AppColors.surfaceMuted,
        child: Center(
          child: Icon(Icons.image_outlined, color: AppColors.muted),
        ),
      );
    }
    return Image.network(
      _displayImageUrl(source),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: AppColors.surfaceMuted,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  children: [
                    Expanded(child: _image(item.leftImageUrl)),
                    const SizedBox(width: 3),
                    Expanded(child: _image(item.rightImageUrl)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.match.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${item.match.leftVotes} : ${item.match.rightVotes}',
              style: const TextStyle(
                color: AppColors.skyBlueDeep,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryPhotoCard extends StatelessWidget {
  const _DiscoveryPhotoCard({
    super.key,
    required this.width,
    required this.post,
    required this.color,
    required this.onTap,
  });

  final double width;
  final PostFeatureInfo post;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final source = post.imageUrl?.trim() ?? '';
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    source.isEmpty
                        ? GradientPhoto(title: post.title)
                        : Image.network(
                            _displayImageUrl(source),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                GradientPhoto(title: post.title),
                          ),
                    Positioned(
                      left: 9,
                      top: 9,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(232),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(topicIcon(post), size: 11, color: color),
                            const SizedBox(width: 3),
                            Text(
                              '하트 ${post.likes}',
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
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
            const SizedBox(height: 9),
            Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.28,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '후기 ${post.reviewCount}  ·  댓글 ${post.commentCount}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData topicIcon(PostFeatureInfo post) => post.recentLikeCount > 0
      ? Icons.trending_up_rounded
      : Icons.favorite_rounded;
}

class _DiscoveryMoreCard extends StatelessWidget {
  const _DiscoveryMoreCard({
    required this.width,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final double width;
  final Color color;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withAlpha(18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(75)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_forward_rounded, color: color, size: 28),
              const SizedBox(height: 9),
              Text(
                '$count개 전체 보기',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LegacyDiscoveryAccordion extends StatefulWidget {
  const _LegacyDiscoveryAccordion({
    required this.topics,
    required this.onOpenPost,
    required this.onOpenCollection,
  });

  final List<_DiscoveryTopic> topics;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;

  @override
  State<_LegacyDiscoveryAccordion> createState() =>
      _LegacyDiscoveryAccordionState();
}

class _LegacyDiscoveryAccordionState extends State<_LegacyDiscoveryAccordion> {
  final Set<int> _expanded = <int>{0};

  @override
  Widget build(BuildContext context) {
    if (widget.topics.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('discovery-topic-accordion'),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0x33FFFFFF)),
        ),
      ),
      child: Column(
        children: widget.topics.indexed.map((entry) {
          final index = entry.$1;
          final topic = entry.$2;
          final expanded = _expanded.contains(index);
          return _LegacyDiscoveryTopicSection(
            key: Key('discovery-topic-$index'),
            topic: topic,
            index: index,
            expanded: expanded,
            onToggle: () => setState(() {
              if (expanded) {
                _expanded.remove(index);
              } else {
                _expanded.add(index);
              }
            }),
            onOpenPost: widget.onOpenPost,
            onOpenCollection: widget.onOpenCollection,
          );
        }).toList(),
      ),
    );
  }
}

class _LegacyDiscoveryTopicSection extends StatelessWidget {
  const _LegacyDiscoveryTopicSection({
    super.key,
    required this.topic,
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.onOpenPost,
    required this.onOpenCollection,
  });

  final _DiscoveryTopic topic;
  final int index;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<PostFeatureInfo> onOpenPost;
  final ValueChanged<HighlightCollectionType> onOpenCollection;

  @override
  Widget build(BuildContext context) {
    final visiblePosts = topic.posts.take(3).toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: expanded ? topic.color.withAlpha(14) : Colors.transparent,
        border: index == 0
            ? null
            : const Border(top: BorderSide(color: Color(0x2AFFFFFF))),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: topic.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(topic.icon, color: topic.color, size: 19),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topic.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${topic.posts.length}개',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 240),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(30, 0, 0, 12),
                    child: Column(
                      children: [
                        const Divider(height: 1, color: Color(0x2AFFFFFF)),
                        const SizedBox(height: 5),
                        if (visiblePosts.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '아직 이 주제의 게시글을 모으는 중이에요.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        else
                          ...visiblePosts.indexed.map(
                            (entry) => _LegacyDiscoveryPostLine(
                              rank: entry.$1 + 1,
                              post: entry.$2,
                              color: topic.color,
                              compact: true,
                              onTap: () => onOpenPost(entry.$2),
                            ),
                          ),
                        if (topic.collectionType != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  onOpenCollection(topic.collectionType!),
                              style: TextButton.styleFrom(
                                foregroundColor: topic.color,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              label: Text(
                                '${topic.posts.length}개 전체 보기',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _LegacyDiscoveryPostLine extends StatelessWidget {
  const _LegacyDiscoveryPostLine({
    required this.rank,
    required this.post,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  final int rank;
  final PostFeatureInfo post;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 39 : 0),
        padding: EdgeInsets.fromLTRB(compact ? 2 : 13, 7, 8, 7),
        child: compact
            ? Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '♥ ${post.likes}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$rank'.padLeft(2, '0'),
                    style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '하트 ${post.likes}  ·  후기 ${post.reviewCount}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
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
    required this.onSearch,
    required this.onToggleTag,
    required this.onShuffle,
    required this.onScanBarcode,
    required this.pickedAuthorsOnly,
    required this.hasPickedAuthors,
    required this.onTogglePickedAuthors,
  });

  final TextEditingController searchController;
  final List<String> titleSuggestions;
  final TextEditingController minFilterController;
  final TextEditingController maxFilterController;
  final Set<String> selectedTags;
  final Future<void> Function() onSearch;
  final Future<void> Function(String tag) onToggleTag;
  final VoidCallback onShuffle;
  final Future<void> Function() onScanBarcode;
  final bool pickedAuthorsOnly;
  final bool hasPickedAuthors;
  final Future<void> Function() onTogglePickedAuthors;

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  bool _categoriesVisible = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.searchController,
                decoration: inputDecoration('조합이나 상품 검색').copyWith(
                  prefixIcon: const Icon(Icons.search_rounded, size: 21),
                  filled: true,
                  fillColor: AppColors.sky,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => widget.onSearch(),
              ),
            ),
            IconButton(
              onPressed: widget.onScanBarcode,
              tooltip: '바코드 스캔',
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
            ),
            IconButton(
              onPressed: widget.onSearch,
              tooltip: '검색',
              icon: const Icon(Icons.arrow_forward_rounded, size: 22),
            ),
          ],
        ),
        if (widget.searchController.text.trim().isNotEmpty)
          _LiveTitleSuggestions(
            suggestions: _matchingTitleSuggestions(
              widget.titleSuggestions,
              widget.searchController.text,
            ),
            onSelected: (title) {
              widget.searchController.text = title;
              setState(() {});
              unawaited(widget.onSearch());
            },
          ),
        Row(
          children: [
            TextButton.icon(
              key: const Key('preference-filter-toggle'),
              onPressed: () =>
                  setState(() => _categoriesVisible = !_categoriesVisible),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                minimumSize: const Size(44, 48),
                padding: const EdgeInsets.only(right: 12),
              ),
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: Text(
                widget.selectedTags.isEmpty
                    ? '취향 필터'
                    : '취향 필터 ${widget.selectedTags.length}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              _categoriesVisible ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: AppColors.muted,
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              key: const Key('picked-author-filter'),
              onPressed: widget.hasPickedAuthors
                  ? widget.onTogglePickedAuthors
                  : widget.onTogglePickedAuthors,
              style: TextButton.styleFrom(
                foregroundColor: widget.pickedAuthorsOnly
                    ? AppColors.skyBlueDeep
                    : AppColors.muted,
                backgroundColor: widget.pickedAuthorsOnly
                    ? AppColors.sky
                    : Colors.transparent,
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: Icon(
                widget.pickedAuthorsOnly
                    ? Icons.person_rounded
                    : Icons.person_outline_rounded,
                size: 18,
              ),
              label: const Text(
                '픽한 사람',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: widget.onShuffle,
              tooltip: '섞기',
              icon: const Icon(Icons.shuffle_rounded, size: 20),
            ),
          ],
        ),
        if (_categoriesVisible)
          Padding(
            key: const Key('preference-filter-options'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: ['전체', ..._suggestedSearchCategories].map((
                    category,
                  ) {
                    final isAll = category == '전체';
                    final selected = isAll
                        ? widget.selectedTags.isEmpty
                        : widget.selectedTags.contains(category);
                    return Semantics(
                      selected: selected,
                      child: TextButton(
                        onPressed: () => unawaited(
                          widget.onToggleTag(isAll ? '' : category),
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(70, 46),
                          foregroundColor: selected
                              ? AppColors.limeDeep
                              : AppColors.muted,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected) ...[
                              const Icon(Icons.check_rounded, size: 17),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              category,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      '가격',
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: widget.minFilterController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '최소',
                          suffixText: '원',
                          filled: false,
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                        ),
                        onSubmitted: (_) => widget.onSearch(),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('~'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: widget.maxFilterController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '최대',
                          suffixText: '원',
                          filled: false,
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.line),
                          ),
                        ),
                        onSubmitted: (_) => widget.onSearch(),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onSearch,
                      child: const Text('적용'),
                    ),
                  ],
                ),
              ],
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
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      borderSide: const BorderSide(color: AppColors.skyBlueDeep, width: 1.5),
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

class _HighlightStoreFilter extends StatelessWidget {
  const _HighlightStoreFilter({
    required this.selectedStore,
    required this.onChanged,
  });

  final String? selectedStore;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final stores = <String?>[null, ..._highlightStores];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stores.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final store = stores[index];
          final selected = selectedStore == store;
          final color = store == null
              ? AppColors.skyBlueDeep
              : _storeColor(store);
          final label = store == null ? '전체' : _storeDisplayName(store);
          return InkWell(
            onTap: () => onChanged(store),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: selected
                    ? (store == null ? AppColors.lime : color)
                    : color.withAlpha(18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected && store == null
                      ? AppColors.lime
                      : selected
                      ? color
                      : color.withAlpha(105),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? (store == null ? AppColors.ink : Colors.white)
                      : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
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
  String? _selectedStore;

  List<Post> get _sortedPosts {
    final sorted = widget.posts
        .where(
          (post) =>
              _selectedStore == null ||
              _postMatchesStore(post, _selectedStore!),
        )
        .toList();
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 360 ? 2 : 1;
          final compactCards = constraints.maxWidth < 620;
          final rowCount = (posts.length / columns).ceil();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: rowCount + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightStoreFilter(
                        selectedStore: _selectedStore,
                        onChanged: (store) =>
                            setState(() => _selectedStore = store),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedStore == null
                                  ? '${posts.length}개 조합'
                                  : '${_storeDisplayName(_selectedStore!)} ${posts.length}개 조합',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SortSelector(
                            sortMode: _sortMode,
                            onChanged: (value) =>
                                setState(() => _sortMode = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              final rowIndex = index - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: 12),
                      Expanded(
                        child: () {
                          final postIndex = rowIndex * columns + column;
                          if (postIndex >= posts.length) {
                            return const SizedBox.shrink();
                          }
                          final post = posts[postIndex];
                          return PostCard(
                            post: post,
                            isMine: post.authorId == widget.currentUser.id,
                            isSaved: widget.currentUser.savedPostIds.contains(
                              post.id,
                            ),
                            compact: compactCards,
                            onToggleLike: () => widget.onToggleLike(post),
                            onToggleDislike: () => widget.onToggleDislike(post),
                            onToggleSave: () => widget.onToggleSave(post.id),
                            onEdit: () => widget.onEditPost(post),
                            onDelete: () => widget.onDeletePost(post),
                            onOpenAuthor: () => widget.onOpenAuthor(post),
                            onOpenPost: () => widget.onOpenPost(post),
                          );
                        }(),
                      ),
                    ],
                  ],
                ),
              );
            },
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
    this.compact = false,
  });

  final Post post;
  final bool isMine;
  final bool isSaved;
  final bool compact;
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
      maxVisible: compact ? 1 : 2,
    );
    final cardHeight = compact ? 284.0 : 448.0;
    final cardPadding = compact ? 5.0 : 8.0;
    final avatarRadius = compact ? 10.0 : 14.0;
    final imageHeight = compact ? 112.0 : 230.0;
    final titleHeight = compact ? 24.0 : 32.0;
    final titleFontSize = compact ? 10.4 : 13.6;
    final tagHeight = compact ? 18.0 : 20.0;
    return SizedBox(
      height: cardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.receipt,
          borderRadius: BorderRadius.circular(AppColors.radiusMedium),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withAlpha(10),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onOpenAuthor,
                  child: _UserAvatar(
                    imageSource: post.authorProfileImageUrl,
                    radius: avatarRadius,
                  ),
                ),
                SizedBox(width: compact ? 5 : 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: onOpenAuthor,
                        child: Text(
                          post.authorNickname,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 10.2 : 12.4,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.transparent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        post.createdAtLabel,
                        style: TextStyle(
                          color: Color(0xFF8CA0B3),
                          fontSize: compact ? 8.2 : 9.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMine)
                  PopupMenuButton<String>(
                    iconSize: compact ? 20 : 24,
                    padding: EdgeInsets.zero,
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
            SizedBox(height: compact ? 2 : 6),
            InkWell(
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
              onTap: onOpenPost,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (displayCategories.isNotEmpty) ...[
                    SizedBox(
                      height: tagHeight,
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
                    SizedBox(height: compact ? 2 : 5),
                  ],
                  SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusSmall,
                      ),
                      child: _PostImageGallery(post: post),
                    ),
                  ),
                  CuProductBadgeStrip(
                    text: post.title,
                    contextText: '${post.title} ${post.content}',
                    compact: true,
                    topPadding: compact ? 4 : 6,
                  ),
                  SizedBox(height: compact ? 3 : 6),
                  SizedBox(
                    height: titleHeight,
                    child: ConvenienceProductTitle(
                      title: post.title,
                      contextText: '${post.title} ${post.content}',
                      maxLines: 1,
                      labelTopPadding: 0,
                      showLabels: false,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 5 : 8,
                          vertical: compact ? 1 : 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.limeSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          post.priceLabel,
                          style: TextStyle(
                            color: AppColors.limeDeep,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 9 : 11.2,
                          ),
                        ),
                      ),
                      if (post.calories != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${post.calories}kcal',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: compact ? 8.6 : 10.2,
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
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ActionChipButton(
                    label: '${post.likedByMe ? '♥' : '♡'} ${post.likes}',
                    active: post.likedByMe,
                    compact: compact,
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
                    compact: compact,
                    onTap: onToggleDislike,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ActionChipButton(
                    label: isSaved ? '보관됨' : '보관',
                    active: isSaved,
                    activeColor: const Color(0xFFE2F3FC),
                    activeTextColor: const Color(0xFF176EAA),
                    compact: compact,
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
        color: AppColors.surfaceMuted,
        alignment: Alignment.center,
        child: const Icon(
          Icons.restaurant_rounded,
          color: AppColors.skyBlueDeep,
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
          child: Icon(icon, color: AppColors.skyBlueDeep),
        ),
      ),
    );
  }
}

List<Widget> _buildPostImages(Post post) {
  final widgets = <Widget>[];
  for (final imageData in post.allImageDatas) {
    try {
      widgets.add(
        Image.memory(
          base64Decode(imageData.split(',').last),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _ImageErrorPlaceholder(),
        ),
      );
    } on FormatException {
      widgets.add(const _ImageErrorPlaceholder());
    }
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
              const ColoredBox(color: Color(0xFFF2F5F8)),
              const Center(
                child: CircularProgressIndicator(color: AppColors.skyBlueDeep),
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
    this.compact = false,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color? activeColor;
  final Color? activeTextColor;
  final bool expanded;
  final bool compact;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () async {
          try {
            await onTap();
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(content: Text('요청을 처리하지 못했어요. 다시 시도해 주세요.')),
              );
          }
        },
        child: Ink(
          width: expanded ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 6,
            vertical: compact ? 3 : 5,
          ),
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
              fontSize: compact ? 10 : 11,
            ),
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
  late final TextEditingController productController;
  late final TextEditingController contentController;
  late final TextEditingController priceController;
  late final TextEditingController calorieController;
  late final TextEditingController eatingStepsController;
  double rating = 3;

  final List<Uint8List> selectedImageBytes = <Uint8List>[];
  final List<String> selectedImageUrls = <String>[];
  List<String> productNameIndex = const <String>[];
  bool submitting = false;
  String? error;

  bool get isEditing => widget.initialPost != null;

  @override
  void initState() {
    super.initState();
    final post = widget.initialPost;
    titleController = TextEditingController(text: post?.title ?? '');
    productController = TextEditingController(
      text: post == null
          ? ''
          : (post.details.usedProducts.isNotEmpty
                ? post.details.usedProducts.join(' + ')
                : post.title),
    );
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
        productNameIndex = index
            .expand(
              (post) => post.usedProducts.isEmpty
                  ? <String>[post.title]
                  : post.usedProducts,
            )
            .toSet()
            .toList();
      });
    } catch (_) {
      // Suggestions are optional; posting remains available if the index fails.
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    productController.dispose();
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
        final currentTitle = productController.text.trim();
        if (nextTitle.isEmpty) {
          error = null;
          return;
        }
        if (currentTitle.isEmpty) {
          productController.text = nextTitle;
        } else {
          final normalizedParts = currentTitle
              .split('+')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
          if (!normalizedParts.contains(nextTitle)) {
            productController.text = '$currentTitle + $nextTitle';
          }
        }
        productController.selection = TextSelection.collapsed(
          offset: productController.text.length,
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
          content: Text('아직 등록되지 않은 상품이거나 조회가 잠시 실패했어요. 사용한 상품을 직접 적어 주세요.'),
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
    final customTitle = titleController.text.trim();
    final usedProducts = productController.text
        .split('+')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final title = customTitle.isEmpty ? usedProducts.join(' + ') : customTitle;
    final content = contentController.text.trim();
    final singlePrice = int.tryParse(priceController.text.trim());
    final calories = int.tryParse(calorieController.text.trim());
    final details = PostDetails(
      usedProducts: usedProducts,
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
    if (usedProducts.isEmpty) {
      setState(() => error = '사용한 상품은 하나 이상 입력해 주세요.');
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
      title: title,
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
                            isEditing ? '게시글 수정' : '게시글 올리기',
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
                                : '조합 사진과 제목, 사용한 상품을 남겨보세요.',
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
                InkWell(
                  onTap: pickImage,
                  borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                  child: Container(
                    height: 240,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusMedium,
                      ),
                      border: Border.all(color: AppColors.line),
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
                              '사진을 추가해주세요',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF9DB0C0),
                                fontWeight: FontWeight.w700,
                                height: 1.6,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
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
                  decoration: inputDecoration('제목 (선택): 초가성비 조합'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: productController,
                  onChanged: (_) => setState(() {}),
                  decoration: inputDecoration('사용한 상품: 불닭볶음면 + 스트링치즈').copyWith(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton.icon(
                        onPressed: scanProductCode,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.skyBlueDeep,
                          backgroundColor: AppColors.sky,
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
                if (productController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _LiveTitleSuggestions(
                    suggestions: _matchingTitleSuggestions(
                      productNameIndex,
                      productController.text.split('+').last,
                    ),
                    onSelected: (title) {
                      final nextTitle = _applyTitleSuggestion(
                        productController.text,
                        title,
                      );
                      setState(() => productController.text = nextTitle);
                      productController.selection = TextSelection.collapsed(
                        offset: nextTitle.length,
                      );
                    },
                  ),
                ],
                if (productController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConvenienceProductTitle(
                    title: productController.text,
                    contextText:
                        '${productController.text} ${titleController.text} ${contentController.text}',
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
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      submitting
                          ? (isEditing ? '수정 중...' : '게시 중...')
                          : (isEditing ? '수정 완료' : '올리기'),
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
    return Column(
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
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9AA9B3)),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFDDE5E9)),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFDDE5E9)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.skyBlueDeep, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostRatingPicker extends StatelessWidget {
  const _PostRatingPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '평점',
          style: TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            ...List.generate(5, (index) {
              final score = index + 1;
              return IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.only(right: 6),
                onPressed: () => onChanged(score),
                icon: Icon(
                  score <= value
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: const Color(0xFFF4B942),
                  size: 30,
                ),
              );
            }),
            const SizedBox(width: 6),
            Text(
              '$value.0',
              style: const TextStyle(
                color: Color(0xFF788B98),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const Divider(height: 1, color: Color(0xFFE4EAED)),
      ],
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
    late final BotTurnResult result;
    try {
      result = await widget.onSend(value, _useAgeCalorieGuide, _currentBudget);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      return;
    }
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
    try {
      await widget.onMore(_useAgeCalorieGuide, _currentBudget);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      return;
    }
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
                  color: AppColors.skyBlueDeep,
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
                      foregroundColor: AppColors.skyBlueDeep,
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
                          foregroundColor: AppColors.ink,
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
                                  color: AppColors.ink,
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
                                ? AppColors.limeSoft
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
                                    ? AppColors.limeDeep
                                    : AppColors.muted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _useAgeCalorieGuide ? '권장 칼로리 반영' : '권장 칼로리 제외',
                                style: TextStyle(
                                  color: _useAgeCalorieGuide
                                      ? AppColors.limeDeep
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
    const desktopTextScale = TextScaler.linear(1.18);
    final range = MealCalorieRange.forAge(
      int.tryParse(_ageController.text.trim()) ?? 0,
    );
    final basicSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _setupSectionTitle('나이는? (만)'),
        const SizedBox(height: 10),
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          decoration: inputDecoration('예: 20'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
        ),
        if (range != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${range.ageLabel} 한 끼 참고 범위 · ${range.label}',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _setupSectionTitle('성별은?'),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: '여자',
              label: SizedBox(
                width: 68,
                child: Center(child: Text('여자', maxLines: 1)),
              ),
            ),
            ButtonSegment(
              value: '남자',
              label: SizedBox(
                width: 68,
                child: Center(child: Text('남자', maxLines: 1)),
              ),
            ),
          ],
          selected: {_gender},
          onSelectionChanged: (values) =>
              setState(() => _gender = values.first),
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _setupSectionTitle('추천에서 중요한 기준은?'),
        const SizedBox(height: 8),
        const Text(
          '두 개를 고르면 선택한 순서대로 1·2순위가 됩니다.',
          style: TextStyle(
            color: Color(0xFF7C90A2),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        _PriorityChoiceWrap(
          labels: const ['저칼로리', '가성비', '시간절약', '호불호', '트렌드'],
          selected: _priorityValues,
          onChanged: () => setState(() {}),
        ),
      ],
    );

    final tasteSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _setupSectionTitle('가장 좋아하는 맛은?'),
        const SizedBox(height: 8),
        const Text(
          '각 맛을 얼마나 좋아하는지 1~5로 표시해 주세요.',
          style: TextStyle(
            color: Color(0xFF7C90A2),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        _TasteRatingEditor(
          ratings: _tasteRatings,
          onChanged: (taste, value) =>
              setState(() => _tasteRatings[taste] = value),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final outerPadding = EdgeInsets.fromLTRB(
          desktop ? 44 : 18,
          desktop ? 36 : 18,
          desktop ? 44 : 18,
          desktop ? 40 : 28,
        );

        return SingleChildScrollView(
          padding: outerPadding,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: desktop ? desktopTextScale : TextScaler.noScaling,
            ),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: desktop ? 520 : 0),
              padding: EdgeInsets.symmetric(
                horizontal: desktop ? 36 : 6,
                vertical: desktop ? 28 : 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '1분 취향 설정',
                      style: TextStyle(
                        color: Color(0xFF6A7D8B),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '내 입맛 알려주기',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: desktop ? 38 : 24,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '평소 좋아하는 맛과 중요한 기준을 알려줘. 대화할수록 더 잘 맞춰갈게.',
                    style: TextStyle(
                      color: Color(0xFF73889B),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: desktop ? 42 : 22),
                  const Divider(height: 1, color: Color(0xFFE7ECEF)),
                  SizedBox(height: desktop ? 34 : 24),
                  if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: basicSection),
                        const SizedBox(width: 54),
                        Expanded(child: tasteSection),
                      ],
                    )
                  else ...[
                    basicSection,
                    const SizedBox(height: 24),
                    tasteSection,
                  ],
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
                  SizedBox(height: desktop ? 36 : 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.lime,
                        foregroundColor: AppColors.ink,
                        padding: EdgeInsets.symmetric(
                          vertical: desktop ? 22 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        _saving ? '저장 중...' : '편봇 시작하기',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _setupSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.currentUser,
    required this.repository,
    required this.posts,
    required this.onUserChanged,
    required this.onResetBotSetup,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.onOpenPost,
    required this.onOpenAuthor,
    required this.onToggleProfilePublic,
  });

  final PyeonUser currentUser;
  final PostRepository repository;
  final List<Post> posts;
  final Future<void> Function(PyeonUser user) onUserChanged;
  final Future<void> Function() onResetBotSetup;
  final Future<void> Function() onLogout;
  final Future<void> Function(String password) onDeleteAccount;
  final Future<void> Function(Post post) onOpenPost;
  final ValueChanged<Post> onOpenAuthor;
  final Future<void> Function(bool value) onToggleProfilePublic;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  _ProfileViewMode _mode = _ProfileViewMode.overview;
  SortMode _postSortMode = SortMode.latest;
  final ImagePicker _picker = ImagePicker();
  bool _deletingAccount = false;
  BattleResultsPage _battleResults = const BattleResultsPage();
  Timer? _resultTimer;
  bool _loadingResults = true;
  bool _fetchingResults = false;
  bool _resultError = false;
  bool _markingResultsRead = false;
  int _resultGeneration = 0;
  final Set<String> _confirmedReadIds = {};

  int get _unreadResultCount => _battleResults.results
      .where(
        (result) => result.unread && !_confirmedReadIds.contains(result.id),
      )
      .length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadBattleResults());
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id ||
        oldWidget.repository != widget.repository) {
      _resultGeneration++;
      _resultTimer?.cancel();
      _battleResults = const BattleResultsPage();
      _confirmedReadIds.clear();
      _fetchingResults = false;
      _markingResultsRead = false;
      _loadingResults = true;
      _resultError = false;
      _mode = _ProfileViewMode.overview;
      unawaited(_loadBattleResults());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadBattleResults());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resultTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBattleResults() async {
    if (_fetchingResults) return;
    final generation = _resultGeneration;
    _fetchingResults = true;
    _resultTimer?.cancel();
    var delay = const Duration(seconds: 15);
    try {
      final results = await widget.repository.fetchBattleResults(
        widget.currentUser.id,
      );
      if (!mounted || generation != _resultGeneration) return;
      delay = results.refreshAfter;
      setState(() {
        _battleResults = results;
        _loadingResults = false;
        _resultError = false;
      });
      if (_mode == _ProfileViewMode.battleResults) {
        unawaited(_markResultsRead());
      }
    } catch (_) {
      if (!mounted || generation != _resultGeneration) return;
      setState(() {
        _loadingResults = false;
        _resultError = true;
      });
    } finally {
      if (mounted && generation == _resultGeneration) {
        _fetchingResults = false;
        _resultTimer = Timer(delay, _loadBattleResults);
      }
    }
  }

  Future<void> _markResultsRead() async {
    if (_markingResultsRead) return;
    final ids = _battleResults.results
        .where(
          (result) => result.unread && !_confirmedReadIds.contains(result.id),
        )
        .map((result) => result.id)
        .toList();
    if (ids.isEmpty) return;
    final generation = _resultGeneration;
    _markingResultsRead = true;
    try {
      final readIds = await widget.repository.markBattleResultsRead(
        widget.currentUser.id,
        ids,
      );
      if (!mounted || generation != _resultGeneration) return;
      setState(() => _confirmedReadIds.addAll(readIds));
    } catch (_) {
      // Keep the badge until the server confirms receipt; the next refresh retries.
    } finally {
      if (mounted && generation == _resultGeneration) {
        _markingResultsRead = false;
      }
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

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('계정을 삭제할까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '내 게시글과 댓글, 후기, 투표 기록이 함께 정리되며 되돌릴 수 없어요.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: inputDecoration('확인을 위해 비밀번호 입력'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(passwordController.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84B4B),
              foregroundColor: Colors.white,
            ),
            child: const Text('계정 영구 삭제'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await widget.onDeleteAccount(password);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      final message = error is StateError
          ? error.message.toString()
          : '계정을 삭제하지 못했어요.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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
    final user = widget.currentUser;
    final setup = user.botSetup;
    final liked = _sortPosts(
      widget.posts
          .where((post) => user.likedPostIds.contains(post.id))
          .toList(),
    );
    final saved = _sortPosts(
      widget.posts
          .where((post) => user.savedPostIds.contains(post.id))
          .toList(),
    );
    final disliked = _sortPosts(
      widget.posts
          .where((post) => user.dislikedPostIds.contains(post.id))
          .toList(),
    );
    final mine = _sortPosts(
      widget.posts.where((post) => post.authorId == user.id).toList(),
    );
    final authors = <String, Post>{
      for (final post in widget.posts)
        if (user.pickedAuthorIds.contains(post.authorId)) post.authorId: post,
    }.values.toList();
    final averages = _likedTasteAverages(liked);
    final tabs = [
      (_ProfileViewMode.overview, '설정'),
      (_ProfileViewMode.myPosts, '내 글 ${mine.length}'),
      (
        _ProfileViewMode.battleResults,
        _unreadResultCount == 0 ? '픽 쇼츠' : '픽 쇼츠 · 새 결과 $_unreadResultCount',
      ),
      (_ProfileViewMode.likes, '하트 ${liked.length}'),
      (_ProfileViewMode.saved, '보관 ${saved.length}'),
      (_ProfileViewMode.dislikes, '싫어요 ${disliked.length}'),
      (_ProfileViewMode.picks, '픽 ${authors.length}'),
    ];
    final selectedPosts = switch (_mode) {
      _ProfileViewMode.likes => liked,
      _ProfileViewMode.saved => saved,
      _ProfileViewMode.dislikes => disliked,
      _ProfileViewMode.myPosts => mine,
      _ => <Post>[],
    };
    return ListView(
      key: const Key('profile-page'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: '프로필 사진 변경',
              child: InkWell(
                onTap: _changeProfileImage,
                customBorder: const CircleBorder(),
                child: _UserAvatar(
                  imageSource: user.profileImageUrl,
                  radius: 32,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.nickname,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '픽 ${user.pickedAuthorIds.length}  ·  받은 픽 ${user.pickedByCount}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _changeProfileImage,
              tooltip: '프로필 사진 변경',
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: tabs
                .map(
                  (tab) => _ProfileModeChip(
                    label: tab.$2,
                    active: _mode == tab.$1,
                    onTap: () {
                      setState(() => _mode = tab.$1);
                      if (_mode == _ProfileViewMode.battleResults) {
                        unawaited(_markResultsRead());
                        unawaited(_loadBattleResults());
                      }
                    },
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        const SizedBox(height: 20),
        if (_mode == _ProfileViewMode.overview) ...[
          if (setup != null) ...[
            const Text(
              '나의 취향',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              setup.priorityValues.join(' · '),
              style: const TextStyle(color: AppColors.muted, height: 1.6),
            ),
            const SizedBox(height: 6),
            Text(
              setup.tasteRatings.entries
                  .map((entry) => '${entry.key} ${entry.value}')
                  .join('   '),
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            if (averages != null) ...[
              const SizedBox(height: 8),
              Text(
                '하트한 맛  ${averages.entries.map((entry) => '${entry.key} ${entry.value.toStringAsFixed(1)}').join(' · ')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_rounded, size: 21),
            title: const Text('편봇 취향 설정', style: TextStyle(fontSize: 15)),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: widget.onResetBotSetup,
          ),
          const Divider(height: 24, color: AppColors.line),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('프로필 공개 설정', style: TextStyle(fontSize: 15)),
              leading: const Icon(Icons.visibility_outlined, size: 21),
              children: [
                _VisibilitySwitchRow(
                  label: '프로필 공개',
                  value: user.profilePublic,
                  onChanged: widget.onToggleProfilePublic,
                ),
                _VisibilitySwitchRow(
                  label: '아이디',
                  value: user.profileVisibility.username,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        username: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '하트',
                  value: user.profileVisibility.likes,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        likes: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '싫어요',
                  value: user.profileVisibility.dislikes,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        dislikes: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '보관',
                  value: user.profileVisibility.saved,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        saved: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '내 글',
                  value: user.profileVisibility.myPosts,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        myPosts: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '픽한 작성자',
                  value: user.profileVisibility.picks,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        picks: v,
                      ),
                    ),
                  ),
                ),
                _VisibilitySwitchRow(
                  label: '받은 픽',
                  value: user.profileVisibility.pickedBy,
                  onChanged: (v) => widget.onUserChanged(
                    user.copyWith(
                      profileVisibility: user.profileVisibility.copyWith(
                        pickedBy: v,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shuffle_rounded, size: 21),
            title: const Text('무작위 추천', style: TextStyle(fontSize: 15)),
            onTap: _openRandomPost,
          ),
          const Divider(height: 24, color: AppColors.line),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('로그아웃', style: TextStyle(fontSize: 15)),
            onTap: widget.onLogout,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _deletingAccount ? '계정 삭제 중...' : '계정 삭제',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            onTap: _deletingAccount ? null : _deleteAccount,
          ),
        ] else if (_mode == _ProfileViewMode.battleResults) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  '내 픽 쇼츠 결과',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '결과 새로고침',
                onPressed: _fetchingResults ? null : _loadBattleResults,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          if (_loadingResults)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_resultError)
              const Text(
                '결과를 불러오지 못했어요. 새로고침해 주세요.',
                style: TextStyle(color: AppColors.muted),
              ),
            if (!_resultError && _battleResults.results.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '내가 올린 픽 쇼츠가 종료되면 여기에 결과가 표시돼요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ..._battleResults.results.map(
              (result) => _ProfileBattleResult(result: result),
            ),
          ],
        ] else if (_mode == _ProfileViewMode.picks) ...[
          if (authors.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '아직 픽한 작성자가 없어요.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ...authors.map(
            (post) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _UserAvatar(
                imageSource: post.authorProfileImageUrl,
                radius: 21,
              ),
              title: Text(post.authorNickname),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => widget.onOpenAuthor(post),
            ),
          ),
        ] else ...[
          Align(
            alignment: Alignment.centerRight,
            child: SortSelector(
              sortMode: _postSortMode,
              compact: true,
              onChanged: (mode) => setState(() => _postSortMode = mode),
            ),
          ),
          const SizedBox(height: 12),
          if (selectedPosts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '아직 게시글이 없어요.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ...selectedPosts.map(
            (post) => _CompactPostTile(
              post: post,
              onTap: () => widget.onOpenPost(post),
            ),
          ),
        ],
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
  battleResults,
}

class _ProfileBattleResult extends StatelessWidget {
  const _ProfileBattleResult({required this.result});

  final BattleResultEntry result;

  @override
  Widget build(BuildContext context) {
    Widget score(String title, int votes) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$votes표',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Column(
      key: ValueKey('battle-result-${result.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          result.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '${DateFormat('M.d HH:mm').format(result.endsAt)} 종료',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        Text(
          result.outcome,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        score(result.leftTitle, result.leftVotes),
        score(result.rightTitle, result.rightVotes),
        const SizedBox(height: 20),
        const Divider(height: 1, color: AppColors.line),
      ],
    );
  }
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
    return Semantics(
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.limeSoft : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.limeDeep : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.limeDeep : AppColors.muted,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
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
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      ),
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppColors.lime,
      activeThumbColor: AppColors.limeDeep,
      inactiveTrackColor: const Color(0xFFEAECEE),
      inactiveThumbColor: Colors.white,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
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

class _AuthorProfileSection extends StatelessWidget {
  const _AuthorProfileSection({
    required this.title,
    required this.subtitle,
    required this.posts,
    required this.onOpenPost,
  });
  final String title, subtitle;
  final List<Post> posts;
  final Future<void> Function(Post post) onOpenPost;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (posts.isEmpty)
            const Text('공개된 항목이 없어요.', style: TextStyle(color: AppColors.muted))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: posts.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
                childAspectRatio: 0.72,
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
    required this.onToggleLike,
    required this.onToggleDislike,
    required this.onAddComment,
    required this.onToggleSave,
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
  final Future<Post> Function() onToggleLike;
  final Future<Post> Function() onToggleDislike;
  final Future<Post> Function(String text) onAddComment;
  final Future<void> Function() onToggleSave;
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
  PostAudienceStats? _audienceStats;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _saved = widget.isSaved;
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.76,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => PostReviewsScreen(
          scrollController: scrollController,
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
      backgroundColor: Colors.white,
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
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 860 ? 48 : 20,
          14,
          MediaQuery.sizeOf(context).width >= 860 ? 48 : 20,
          40,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Container(
                color: Colors.white,
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
                      ],
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: GestureDetector(
                        onTap: _openPhotoViewer,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 520),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: _PostImageGallery(post: _post),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConvenienceProductTitle(
                      title: _post.title,
                      contextText: '${_post.title} ${_post.content}',
                      maxLines: 3,
                      showLabels: false,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        height: 1.24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CuProductBadgeStrip(
                      text: _post.title,
                      contextText: '${_post.title} ${_post.content}',
                    ),
                    const SizedBox(height: 12),
                    _PostMetaRow(
                      priceLabel: _post.priceLabel,
                      calories: _post.calories,
                      rating: _post.rating,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _displayCategories(_post.categories)
                          .map((category) => _TagPill(label: '#$category'))
                          .toList(),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Divider(height: 1, color: Color(0xFFE7ECEF)),
                    ),
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
                      displayContent.isEmpty
                          ? '아직 후기가 비어 있어요.'
                          : displayContent,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PostDetailsSection(details: _post.details),
                    if (_post.details.usedProducts.isNotEmpty ||
                        _post.details.eatingSteps.isNotEmpty ||
                        _post.details.tips.isNotEmpty)
                      const SizedBox(height: 20),
                    const Divider(height: 1, color: Color(0xFFE7ECEF)),
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionChipButton(
                            label: _saved ? '보관 중' : '보관함 이동',
                            active: _saved,
                            activeColor: const Color(0xFFE2F3FC),
                            activeTextColor: const Color(0xFF176EAA),
                            expanded: true,
                            onTap: () async {
                              await widget.onToggleSave();
                              if (!mounted) return;
                              setState(() => _saved = !_saved);
                            },
                          ),
                        ),
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
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1, color: Color(0xFFE7ECEF)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _PostLikeAudienceCard(
                likedUsers: _likedUsers,
                audienceStats: _audienceStats,
                reviews: _post.reviews,
              ),
            ),
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
    final hasAny = details.usedProducts.isNotEmpty || eatingTips.isNotEmpty;
    if (!hasAny) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.usedProducts.isNotEmpty)
            _DetailBlock(title: '사용한 상품', items: details.usedProducts),
          if (details.usedProducts.isNotEmpty && eatingTips.isNotEmpty)
            const SizedBox(height: 14),
          if (eatingTips.isNotEmpty)
            _DetailBlock(title: '먹는 법', items: eatingTips),
        ],
      ),
    );
  }
}

class _PostMetaRow extends StatelessWidget {
  const _PostMetaRow({
    required this.priceLabel,
    required this.calories,
    required this.rating,
  });

  final String priceLabel;
  final int? calories;
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFE9EEF1)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PostMetaItem(label: '가격', value: priceLabel),
          ),
          if (calories != null) ...[
            const _PostMetaDivider(),
            Expanded(
              child: _PostMetaItem(label: '칼로리', value: '$calories kcal'),
            ),
          ],
          const _PostMetaDivider(),
          Expanded(
            child: _PostMetaItem(
              label: '평점',
              value: rating <= 0 ? '미입력' : '★ ${rating.toStringAsFixed(1)}',
              valueColor: const Color(0xFFC87812),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMetaItem extends StatelessWidget {
  const _PostMetaItem({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8A9AA7),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PostMetaDivider extends StatelessWidget {
  const _PostMetaDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      width: 18,
      child: VerticalDivider(width: 18, color: Color(0xFFE6EBEE)),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
          const SizedBox(height: 16),
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
              final color = colors[entry.key] ?? AppColors.skyBlueDeep;
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
                        backgroundColor: AppColors.lime,
                        foregroundColor: AppColors.ink,
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
        ...items.indexed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${entry.$1 + 1}'.padLeft(2, '0'),
                    style: const TextStyle(
                      color: Color(0xFF88A2B3),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.$2,
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
                      foregroundColor: AppColors.skyBlueDeep,
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

String _retailBarcodeFromCapture(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final raw = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (const <int>{8, 12, 13, 14}.contains(digits.length)) return digits;
  }
  return '';
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
    cameraResolution: const Size(1280, 720),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 120,
    autoZoom: true,
    formats: const <BarcodeFormat>[
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
      BarcodeFormat.code128,
    ],
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
                                    final value = _retailBarcodeFromCapture(
                                      capture,
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
                                      foregroundColor: AppColors.ink,
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
                            foregroundColor: AppColors.skyBlueDeep,
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
        style: TextStyle(
          color: AppColors.skyBlueDeep,
          fontWeight: FontWeight.w800,
        ),
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
              color: AppColors.skyBlueDeep,
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
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.ink,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '오늘 뭐 먹을까?',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '기분과 예산을 편하게 말해줘. 네 입맛과 좋아요 기록을 보고 실제 게시글에서 골라줄게.',
            style: TextStyle(
              color: Color(0xFF657B8D),
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _BotPromptExample(label: '오천 원으로 든든하게'),
              _BotPromptExample(label: '오늘 너무 피곤해'),
              _BotPromptExample(label: '매콤한 거 추천해줘'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotPromptExample extends StatelessWidget {
  const _BotPromptExample({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF647887),
          fontSize: 11,
          fontWeight: FontWeight.w800,
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
                color: isUser ? AppColors.sky : AppColors.limeSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isUser ? AppColors.skyBlue : AppColors.lime,
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
              const SizedBox(height: 12),
              ...recommended.map(
                (post) => GestureDetector(
                  onTap: () => onOpenPost(post.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(12),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 108,
                          height: 108,
                          child: _BotPostThumbnail(post: post),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  post.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w900,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  post.priceLabel,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  post.categories.take(3).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF80909B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BotPostThumbnail extends StatelessWidget {
  const _BotPostThumbnail({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => const ColoredBox(
      color: Color(0xFFF0F2F3),
      child: Center(
        child: Icon(Icons.fastfood_rounded, color: Color(0xFF9AA7AF)),
      ),
    );

    if (post.allImageDatas.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(post.allImageDatas.first),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        );
      } catch (_) {
        return fallback();
      }
    }
    if (post.allImageUrls.isNotEmpty) {
      return Image.network(
        _displayImageUrl(post.allImageUrls.first),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      );
    }
    return fallback();
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
        border: Border.all(color: const Color(0xFFCBE8F8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.skyBlueDeep,
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
    '달달': AppColors.lime,
    '매콤': AppColors.skyBlue,
    '새콤': AppColors.lime,
    '짭짤': AppColors.skyBlue,
  };

  Color _fillColorFor(String taste) =>
      _tasteFillColors[taste] ?? AppColors.lime;

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
                      color: AppColors.muted,
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
                                  : AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: active ? fillColor : AppColors.line,
                              ),
                            ),
                            child: Text(
                              '$score',
                              style: TextStyle(
                                color: active ? AppColors.ink : AppColors.muted,
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
                        ? AppColors.lime
                        : AppColors.skyBlue
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? rank == 0
                          ? AppColors.lime
                          : AppColors.skyBlue
                    : AppColors.line,
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
              color: active ? AppColors.lime : AppColors.limeSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.limeDeep,
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
