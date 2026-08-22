import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/mock_combination_battle.dart';
import '../models/combination_battle.dart';
import '../models/post.dart';
import '../models/pyeon_user.dart';
import '../models/sort_mode.dart';
import '../repositories/post_repository.dart';
import '../services/battle_state_store.dart';
import '../widgets/cu_product_badges.dart';

const _battleInk = Color(0xFF203447);
const _battleCanvas = Color(0xFFF6F8FC);
const _battleLine = Color(0xFFDCE6F0);
const _battleSubtle = Color(0xFF72869B);

bool _isCombinationTitle(String value) {
  final parts = value
      .replaceAll('＋', '+')
      .split('+')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  return parts.length >= 2;
}

bool _isCombinationPost(Post post) {
  if (post.details.usedProducts.length >= 2) return true;
  return _isCombinationTitle(post.title);
}

String _battleDisplayImageUrl(String imageUrl) {
  final raw = imageUrl.trim();
  if (raw.isEmpty || raw.startsWith('data:')) return raw;
  if (kIsWeb && raw.startsWith(RegExp(r'https?://'))) {
    return '${Uri.base.origin}/api/image-proxy?url=${Uri.encodeComponent(raw)}';
  }
  return raw;
}

enum _BattleCreateSourceMode { community, custom }

enum _BattleEndUnit {
  minutes('분', Icons.timer_rounded),
  hours('시간', Icons.schedule_rounded),
  days('일', Icons.calendar_today_rounded);

  const _BattleEndUnit(this.label, this.icon);

  final String label;
  final IconData icon;

  Duration durationFor(int amount) {
    switch (this) {
      case _BattleEndUnit.minutes:
        return Duration(minutes: amount);
      case _BattleEndUnit.hours:
        return Duration(hours: amount);
      case _BattleEndUnit.days:
        return Duration(days: amount);
    }
  }
}

class _BattleResolvedSide {
  const _BattleResolvedSide({
    required this.title,
    this.imageUrl,
    this.fallbackImageUrls = const <String>[],
    this.post,
  });

  final String title;
  final String? imageUrl;
  final List<String> fallbackImageUrls;
  final Post? post;
}

class CombinationBattleScreen extends StatefulWidget {
  const CombinationBattleScreen({
    super.key,
    required this.currentUser,
    required this.posts,
    required this.repository,
    required this.onUserChanged,
    required this.onOpenPost,
    required this.onOpenAuthor,
  });

  final PyeonUser currentUser;
  final List<Post> posts;
  final PostRepository repository;
  final Future<void> Function(PyeonUser user) onUserChanged;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(String authorId, String authorNickname)
  onOpenAuthor;

  @override
  State<CombinationBattleScreen> createState() =>
      _CombinationBattleScreenState();
}

class _CombinationBattleScreenState extends State<CombinationBattleScreen> {
  final TextEditingController _titleController = TextEditingController();

  late CombinationBattleState _state;
  Timer? _expiryTimer;
  List<Post> _allPosts = <Post>[];
  bool _loadingAllPosts = false;
  Map<String, int> _shuffleRanks = const <String, int>{};
  final double _leftHue = 355;
  final double _rightHue = 218;

  List<Post> get _sourcePosts => _allPosts.isEmpty ? widget.posts : _allPosts;

  @override
  void initState() {
    super.initState();
    _state = _initialState();
    _startExpiryWatcher();
    _loadSharedBattleState();
    _loadAllBattlePosts();
  }

  @override
  void didUpdateWidget(covariant CombinationBattleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id) {
      _loadSharedBattleState();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  CombinationBattleState _initialState() {
    if (widget.currentUser.battleState.matches.isNotEmpty) {
      return widget.currentUser.battleState;
    }
    return mockCombinationBattleState(_sourcePosts, now: DateTime.now());
  }

  CombinationBattleState _mergedState(
    CombinationBattleState base,
    CombinationBattleState extra,
  ) {
    final byId = <String, BattleMatchEntry>{
      for (final match in extra.matches) match.id: match,
    };
    for (final match in base.matches) {
      final previous = byId[match.id];
      if (previous == null) {
        byId[match.id] = match;
        continue;
      }
      final leftVoters = <String>{
        ...previous.leftVoterIds,
        ...match.leftVoterIds,
      };
      final rightVoters = <String>{
        ...previous.rightVoterIds,
        ...match.rightVoterIds,
      }..removeAll(leftVoters);
      byId[match.id] = match.copyWith(
        leftVoterIds: leftVoters.toList(),
        rightVoterIds: rightVoters.toList(),
      );
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return CombinationBattleState(matches: merged);
  }

  Future<void> _loadSharedBattleState() async {
    try {
      final shared = await BattleStateStore.load(
        fallback: widget.currentUser.battleState,
      );
      final seeded = shared.matches.isNotEmpty
          ? shared
          : mockCombinationBattleState(_sourcePosts, now: DateTime.now());
      if (!mounted) return;
      final merged = _mergedState(seeded, widget.currentUser.battleState);
      setState(() {
        _state = merged;
        if (_shuffleRanks.isEmpty && merged.matches.isNotEmpty) {
          _shuffleRanks = _buildShuffleRanks(merged.matches);
        }
      });
    } catch (_) {
      // Keep preview data when local persistence is unavailable.
    }
  }

  Future<void> _saveSharedBattleState(CombinationBattleState state) async {
    await BattleStateStore.save(state);
  }

  Future<void> _persist(CombinationBattleState state) async {
    final normalized = CombinationBattleState(
      matches: [...state.matches]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      notifiedExpiredMatchIds: state.notifiedExpiredMatchIds,
      todayEndedSummarySeenMatchIds: state.todayEndedSummarySeenMatchIds,
    );
    setState(() {
      _state = normalized;
      if (_shuffleRanks.isEmpty && normalized.matches.isNotEmpty) {
        _shuffleRanks = _buildShuffleRanks(normalized.matches);
      }
    });
    await Future.wait<void>([
      _saveSharedBattleState(normalized),
      widget.onUserChanged(
        widget.currentUser.copyWith(battleState: normalized),
      ),
    ]);
  }

  Future<void> _loadAllBattlePosts() async {
    if (_loadingAllPosts) return;
    setState(() => _loadingAllPosts = true);
    try {
      final pagePosts = await _fetchAllBattlePosts();
      if (!mounted) return;
      setState(() => _allPosts = pagePosts);
      if (pagePosts.length >= 2) {
        final repaired = _state.matches.isEmpty
            ? mockCombinationBattleState(pagePosts, now: DateTime.now())
            : _repairBattleStateForPosts(_state, pagePosts);
        final oldIds = _state.matches.map((match) => match.id).join('|');
        final newIds = repaired.matches.map((match) => match.id).join('|');
        if (oldIds != newIds) {
          await _persist(repaired);
        }
      }
    } catch (_) {
      // Fall back to communication page data.
    } finally {
      if (mounted) setState(() => _loadingAllPosts = false);
    }
  }

  Future<List<Post>> _fetchAllBattlePosts() async {
    return widget.repository.fetchPostCatalog(
      currentUserId: widget.currentUser.id,
    );
  }

  Post? _postForId(String id) {
    return _sourcePosts.where((post) => post.id == id).firstOrNull;
  }

  _BattleResolvedSide _resolvedSide(BattleMatchEntry match, bool isLeft) {
    final post = _postForId(isLeft ? match.leftPostId : match.rightPostId);
    final customTitle = isLeft ? match.leftCustomTitle : match.rightCustomTitle;
    final customImageUrl = isLeft
        ? match.leftCustomImageUrl
        : match.rightCustomImageUrl;
    if (post != null) {
      return _BattleResolvedSide(
        title: post.title,
        imageUrl: post.allImageUrls.firstOrNull,
        fallbackImageUrls: post.allImageUrls.skip(1).toList(),
        post: post,
      );
    }
    return _BattleResolvedSide(
      title: customTitle?.trim().isNotEmpty == true
          ? customTitle!.trim()
          : (isLeft ? '왼쪽 조합' : '오른쪽 조합'),
      imageUrl: customImageUrl,
    );
  }

  bool _matchHasResolvableImages(BattleMatchEntry match, List<Post> posts) {
    final postIds = posts.map((post) => post.id).toSet();
    final leftOk = match.usesCustomLeft || postIds.contains(match.leftPostId);
    final rightOk =
        match.usesCustomRight || postIds.contains(match.rightPostId);
    return leftOk && rightOk;
  }

  CombinationBattleState _repairBattleStateForPosts(
    CombinationBattleState state,
    List<Post> posts,
  ) {
    if (posts.length < 2) return state;
    final kept = state.matches
        .where((match) => _matchHasResolvableImages(match, posts))
        .toList();
    if (kept.length == state.matches.length && kept.isNotEmpty) return state;

    final seeded = mockCombinationBattleState(posts, now: DateTime.now());
    final existingIds = kept.map((match) => match.id).toSet();
    return CombinationBattleState(
      matches: <BattleMatchEntry>[
        ...kept,
        ...seeded.matches.where((match) => !existingIds.contains(match.id)),
      ],
    );
  }

  List<BattleMatchEntry> get _sortedMatches {
    final matches = _filteredMatches();
    if (_shuffleRanks.isNotEmpty) {
      matches.sort((a, b) {
        final aRank = _shuffleRanks[a.id] ?? 1 << 20;
        final bRank = _shuffleRanks[b.id] ?? 1 << 20;
        final compare = aRank.compareTo(bRank);
        return compare != 0 ? compare : b.createdAt.compareTo(a.createdAt);
      });
      return matches;
    }
    matches.sort((a, b) {
      final compare = b.totalVotes.compareTo(a.totalVotes);
      return compare != 0 ? compare : b.createdAt.compareTo(a.createdAt);
    });
    return matches;
  }

  List<BattleMatchEntry> _filteredMatches() {
    return _state.matches.where((match) {
      if (match.isExpired) return false;
      return true;
    }).toList();
  }

  Future<BattleMatchEntry> _vote(
    BattleMatchEntry match,
    BattleVoteSide side,
  ) async {
    if (match.isExpired) {
      _toast('투표 종료 시간이 지나서 더 이상 투표할 수 없어요.');
      return match;
    }
    final userId = widget.currentUser.id;
    if (match.voteSideOf(userId) != null) {
      _toast('이미 투표한 픽 쇼츠예요. 첫 선택은 바꾸지 않아요.');
      return match;
    }
    final updated = match.castVote(userId, side);
    await _replaceMatch(updated);
    return updated;
  }

  Future<void> _replaceMatch(BattleMatchEntry match) async {
    final matches = _state.matches
        .map((item) => item.id == match.id ? match : item)
        .toList();
    await _persist(_state.copyWith(matches: matches));
  }

  Future<void> _deleteMatch(BattleMatchEntry match) async {
    final matches = _state.matches
        .where((item) => item.id != match.id)
        .toList();
    await _persist(_state.copyWith(matches: matches));
  }

  void _startExpiryWatcher() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<String?> _pickCustomImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
      maxWidth: 1280,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  Future<BattleMatchEntry?> _createBattle({
    required String title,
    required _BattleCreateSourceMode sourceMode,
    required Post? leftPost,
    required Post? rightPost,
    required String leftCustomTitle,
    required String rightCustomTitle,
    required String? leftCustomImageUrl,
    required String? rightCustomImageUrl,
    required DateTime? battleEndsAt,
  }) async {
    if (title.isEmpty) {
      _toast('대결 제목을 입력해 주세요.');
      return null;
    }
    if (battleEndsAt == null || !battleEndsAt.isAfter(DateTime.now())) {
      _toast('투표 종료 시간을 현재보다 뒤로 설정해 주세요.');
      return null;
    }
    if (sourceMode == _BattleCreateSourceMode.community) {
      if (leftPost == null || rightPost == null) {
        _toast('커뮤니케이션 게시글 두 개를 모두 골라주세요.');
        return null;
      }
      if (leftPost.id == rightPost.id) {
        _toast('서로 다른 게시글을 골라주세요.');
        return null;
      }
      if (!_isCombinationPost(leftPost) || !_isCombinationPost(rightPost)) {
        _toast('픽 쇼츠에는 상품 사이에 +가 있는 조합만 올릴 수 있어요.');
        return null;
      }
    } else {
      if (leftCustomTitle.trim().isEmpty || rightCustomTitle.trim().isEmpty) {
        _toast('직접 입력 모드에서는 양쪽 조합 이름을 모두 적어주세요.');
        return null;
      }
      if (leftCustomImageUrl == null || rightCustomImageUrl == null) {
        _toast('직접 입력 모드에서는 양쪽 사진이 모두 필요해요. 바코드로 불러오거나 직접 올려주세요.');
        return null;
      }
      if (!_isCombinationTitle(leftCustomTitle) ||
          !_isCombinationTitle(rightCustomTitle)) {
        _toast('양쪽 조합 이름을 상품 A + 상품 B 형태로 입력해 주세요.');
        return null;
      }
    }

    final now = DateTime.now();
    final match = BattleMatchEntry(
      id: 'battle-${widget.currentUser.id}-${now.microsecondsSinceEpoch}',
      title: title,
      authorId: widget.currentUser.id,
      authorNickname: widget.currentUser.nickname,
      leftPostId: sourceMode == _BattleCreateSourceMode.community
          ? leftPost!.id
          : '',
      rightPostId: sourceMode == _BattleCreateSourceMode.community
          ? rightPost!.id
          : '',
      leftColorValue: _colorFromHue(_leftHue).toARGB32(),
      rightColorValue: _colorFromHue(_rightHue).toARGB32(),
      endsAt: battleEndsAt,
      requiredTitleKey: null,
      leftCustomTitle: sourceMode == _BattleCreateSourceMode.custom
          ? leftCustomTitle.trim()
          : null,
      rightCustomTitle: sourceMode == _BattleCreateSourceMode.custom
          ? rightCustomTitle.trim()
          : null,
      leftCustomImageUrl: sourceMode == _BattleCreateSourceMode.custom
          ? leftCustomImageUrl
          : null,
      rightCustomImageUrl: sourceMode == _BattleCreateSourceMode.custom
          ? rightCustomImageUrl
          : null,
      createdAt: now,
    );
    await _persist(
      _state.copyWith(matches: <BattleMatchEntry>[match, ..._state.matches]),
    );
    return match;
  }

  void _shuffleFeed() {
    setState(() => _shuffleRanks = _buildShuffleRanks(_filteredMatches()));
  }

  Map<String, int> _buildShuffleRanks(List<BattleMatchEntry> matches) {
    final ids = matches.map((match) => match.id).toList()
      ..shuffle(math.Random(DateTime.now().microsecondsSinceEpoch));
    return <String, int>{
      for (var index = 0; index < ids.length; index++) ids[index]: index,
    };
  }

  Future<void> _openCreatePage() async {
    final titleController = TextEditingController();
    final leftCustomTitleController = TextEditingController();
    final rightCustomTitleController = TextEditingController();
    final endAmountController = TextEditingController(text: '1');
    var sourceMode = _BattleCreateSourceMode.community;
    var endUnit = _BattleEndUnit.hours;
    Post? leftPost;
    Post? rightPost;
    String? leftCustomImageUrl;
    String? rightCustomImageUrl;

    Future<void> lookupBarcode(
      String rawValue,
      TextEditingController titleTarget,
      void Function(void Function()) setModalState,
      bool leftSide,
    ) async {
      final query = rawValue.trim();
      if (query.isEmpty) {
        _toast('바코드를 입력해 주세요.');
        return;
      }
      try {
        final result = await widget.repository.lookupProductByBarcode(query);
        final resolvedName = result.officialName.trim();
        if (resolvedName.isNotEmpty) {
          titleTarget.text = resolvedName;
          final productImageUrl = result.imageUrl?.trim();
          final matchedPost = _sourcePosts.where((post) {
            final postTitle = post.title.toLowerCase();
            final target = resolvedName.toLowerCase();
            return postTitle.contains(target) || target.contains(postTitle);
          }).firstOrNull;
          setModalState(() {
            final nextImageUrl =
                (productImageUrl != null && productImageUrl.isNotEmpty)
                ? productImageUrl
                : matchedPost?.allImageUrls.firstOrNull;
            if (nextImageUrl != null && nextImageUrl.isNotEmpty) {
              if (leftSide) {
                leftCustomImageUrl = nextImageUrl;
              } else {
                rightCustomImageUrl = nextImageUrl;
              }
            }
          });
        }
        final label = resolvedName.isEmpty ? '이름을 찾지 못했어요.' : resolvedName;
        _toast('바코드 확인: $label');
      } catch (_) {
        _toast('바코드를 조회하지 못했어요.');
      }
    }

    Future<void> scanBarcode(
      TextEditingController titleTarget,
      void Function(void Function()) setModalState,
      bool leftSide,
    ) async {
      final rawValue = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (context) => const _BattleBarcodeScannerPage(),
        ),
      );
      if (rawValue == null || rawValue.trim().isEmpty) return;
      await lookupBarcode(rawValue, titleTarget, setModalState, leftSide);
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Scaffold(
            backgroundColor: _battleCanvas,
            appBar: AppBar(
              backgroundColor: _battleCanvas,
              foregroundColor: _battleInk,
              elevation: 0,
              title: const Text('픽 쇼츠 올리기'),
            ),
            body: _BattleCreatePage(
              titleController: titleController,
              sourceMode: sourceMode,
              onSourceModeChanged: (value) {
                setModalState(() => sourceMode = value);
              },
              leftPost: leftPost,
              rightPost: rightPost,
              leftCustomTitleController: leftCustomTitleController,
              rightCustomTitleController: rightCustomTitleController,
              leftCustomImageUrl: leftCustomImageUrl,
              rightCustomImageUrl: rightCustomImageUrl,
              endAmountController: endAmountController,
              endUnit: endUnit,
              onEndUnitChanged: (value) {
                setModalState(() => endUnit = value);
              },
              onScanLeftBarcode: () =>
                  scanBarcode(leftCustomTitleController, setModalState, true),
              onScanRightBarcode: () =>
                  scanBarcode(rightCustomTitleController, setModalState, false),
              onPickLeft: () async {
                final selected = await showModalBottomSheet<Post>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _BattlePostPickerSheet(
                    posts: _sourcePosts.where(_isCombinationPost).toList(),
                    initialPost: leftPost,
                  ),
                );
                if (selected != null) {
                  setModalState(() => leftPost = selected);
                }
              },
              onPickRight: () async {
                final selected = await showModalBottomSheet<Post>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _BattlePostPickerSheet(
                    posts: _sourcePosts.where(_isCombinationPost).toList(),
                    initialPost: rightPost,
                  ),
                );
                if (selected != null) {
                  setModalState(() => rightPost = selected);
                }
              },
              onPickLeftCustomImage: () async {
                final image = await _pickCustomImage();
                if (image != null) {
                  setModalState(() => leftCustomImageUrl = image);
                }
              },
              onPickRightCustomImage: () async {
                final image = await _pickCustomImage();
                if (image != null) {
                  setModalState(() => rightCustomImageUrl = image);
                }
              },
              onSubmit: () async {
                final navigator = Navigator.of(context);
                final amount = int.tryParse(endAmountController.text.trim());
                if (amount == null || amount <= 0) {
                  _toast('투표 시간은 1 이상의 숫자로 입력해 주세요.');
                  return;
                }
                final createdMatch = await _createBattle(
                  title: titleController.text.trim(),
                  sourceMode: sourceMode,
                  leftPost: leftPost,
                  rightPost: rightPost,
                  leftCustomTitle: leftCustomTitleController.text,
                  rightCustomTitle: rightCustomTitleController.text,
                  leftCustomImageUrl: leftCustomImageUrl,
                  rightCustomImageUrl: rightCustomImageUrl,
                  battleEndsAt: DateTime.now().add(endUnit.durationFor(amount)),
                );
                if (createdMatch == null) return;
                setModalState(() {
                  titleController.clear();
                  leftCustomTitleController.clear();
                  rightCustomTitleController.clear();
                  leftPost = null;
                  rightPost = null;
                  leftCustomImageUrl = null;
                  rightCustomImageUrl = null;
                  endAmountController.text = '1';
                  endUnit = _BattleEndUnit.hours;
                  sourceMode = _BattleCreateSourceMode.community;
                });
                if (navigator.mounted) navigator.pop();
                _toast('픽 쇼츠를 올렸어요.');
                if (!mounted) return;
                await _openDetail(createdMatch);
              },
            ),
          ),
        ),
      ),
    );
    titleController.dispose();
    leftCustomTitleController.dispose();
    rightCustomTitleController.dispose();
    endAmountController.dispose();
  }

  Future<void> _openDetail(BattleMatchEntry match) async {
    final leftPost = _postForId(match.leftPostId);
    final rightPost = _postForId(match.rightPostId);

    final result = await Navigator.of(context).push<_BattleDetailResult>(
      MaterialPageRoute<_BattleDetailResult>(
        builder: (context) => _BattleMatchDetailPage(
          match: match,
          currentUser: widget.currentUser,
          leftPost: leftPost,
          rightPost: rightPost,
          allPosts: _sourcePosts,
          onOpenPost: widget.onOpenPost,
          onOpenAuthor: widget.onOpenAuthor,
          onVote: _vote,
        ),
      ),
    );
    if (result == null) return;

    switch (result) {
      case _BattleDetailDeleted():
        await _deleteMatch(match);
        if (mounted) _toast('픽 쇼츠를 삭제했어요.');
      case _BattleDetailUpdated(:final match):
        await _replaceMatch(match);
        if (mounted) _toast('픽 쇼츠를 수정했어요.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _colorFromHue(double hue) {
    return HSVColor.fromAHSV(1, hue, 0.82, 0.82).toColor();
  }

  int get _todayWinCount {
    final userId = widget.currentUser.id;
    return _state.matches.where((match) {
      if (!_hasEndedToday(match.endsAt)) return false;
      final votedSide = match.voteSideOf(userId);
      if (votedSide == null) return false;
      final winner = match.winnerSide;
      if (winner == null) return false;
      return winner == votedSide;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _battleCanvas),
      child: _BattleFeedPage(
        matches: _sortedMatches,
        currentUserId: widget.currentUser.id,
        todayWinCount: _todayWinCount,
        onShuffle: _shuffleFeed,
        onOpenCreate: _openCreatePage,
        resolveSide: _resolvedSide,
        onVote: _vote,
        onOpenPost: widget.onOpenPost,
        onOpenAuthor: widget.onOpenAuthor,
        onOpenDetail: _openDetail,
      ),
    );
  }
}

class _BattleFeedPage extends StatefulWidget {
  const _BattleFeedPage({
    required this.matches,
    required this.currentUserId,
    required this.todayWinCount,
    required this.onShuffle,
    required this.onOpenCreate,
    required this.resolveSide,
    required this.onVote,
    required this.onOpenPost,
    required this.onOpenAuthor,
    required this.onOpenDetail,
  });

  final List<BattleMatchEntry> matches;
  final String currentUserId;
  final int todayWinCount;
  final VoidCallback onShuffle;
  final VoidCallback onOpenCreate;
  final _BattleResolvedSide Function(BattleMatchEntry match, bool isLeft)
  resolveSide;
  final Future<BattleMatchEntry> Function(
    BattleMatchEntry match,
    BattleVoteSide side,
  )
  onVote;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(String authorId, String authorNickname)
  onOpenAuthor;
  final Future<void> Function(BattleMatchEntry match) onOpenDetail;

  @override
  State<_BattleFeedPage> createState() => _BattleFeedPageState();
}

class _BattleFeedPageState extends State<_BattleFeedPage> {
  late final PageController _pageController;
  int _pageIndex = 0;
  String? _revealedMatchId;
  BattleMatchEntry? _revealedMatch;
  bool _processingVote = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant _BattleFeedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_revealedMatchId != null &&
        !widget.matches.any((match) => match.id == _revealedMatchId)) {
      _revealedMatchId = null;
      _revealedMatch = null;
      _processingVote = false;
    }
    if (widget.matches.isEmpty) {
      _pageIndex = 0;
      return;
    }
    if (_pageIndex >= widget.matches.length) {
      _pageIndex = widget.matches.length - 1;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_pageIndex);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goNextFrom(String matchId) async {
    if (widget.matches.isEmpty || !_pageController.hasClients) return;
    final resolvedIndex = widget.matches.indexWhere(
      (match) => match.id == matchId,
    );
    final currentIndex = resolvedIndex >= 0 ? resolvedIndex : _pageIndex;
    final nextIndex = (currentIndex + 1) % widget.matches.length;
    if (nextIndex == currentIndex) return;
    await _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() => _pageIndex = nextIndex);
  }

  Future<BattleMatchEntry> _handleVote(
    BattleMatchEntry match,
    BattleVoteSide side,
  ) async {
    if (_processingVote) return match;
    setState(() => _processingVote = true);
    final updated = await widget.onVote(match, side);
    if (!mounted) return updated;
    setState(() {
      _revealedMatchId = updated.id;
      _revealedMatch = updated;
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return updated;
    await _goNextFrom(updated.id);
    if (!mounted) return updated;
    setState(() {
      _revealedMatchId = null;
      _revealedMatch = null;
      _processingVote = false;
    });
    return updated;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '픽 쇼츠',
                  style: TextStyle(
                    color: _battleInk,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (widget.todayWinCount > 0) ...[
                const Text(
                  '오늘',
                  style: TextStyle(
                    color: _battleSubtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ' ${widget.todayWinCount}승',
                  style: const TextStyle(
                    color: _battleInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Tooltip(
                message: '새로 섞기',
                child: IconButton(
                  onPressed: () {
                    widget.onShuffle();
                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(0);
                    }
                    setState(() => _pageIndex = 0);
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                  color: _battleInk,
                ),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: widget.onOpenCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  '올리기',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: widget.matches.isEmpty
                ? const Center(
                    child: Text(
                      '아직 올라온 픽 쇼츠가 없어요.\n첫 번째 대결을 만들어보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _battleSubtle,
                        fontWeight: FontWeight.w800,
                        height: 1.6,
                      ),
                    ),
                  )
                : PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    itemCount: widget.matches.length,
                    physics: _processingVote
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (value) =>
                        setState(() => _pageIndex = value),
                    itemBuilder: (context, index) {
                      final match = widget.matches[index];
                      final revealMatch = _revealedMatchId == match.id
                          ? _revealedMatch
                          : null;
                      final left = widget.resolveSide(match, true);
                      final right = widget.resolveSide(match, false);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _BattleMatchCard(
                          match: match,
                          leftSide: left,
                          rightSide: right,
                          currentUserId: widget.currentUserId,
                          immersive: true,
                          revealMatch: revealMatch,
                          showVoteStats: match.isExpired || revealMatch != null,
                          onVote: _handleVote,
                          onOpenLeft: left.post == null
                              ? null
                              : () {
                                  widget.onOpenPost(left.post!);
                                },
                          onOpenRight: right.post == null
                              ? null
                              : () {
                                  widget.onOpenPost(right.post!);
                                },
                          onOpenAuthor: () {
                            widget.onOpenAuthor(
                              match.authorId,
                              match.authorNickname,
                            );
                          },
                          authorProfileImageUrl: _battleAuthorImageUrl(
                            match,
                            left,
                            right,
                          ),
                          onOpenDetail: () {
                            widget.onOpenDetail(match);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String? _battleAuthorImageUrl(
    BattleMatchEntry match,
    _BattleResolvedSide left,
    _BattleResolvedSide right,
  ) {
    if (left.post?.authorId == match.authorId) {
      return left.post?.authorProfileImageUrl;
    }
    if (right.post?.authorId == match.authorId) {
      return right.post?.authorProfileImageUrl;
    }
    return null;
  }
}

class _BattleCreatePage extends StatelessWidget {
  const _BattleCreatePage({
    required this.titleController,
    required this.sourceMode,
    required this.onSourceModeChanged,
    required this.leftPost,
    required this.rightPost,
    required this.leftCustomTitleController,
    required this.rightCustomTitleController,
    required this.leftCustomImageUrl,
    required this.rightCustomImageUrl,
    required this.endAmountController,
    required this.endUnit,
    required this.onEndUnitChanged,
    required this.onScanLeftBarcode,
    required this.onScanRightBarcode,
    required this.onPickLeft,
    required this.onPickRight,
    required this.onPickLeftCustomImage,
    required this.onPickRightCustomImage,
    required this.onSubmit,
  });

  final TextEditingController titleController;
  final _BattleCreateSourceMode sourceMode;
  final ValueChanged<_BattleCreateSourceMode> onSourceModeChanged;
  final Post? leftPost;
  final Post? rightPost;
  final TextEditingController leftCustomTitleController;
  final TextEditingController rightCustomTitleController;
  final String? leftCustomImageUrl;
  final String? rightCustomImageUrl;
  final TextEditingController endAmountController;
  final _BattleEndUnit endUnit;
  final ValueChanged<_BattleEndUnit> onEndUnitChanged;
  final Future<void> Function() onScanLeftBarcode;
  final Future<void> Function() onScanRightBarcode;
  final VoidCallback onPickLeft;
  final VoidCallback onPickRight;
  final VoidCallback onPickLeftCustomImage;
  final VoidCallback onPickRightCustomImage;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '새 픽 쇼츠',
                style: TextStyle(
                  color: _battleInk,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '상품 A + 상품 B처럼 실제 조합만 대결에 올릴 수 있어요.',
                style: TextStyle(
                  color: _battleSubtle,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              _BattleSourceModeToggle(
                sourceMode: sourceMode,
                onChanged: onSourceModeChanged,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '대결 제목',
                  hintText: '예: 야식으로 더 끌리는 조합은?',
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: _battleLine),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _battleLine),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF49A9D8), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (sourceMode == _BattleCreateSourceMode.community)
                _BattleCreateSlot(
                  label: '왼쪽 조합',
                  post: leftPost,
                  onTap: onPickLeft,
                )
              else
                _BattleManualCreateSlot(
                  label: '왼쪽 조합',
                  titleController: leftCustomTitleController,
                  imageUrl: leftCustomImageUrl,
                  onScanBarcode: onScanLeftBarcode,
                  onPickImage: onPickLeftCustomImage,
                ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6FB),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(
                      color: Color(0xFF8D99A7),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (sourceMode == _BattleCreateSourceMode.community)
                _BattleCreateSlot(
                  label: '오른쪽 조합',
                  post: rightPost,
                  onTap: onPickRight,
                )
              else
                _BattleManualCreateSlot(
                  label: '오른쪽 조합',
                  titleController: rightCustomTitleController,
                  imageUrl: rightCustomImageUrl,
                  onScanBarcode: onScanRightBarcode,
                  onPickImage: onPickRightCustomImage,
                ),
              const SizedBox(height: 14),
              _BattleDurationPicker(
                amountController: endAmountController,
                unit: endUnit,
                onUnitChanged: onEndUnitChanged,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF49A9D8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '올리기',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BattleDurationPicker extends StatelessWidget {
  const _BattleDurationPicker({
    required this.amountController,
    required this.unit,
    required this.onUnitChanged,
  });

  final TextEditingController amountController;
  final _BattleEndUnit unit;
  final ValueChanged<_BattleEndUnit> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: _battleInk),
              SizedBox(width: 8),
              Text(
                '투표 시간 설정',
                style: TextStyle(
                  color: _battleInk,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 92,
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '숫자',
                    hintText: '1',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _BattleEndUnit.values
                      .map(
                        (item) => ChoiceChip(
                          selected: unit == item,
                          avatar: Icon(item.icon, size: 16),
                          label: Text(item.label),
                          onSelected: (_) => onUnitChanged(item),
                          selectedColor: const Color(0xFFDDEBFF),
                          labelStyle: TextStyle(
                            color: unit == item
                                ? const Color(0xFF2458B6)
                                : _battleSubtle,
                            fontWeight: FontWeight.w900,
                          ),
                          side: BorderSide(
                            color: unit == item
                                ? const Color(0xFF2458B6)
                                : _battleLine,
                          ),
                          backgroundColor: Colors.white,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: amountController,
            builder: (context, value, _) {
              final amount = int.tryParse(value.text.trim());
              final previewEndsAt = amount == null || amount <= 0
                  ? null
                  : DateTime.now().add(unit.durationFor(amount));
              return Text(
                previewEndsAt == null
                    ? '1 이상의 숫자를 입력하면 종료 시간이 계산돼요.'
                    : '$amount${unit.label} 뒤 종료 · ${_formatBattleDateTime(previewEndsAt)}',
                style: const TextStyle(
                  color: _battleSubtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BattleManualCreateSlot extends StatelessWidget {
  const _BattleManualCreateSlot({
    required this.label,
    required this.titleController,
    required this.imageUrl,
    required this.onScanBarcode,
    required this.onPickImage,
  });

  final String label;
  final TextEditingController titleController;
  final String? imageUrl;
  final Future<void> Function() onScanBarcode;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _battleInk,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE6F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? _BattleImageFill(
                        imageUrl: imageUrl,
                        fallbackColor: const Color(0xFFF4F7FA),
                        iconColor: _battleSubtle,
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            color: _battleSubtle,
                            size: 30,
                          ),
                          SizedBox(height: 8),
                          Text(
                            '사진을 추가해주세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF96A4B2),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '조합 이름',
                    hintText: '예: 불닭볶음면 + 스트링치즈',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPickImage,
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFF5FAFC),
                foregroundColor: const Color(0xFF276A85),
                side: const BorderSide(color: Color(0xFFCFE4EC)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text(
                '사진 올리기',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onScanBarcode,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF174C84),
                side: const BorderSide(color: Color(0xFFD4E2EA)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text(
                '바코드로 상품명 불러오기',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleCreateSlot extends StatelessWidget {
  const _BattleCreateSlot({
    required this.label,
    required this.post,
    required this.onTap,
  });

  final String label;
  final Post? post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _battleLine)),
        ),
        child: post == null
            ? Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: _battleSubtle,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: _battleInk,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '게시글 선택',
                          style: TextStyle(
                            color: _battleSubtle,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  _BattleImageThumb(imageUrl: post!.allImageUrls.firstOrNull),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: _battleInk,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConvenienceProductTitle(
                          title: post!.title,
                          contextText: '${post!.title} ${post!.content}',
                          maxLines: 2,
                          style: const TextStyle(
                            color: _battleInk,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BattleBarcodeScannerPage extends StatefulWidget {
  const _BattleBarcodeScannerPage();

  @override
  State<_BattleBarcodeScannerPage> createState() =>
      _BattleBarcodeScannerPageState();
}

class _BattleBarcodeScannerPageState extends State<_BattleBarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
  );
  final TextEditingController _manualCodeController = TextEditingController();
  bool _handled = false;
  bool _starting = !kIsWeb;
  bool _readyForWebTap = kIsWeb;
  String? _scannerError;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScanner();
      });
    }
  }

  @override
  void dispose() {
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
          decoration: const InputDecoration(
            labelText: '바코드 숫자',
            hintText: '예: 880...',
          ),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FDFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '상품 바코드 스캔',
                          style: TextStyle(
                            color: _battleInk,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '바코드를 정면으로 맞추면 상품명을 자동으로 불러와요.',
                          style: TextStyle(
                            color: _battleSubtle,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 30),
                    color: _battleInk,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6FF),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFFD2E9F7)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      MobileScanner(
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
                        errorBuilder: (_, exception) => _BattleScannerStatus(
                          text: '카메라를 시작하지 못했어요',
                          detail:
                              exception.errorDetails?.message ??
                              exception.errorCode.message,
                          onRetry: _startScanner,
                        ),
                      ),
                      if (_readyForWebTap)
                        Center(
                          child: FilledButton.icon(
                            onPressed: _startScanner,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF49ACE6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text(
                              '카메라 켜기',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      if (_starting)
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: _BattleScannerStatus(
                              text: '카메라 준비 중',
                              loading: true,
                            ),
                          ),
                        ),
                      if (_scannerError != null && !_starting)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _BattleScannerStatus(
                              text: '카메라 연결을 확인해 주세요.',
                              detail: _scannerError,
                              onRetry: _startScanner,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openManualBarcodeInput,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF174C84),
                    side: const BorderSide(color: Color(0xFFD4E2EA)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.keyboard_alt_rounded),
                  label: const Text(
                    '바코드 직접 입력',
                    style: TextStyle(fontWeight: FontWeight.w900),
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

class _BattleScannerStatus extends StatelessWidget {
  const _BattleScannerStatus({
    required this.text,
    this.detail,
    this.loading = false,
    this.onRetry,
  });

  final String text;
  final String? detail;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(232),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            const Icon(Icons.info_outline_rounded, color: _battleSubtle),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              detail == null ? text : '$text\n$detail',
              style: const TextStyle(
                color: _battleInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('재시도')),
        ],
      ),
    );
  }
}

class _BattleMatchCard extends StatelessWidget {
  const _BattleMatchCard({
    required this.match,
    required this.leftSide,
    required this.rightSide,
    required this.currentUserId,
    required this.onVote,
    this.revealMatch,
    this.showVoteStats = true,
    this.onOpenLeft,
    this.onOpenRight,
    required this.onOpenAuthor,
    this.authorProfileImageUrl,
    required this.onOpenDetail,
    this.immersive = false,
  });

  final BattleMatchEntry match;
  final _BattleResolvedSide leftSide;
  final _BattleResolvedSide rightSide;
  final String currentUserId;
  final Future<BattleMatchEntry> Function(
    BattleMatchEntry match,
    BattleVoteSide side,
  )
  onVote;
  final BattleMatchEntry? revealMatch;
  final bool showVoteStats;
  final VoidCallback? onOpenLeft;
  final VoidCallback? onOpenRight;
  final VoidCallback onOpenAuthor;
  final String? authorProfileImageUrl;
  final VoidCallback onOpenDetail;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final displayMatch = revealMatch ?? match;
    final selectedSide = displayMatch.voteSideOf(currentUserId);
    final totalVotes = math.max(1, displayMatch.totalVotes);
    final leftColor = Color(displayMatch.leftColorValue);
    final rightColor = Color(displayMatch.rightColorValue);
    final voteArena = _BattleVoteArena(
      match: displayMatch,
      matchTitle: displayMatch.title,
      leftSide: leftSide,
      rightSide: rightSide,
      selectedSide: selectedSide,
      leftColor: leftColor,
      rightColor: rightColor,
      height: immersive ? null : 260,
      showVoteStats: showVoteStats,
      onVote: onVote,
    );
    return Container(
      padding: EdgeInsets.all(immersive ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(immersive ? 8 : 28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (immersive) Expanded(child: voteArena) else voteArena,
          if (!immersive) ...[
            const SizedBox(height: 12),
            _BattleEndPill(match: match),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${((displayMatch.leftVotes / totalVotes) * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: _darken(leftColor),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '총 ${_formatVotes(displayMatch.totalVotes)}표',
                  style: const TextStyle(
                    color: _battleSubtle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${((displayMatch.rightVotes / totalVotes) * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _darken(rightColor),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!immersive) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                InkWell(
                  onTap: onOpenAuthor,
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BattleImageThumb(
                        imageUrl: authorProfileImageUrl,
                        size: 22,
                        borderColor: const Color(0xFFDCE6F0),
                        emptyIconColor: _battleSubtle,
                        backgroundColor: const Color(0xFFF5F8FC),
                        borderRadius: 999,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '@${match.authorNickname}',
                        style: const TextStyle(
                          color: _battleSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onOpenDetail, child: const Text('상세')),
              ],
            ),
          ],
          if (!immersive && (onOpenLeft != null || onOpenRight != null)) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (onOpenLeft != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpenLeft,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _battleInk,
                        side: const BorderSide(color: _battleLine),
                      ),
                      child: const Text('왼쪽 글'),
                    ),
                  ),
                if (onOpenLeft != null && onOpenRight != null)
                  const SizedBox(width: 10),
                if (onOpenRight != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpenRight,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _battleInk,
                        side: const BorderSide(color: _battleLine),
                      ),
                      child: const Text('오른쪽 글'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BattleEndPill extends StatelessWidget {
  const _BattleEndPill({required this.match});

  final BattleMatchEntry match;

  @override
  Widget build(BuildContext context) {
    final endsAt = match.endsAt;
    if (endsAt == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD9E0E8)),
          ),
          child: Text(
            '종료 시간 없음',
            style: const TextStyle(
              color: _battleSubtle,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }
    final expired = match.isExpired;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: expired ? const Color(0xFFF0F2F5) : const Color(0xFFEAF3FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: expired ? const Color(0xFFD9E0E8) : const Color(0xFFCFE1FF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expired ? Icons.lock_clock_rounded : Icons.timer_rounded,
              size: 15,
              color: expired ? _battleSubtle : const Color(0xFF2458B6),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                expired
                    ? '투표 종료 · ${_formatBattleDateTime(endsAt)}'
                    : '${_formatBattleRemaining(endsAt)} 남음 · ${_formatBattleDateTime(endsAt)} 종료',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: expired ? _battleSubtle : const Color(0xFF2458B6),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleVoteArena extends StatelessWidget {
  const _BattleVoteArena({
    required this.match,
    required this.matchTitle,
    required this.leftSide,
    required this.rightSide,
    required this.selectedSide,
    required this.leftColor,
    required this.rightColor,
    required this.showVoteStats,
    required this.onVote,
    this.height = 204,
  });

  final BattleMatchEntry match;
  final String matchTitle;
  final _BattleResolvedSide leftSide;
  final _BattleResolvedSide rightSide;
  final BattleVoteSide? selectedSide;
  final Color leftColor;
  final Color rightColor;
  final bool showVoteStats;
  final Future<BattleMatchEntry> Function(
    BattleMatchEntry match,
    BattleVoteSide side,
  )
  onVote;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        const vsSize = 62.0;
        final arenaHeight = constraints.maxHeight;
        final seamX = constraints.maxWidth / 2;
        final sideWidth = constraints.maxWidth / 2;

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: sideWidth,
              child: _BattleVoteSideCard(
                side: leftSide,
                votes: match.leftVotes,
                color: leftColor,
                darkColor: _darken(leftColor),
                active: selectedSide == BattleVoteSide.left,
                disabled: match.isExpired,
                fullBleed: height == null,
                showVotes: showVoteStats,
                alignLeft: true,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  topRight: Radius.zero,
                  bottomRight: Radius.zero,
                ),
                onTap: () => onVote(match, BattleVoteSide.left),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: sideWidth,
              child: _BattleVoteSideCard(
                side: rightSide,
                votes: match.rightVotes,
                color: rightColor,
                darkColor: _darken(rightColor),
                active: selectedSide == BattleVoteSide.right,
                disabled: match.isExpired,
                fullBleed: height == null,
                showVotes: showVoteStats,
                alignLeft: false,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.zero,
                  bottomLeft: Radius.zero,
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                onTap: () => onVote(match, BattleVoteSide.right),
              ),
            ),
            Positioned(
              left: seamX - (vsSize / 2),
              top: (arenaHeight - vsSize) / 2,
              child: Container(
                width: vsSize,
                height: vsSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(238),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(14),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Color(0xFF8D99A7),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(238),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(16),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    matchTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _battleInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (height == null) return content;
    return SizedBox(height: height, child: content);
  }
}

class _BattleVoteSideCard extends StatelessWidget {
  const _BattleVoteSideCard({
    required this.side,
    required this.votes,
    required this.color,
    required this.darkColor,
    required this.active,
    required this.disabled,
    required this.fullBleed,
    required this.showVotes,
    required this.alignLeft,
    required this.borderRadius,
    required this.onTap,
  });

  final _BattleResolvedSide side;
  final int votes;
  final Color color;
  final Color darkColor;
  final bool active;
  final bool disabled;
  final bool fullBleed;
  final bool showVotes;
  final bool alignLeft;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.all(fullBleed ? 0 : 5),
        decoration: BoxDecoration(
          color: fullBleed ? Colors.transparent : Colors.white,
          borderRadius: borderRadius,
          border: fullBleed ? null : Border.all(color: const Color(0xFFE5E9ED)),
          boxShadow: fullBleed
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(active ? 24 : 12),
                    blurRadius: active ? 20 : 14,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: fullBleed
            ? _BattleVoteHero(
                imageUrl: side.imageUrl,
                fallbackImageUrls: side.fallbackImageUrls,
                title: side.title,
                votes: _formatVotes(votes),
                color: color,
                showVotes: showVotes,
                alignLeft: alignLeft,
                borderRadius: borderRadius,
              )
            : Column(
                children: [
                  Expanded(
                    child: _BattleVoteHero(
                      imageUrl: side.imageUrl,
                      fallbackImageUrls: side.fallbackImageUrls,
                      votes: _formatVotes(votes),
                      color: color,
                      showVotes: true,
                      alignLeft: alignLeft,
                      borderRadius: BorderRadius.only(
                        topLeft: borderRadius.topLeft,
                        topRight: borderRadius.topRight,
                        bottomLeft: const Radius.circular(10),
                        bottomRight: const Radius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 38,
                    child: Align(
                      alignment: alignLeft
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Text(
                        side.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: alignLeft ? TextAlign.left : TextAlign.right,
                        style: const TextStyle(
                          color: _battleInk,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.2,
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

class _BattleImageThumb extends StatelessWidget {
  const _BattleImageThumb({
    required this.imageUrl,
    this.size = 62,
    this.borderColor = const Color(0x33FFFFFF),
    this.emptyIconColor = Colors.white,
    this.backgroundColor = const Color(0x22FFFFFF),
    this.borderRadius = 16,
  });

  final String? imageUrl;
  final double size;
  final Color borderColor;
  final Color emptyIconColor;
  final Color backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Icon(Icons.fastfood_rounded, color: emptyIconColor, size: 28)
          : _BattleImageFill(
              imageUrl: imageUrl,
              fallbackColor: backgroundColor,
              iconColor: emptyIconColor,
            ),
    );
  }
}

class _BattleImageFill extends StatelessWidget {
  const _BattleImageFill({
    required this.imageUrl,
    required this.fallbackColor,
    required this.iconColor,
    this.fallbackImageUrls = const <String>[],
  });

  final String? imageUrl;
  final Color fallbackColor;
  final Color iconColor;
  final List<String> fallbackImageUrls;

  @override
  Widget build(BuildContext context) {
    final source = imageUrl?.trim() ?? '';
    if (source.isEmpty) return _fallback();
    if (source.startsWith('data:')) {
      final commaIndex = source.indexOf(',');
      if (commaIndex <= 0) return _fallback();
      try {
        return Image.memory(
          base64Decode(source.substring(commaIndex + 1)),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _errorFallback(),
        );
      } catch (_) {
        return _fallback();
      }
    }
    return _networkImage(<String>[
      source,
      ...fallbackImageUrls.where((url) => url.trim().isNotEmpty),
    ]);
  }

  Widget _networkImage(List<String> sources, [int index = 0]) {
    return Image.network(
      _battleDisplayImageUrl(sources[index]),
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            _fallback(),
            const Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
          ],
        );
      },
      errorBuilder: (_, _, _) => index + 1 < sources.length
          ? _networkImage(sources, index + 1)
          : _errorFallback(),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fallbackColor.withAlpha(36), fallbackColor.withAlpha(10)],
        ),
      ),
      child: Center(
        child: Icon(Icons.fastfood_rounded, size: 42, color: iconColor),
      ),
    );
  }

  Widget _errorFallback() {
    return Container(
      color: const Color(0xFFF2F5F8),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Color(0xFF8DA0B3), size: 36),
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

class _BattleVoteHero extends StatelessWidget {
  const _BattleVoteHero({
    required this.imageUrl,
    this.fallbackImageUrls = const <String>[],
    this.title,
    required this.votes,
    required this.color,
    required this.showVotes,
    required this.alignLeft,
    required this.borderRadius,
  });

  final String? imageUrl;
  final List<String> fallbackImageUrls;
  final String? title;
  final String votes;
  final Color color;
  final bool showVotes;
  final bool alignLeft;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final textAlign = alignLeft ? TextAlign.left : TextAlign.right;

    return Container(
      height: double.infinity,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: const Color(0xFFF0F1F2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _BattleImageFill(
            imageUrl: imageUrl,
            fallbackImageUrls: fallbackImageUrls,
            fallbackColor: color,
            iconColor: color,
          ),
          if (title != null)
            Positioned(
              left: alignLeft ? 14 : 8,
              right: alignLeft ? 8 : 14,
              bottom: 14,
              child: Align(
                alignment: alignLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(226),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    title!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    style: const TextStyle(
                      color: _battleInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          if (showVotes)
            Center(
              child: IgnorePointer(
                child: Text(
                  '$votes\n표',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 0.92,
                    shadows: [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 18,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BattlePostPickerSheet extends StatefulWidget {
  const _BattlePostPickerSheet({required this.posts, this.initialPost});

  final List<Post> posts;
  final Post? initialPost;

  @override
  State<_BattlePostPickerSheet> createState() => _BattlePostPickerSheetState();
}

class _BattlePostPickerSheetState extends State<_BattlePostPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  SortMode _sortMode = SortMode.latest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Post> get _filteredPosts {
    final query = _searchController.text.trim().toLowerCase();
    final posts = [...widget.posts]
      ..sort((a, b) {
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
    if (query.isEmpty) return posts;
    return posts.where((post) {
      return post.title.toLowerCase().contains(query) ||
          post.authorNickname.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _filteredPosts;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: Colors.white,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.86,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7E0E8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Text(
                          '커뮤니케이션 게시글 불러오기',
                          style: TextStyle(
                            color: _battleInk,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '제목이나 작성자 검색',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: SegmentedButton<SortMode>(
                      segments: const [
                        ButtonSegment(
                          value: SortMode.latest,
                          label: Text('최신순'),
                        ),
                        ButtonSegment(
                          value: SortMode.popular,
                          label: Text('인기순'),
                        ),
                        ButtonSegment(
                          value: SortMode.worst,
                          label: Text('최악순'),
                        ),
                      ],
                      selected: {_sortMode},
                      onSelectionChanged: (values) =>
                          setState(() => _sortMode = values.first),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: posts.isEmpty
                        ? const Center(
                            child: Text(
                              '불러올 게시글이 없어요.',
                              style: TextStyle(
                                color: _battleSubtle,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              final selected =
                                  widget.initialPost?.id == post.id;
                              return ListTile(
                                onTap: () => Navigator.of(context).pop(post),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                tileColor: selected
                                    ? const Color(0xFFEFF5FF)
                                    : const Color(0xFFF8FBFE),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: selected
                                        ? const Color(0xFFBFD1F0)
                                        : _battleLine,
                                  ),
                                ),
                                leading: _BattleImageThumb(
                                  imageUrl: post.allImageUrls.firstOrNull,
                                  size: 50,
                                  borderColor: const Color(0xFFDCE6F0),
                                ),
                                title: Text(
                                  post.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _battleInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  '@${post.authorNickname} · ${post.priceLabel} · 하트 ${post.likes}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _battleSubtle,
                                ),
                              );
                            },
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemCount: posts.length,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _BattleDetailResult {
  const _BattleDetailResult();
}

class _BattleDetailDeleted extends _BattleDetailResult {
  const _BattleDetailDeleted();
}

class _BattleDetailUpdated extends _BattleDetailResult {
  const _BattleDetailUpdated(this.match);

  final BattleMatchEntry match;
}

class _BattleMatchDetailPage extends StatefulWidget {
  const _BattleMatchDetailPage({
    required this.match,
    required this.currentUser,
    required this.leftPost,
    required this.rightPost,
    required this.allPosts,
    required this.onOpenPost,
    required this.onOpenAuthor,
    required this.onVote,
  });

  final BattleMatchEntry match;
  final PyeonUser currentUser;
  final Post? leftPost;
  final Post? rightPost;
  final List<Post> allPosts;
  final Future<void> Function(Post post) onOpenPost;
  final Future<void> Function(String authorId, String authorNickname)
  onOpenAuthor;
  final Future<BattleMatchEntry> Function(
    BattleMatchEntry match,
    BattleVoteSide side,
  )
  onVote;

  @override
  State<_BattleMatchDetailPage> createState() => _BattleMatchDetailPageState();
}

class _BattleMatchDetailPageState extends State<_BattleMatchDetailPage> {
  late TextEditingController _titleController;
  Post? _leftPost;
  Post? _rightPost;
  late double _leftHue;
  late double _rightHue;
  late BattleMatchEntry _previewMatch;
  bool _editing = false;

  bool get _isMine => widget.match.authorId == widget.currentUser.id;
  bool get _usesCommunityPosts =>
      _leftPost != null &&
      _rightPost != null &&
      !widget.match.usesCustomLeft &&
      !widget.match.usesCustomRight;

  _BattleResolvedSide _resolvedSide(bool isLeft) {
    final post = isLeft ? _leftPost : _rightPost;
    final customTitle = isLeft
        ? _previewMatch.leftCustomTitle
        : _previewMatch.rightCustomTitle;
    final customImageUrl = isLeft
        ? _previewMatch.leftCustomImageUrl
        : _previewMatch.rightCustomImageUrl;
    if (post != null) {
      return _BattleResolvedSide(
        title: post.title,
        imageUrl: post.allImageUrls.firstOrNull,
        fallbackImageUrls: post.allImageUrls.skip(1).toList(),
        post: post,
      );
    }
    return _BattleResolvedSide(
      title: customTitle?.trim().isNotEmpty == true
          ? customTitle!.trim()
          : (isLeft ? '왼쪽 조합' : '오른쪽 조합'),
      imageUrl: customImageUrl,
    );
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.match.title);
    _leftPost = widget.leftPost;
    _rightPost = widget.rightPost;
    _previewMatch = widget.match;
    _leftHue = HSVColor.fromColor(Color(widget.match.leftColorValue)).hue;
    _rightHue = HSVColor.fromColor(Color(widget.match.rightColorValue)).hue;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickPost(bool leftSide) async {
    if (!_usesCommunityPosts) return;
    final selected = await showModalBottomSheet<Post>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BattlePostPickerSheet(
        posts: widget.allPosts,
        initialPost: leftSide ? _leftPost : _rightPost,
      ),
    );
    if (selected == null) return;
    setState(() {
      if (leftSide) {
        _leftPost = selected;
      } else {
        _rightPost = selected;
      }
    });
  }

  void _saveEdit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    if (_usesCommunityPosts && _leftPost!.id == _rightPost!.id) return;
    final updated = _previewMatch.copyWith(
      title: title,
      leftColorValue: HSVColor.fromAHSV(
        1,
        _leftHue,
        0.82,
        0.82,
      ).toColor().toARGB32(),
      rightColorValue: HSVColor.fromAHSV(
        1,
        _rightHue,
        0.82,
        0.82,
      ).toColor().toARGB32(),
    );
    final replaced = BattleMatchEntry(
      id: updated.id,
      title: updated.title,
      authorId: updated.authorId,
      authorNickname: updated.authorNickname,
      leftPostId: _leftPost?.id ?? updated.leftPostId,
      rightPostId: _rightPost?.id ?? updated.rightPostId,
      createdAt: updated.createdAt,
      leftColorValue: updated.leftColorValue,
      rightColorValue: updated.rightColorValue,
      endsAt: updated.endsAt,
      requiredTitleKey: null,
      leftCustomTitle: updated.leftCustomTitle,
      rightCustomTitle: updated.rightCustomTitle,
      leftCustomImageUrl: updated.leftCustomImageUrl,
      rightCustomImageUrl: updated.rightCustomImageUrl,
      leftVoterIds: updated.leftVoterIds,
      rightVoterIds: updated.rightVoterIds,
    );
    Navigator.of(context).pop(_BattleDetailUpdated(replaced));
  }

  Future<BattleMatchEntry> _vote(BattleVoteSide side) async {
    final updated = await widget.onVote(_previewMatch, side);
    if (!mounted) return updated;
    setState(() => _previewMatch = updated);
    return updated;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('픽 쇼츠 삭제'),
        content: const Text('이 대결을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const _BattleDetailDeleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = BattleMatchEntry(
      id: _previewMatch.id,
      title: _titleController.text.trim().isEmpty
          ? _previewMatch.title
          : _titleController.text.trim(),
      authorId: _previewMatch.authorId,
      authorNickname: _previewMatch.authorNickname,
      leftPostId: _leftPost?.id ?? _previewMatch.leftPostId,
      rightPostId: _rightPost?.id ?? _previewMatch.rightPostId,
      createdAt: _previewMatch.createdAt,
      leftColorValue: HSVColor.fromAHSV(
        1,
        _leftHue,
        0.82,
        0.82,
      ).toColor().toARGB32(),
      rightColorValue: HSVColor.fromAHSV(
        1,
        _rightHue,
        0.82,
        0.82,
      ).toColor().toARGB32(),
      endsAt: _previewMatch.endsAt,
      requiredTitleKey: null,
      leftCustomTitle: _previewMatch.leftCustomTitle,
      rightCustomTitle: _previewMatch.rightCustomTitle,
      leftCustomImageUrl: _previewMatch.leftCustomImageUrl,
      rightCustomImageUrl: _previewMatch.rightCustomImageUrl,
      leftVoterIds: _previewMatch.leftVoterIds,
      rightVoterIds: _previewMatch.rightVoterIds,
    );
    final leftSide = _resolvedSide(true);
    final rightSide = _resolvedSide(false);

    return Scaffold(
      backgroundColor: _battleCanvas,
      appBar: AppBar(
        backgroundColor: _battleCanvas,
        foregroundColor: _battleInk,
        elevation: 0,
        title: const Text('픽 쇼츠 상세'),
        actions: [
          if (_isMine && !_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('수정'),
            ),
          if (_isMine && _editing)
            TextButton(onPressed: _saveEdit, child: const Text('저장')),
          if (_isMine) TextButton(onPressed: _delete, child: const Text('삭제')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _BattleMatchCard(
            match: preview,
            leftSide: leftSide,
            rightSide: rightSide,
            currentUserId: widget.currentUser.id,
            onVote: (match, side) => _vote(side),
            onOpenLeft: _leftPost == null
                ? null
                : () {
                    widget.onOpenPost(_leftPost!);
                  },
            onOpenRight: _rightPost == null
                ? null
                : () {
                    widget.onOpenPost(_rightPost!);
                  },
            onOpenAuthor: () {
              widget.onOpenAuthor(preview.authorId, preview.authorNickname);
            },
            onOpenDetail: () {},
          ),
          const SizedBox(height: 16),
          if (_editing)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _battleLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '대결 수정',
                    style: TextStyle(
                      color: _battleInk,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: '대결 제목'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  if (_usesCommunityPosts) ...[
                    _BattleCreateSlot(
                      label: '왼쪽 조합',
                      post: _leftPost,
                      onTap: () => _pickPost(true),
                    ),
                    const SizedBox(height: 14),
                    _BattleCreateSlot(
                      label: '오른쪽 조합',
                      post: _rightPost,
                      onTap: () => _pickPost(false),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    const Text(
                      '직접 입력 대결은 현재 제목만 수정할 수 있어요.',
                      style: TextStyle(
                        color: _battleSubtle,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BattleSourceModeToggle extends StatelessWidget {
  const _BattleSourceModeToggle({
    required this.sourceMode,
    required this.onChanged,
  });

  final _BattleCreateSourceMode sourceMode;
  final ValueChanged<_BattleCreateSourceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option({
      required _BattleCreateSourceMode value,
      required IconData icon,
      required String label,
    }) {
      final active = sourceMode == value;
      return Expanded(
        child: FilledButton.icon(
          onPressed: () => onChanged(value),
          icon: Icon(icon, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: active
                ? const Color(0xFFDFF3FA)
                : Colors.transparent,
            foregroundColor: active ? const Color(0xFF276A85) : _battleSubtle,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: active ? const Color(0xFFAED9E8) : _battleLine,
              ),
            ),
          ),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(
          value: _BattleCreateSourceMode.community,
          icon: Icons.forum_rounded,
          label: '커뮤니티 불러오기',
        ),
        const SizedBox(width: 10),
        option(
          value: _BattleCreateSourceMode.custom,
          icon: Icons.draw_rounded,
          label: '직접 입력',
        ),
      ],
    );
  }
}

Color _darken(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.withValue((hsv.value * 0.82).clamp(0.0, 1.0)).toColor();
}

String _formatBattleDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}.$month.$day $hour:$minute';
}

String _formatBattleRemaining(DateTime endsAt) {
  final remaining = endsAt.difference(DateTime.now());
  if (remaining.isNegative) return '0분';
  final days = remaining.inDays;
  if (days >= 1) return '$days일';
  final hours = remaining.inHours;
  if (hours >= 1) return '$hours시간';
  final minutes = math.max(1, remaining.inMinutes);
  return '$minutes분';
}

bool _hasEndedToday(DateTime? endsAt) {
  if (endsAt == null) return false;
  final now = DateTime.now();
  if (endsAt.isAfter(now)) return false;
  return endsAt.year == now.year &&
      endsAt.month == now.month &&
      endsAt.day == now.day;
}

String _formatVotes(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final reverseIndex = digits.length - index;
    buffer.write(digits[index]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
