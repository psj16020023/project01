import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_colors.dart';
import '../core/app_environment.dart';
import '../models/app_tab.dart';
import '../models/post.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import '../repositories/post_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.environment,
  });

  final PostRepository repository;
  final AppEnvironment environment;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minFilterController = TextEditingController();
  final TextEditingController _maxFilterController = TextEditingController();

  AppTab _selectedTab = AppTab.communication;
  SortMode _sortMode = SortMode.latest;
  bool _loading = true;
  String? _error;
  List<Post> _posts = <Post>[];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final posts = await widget.repository.fetchPosts(
        query: _searchController.text.trim(),
        minPrice: int.tryParse(_minFilterController.text.trim()),
        maxPrice: int.tryParse(_maxFilterController.text.trim()),
        sortMode: _sortMode,
      );

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.environment.dataMode == DataMode.remote
            ? '원격 서버에서 게시글을 불러오지 못했어요. API 주소나 서버 상태를 확인해 주세요.'
            : '게시글을 불러오지 못했어요.';
      });
    }
  }

  Future<void> _toggleLike(Post post) async {
    await widget.repository.toggleLike(post.id);
    await _loadPosts();
  }

  Future<void> _addComment(Post post, String text) async {
    await widget.repository.addComment(post.id, text);
    await _loadPosts();
  }

  Future<void> _openComposer() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ComposerSheet(repository: widget.repository),
    );
    if (created == true) {
      await _loadPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _selectedTab == AppTab.communication
          ? FloatingActionButton(
              onPressed: _openComposer,
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
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '편pick! 오늘은 뭘 사먹을까?',
                      style: TextStyle(
                        color: AppColors.limeDeep,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '잘 pick해 주는 편의점 음식 추천앱 편pick!',
                      style: TextStyle(
                        color: AppColors.limeDeep,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.environment.dataMode == DataMode.remote
                          ? '연결 모드: 원격 API'
                          : '연결 모드: 앱 내 시드 데이터',
                      style: const TextStyle(
                        color: Color(0xFF5D7A1C),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                        child: FeatureTabs(
                          selectedTab: _selectedTab,
                          onChanged: (tab) => setState(() => _selectedTab = tab),
                        ),
                      ),
                      Container(height: 1.5, color: AppColors.lime),
                      Expanded(
                        child: _selectedTab == AppTab.communication
                            ? CommunicationBody(
                                loading: _loading,
                                error: _error,
                                posts: _posts,
                                searchController: _searchController,
                                minFilterController: _minFilterController,
                                maxFilterController: _maxFilterController,
                                sortMode: _sortMode,
                                onReload: _loadPosts,
                                onChangeSort: (sortMode) {
                                  setState(() => _sortMode = sortMode);
                                  _loadPosts();
                                },
                                onToggleLike: _toggleLike,
                                onAddComment: _addComment,
                              )
                            : PlaceholderPage(tab: _selectedTab),
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

class CommunicationBody extends StatelessWidget {
  const CommunicationBody({
    super.key,
    required this.loading,
    required this.error,
    required this.posts,
    required this.searchController,
    required this.minFilterController,
    required this.maxFilterController,
    required this.sortMode,
    required this.onReload,
    required this.onChangeSort,
    required this.onToggleLike,
    required this.onAddComment,
  });

  final bool loading;
  final String? error;
  final List<Post> posts;
  final TextEditingController searchController;
  final TextEditingController minFilterController;
  final TextEditingController maxFilterController;
  final SortMode sortMode;
  final Future<void> Function() onReload;
  final ValueChanged<SortMode> onChangeSort;
  final Future<void> Function(Post post) onToggleLike;
  final Future<void> Function(Post post, String text) onAddComment;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.limeDeep));
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
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

    return RefreshIndicator(
      color: AppColors.limeDeep,
      onRefresh: onReload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          Toolbar(
            searchController: searchController,
            minFilterController: minFilterController,
            maxFilterController: maxFilterController,
            sortMode: sortMode,
            onChangedSortMode: onChangeSort,
            onSearch: onReload,
          ),
          const SizedBox(height: 16),
          if (posts.isEmpty)
            const EmptyState()
          else
            ...posts.map(
              (post) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  post: post,
                  onToggleLike: () => onToggleLike(post),
                  onAddComment: (text) => onAddComment(post, text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FeatureTabs extends StatelessWidget {
  const FeatureTabs({super.key, required this.selectedTab, required this.onChanged});

  final AppTab selectedTab;
  final ValueChanged<AppTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = <({AppTab tab, String label})>[
      (tab: AppTab.communication, label: '커뮤니케이션'),
      (tab: AppTab.bot, label: '편봇'),
      (tab: AppTab.health, label: '건강계산기'),
      (tab: AppTab.scanner, label: '편의점 스캐너'),
      (tab: AppTab.profile, label: '내 정보'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((item) {
          final active = selectedTab == item.tab;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => onChanged(item.tab),
              child: Container(
                width: 78,
                height: 78,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.activeYellow : AppColors.softYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: item.label.length > 6 ? 11.5 : 12.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF6E5C12),
                    height: 1.2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class Toolbar extends StatelessWidget {
  const Toolbar({
    super.key,
    required this.searchController,
    required this.minFilterController,
    required this.maxFilterController,
    required this.sortMode,
    required this.onChangedSortMode,
    required this.onSearch,
  });

  final TextEditingController searchController;
  final TextEditingController minFilterController;
  final TextEditingController maxFilterController;
  final SortMode sortMode;
  final ValueChanged<SortMode> onChangedSortMode;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: inputDecoration('제목 검색 또는 #달달 처럼 카테고리 검색').copyWith(
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.ink),
                ),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const SizedBox(width: 10),
            SortSelector(sortMode: sortMode, onChanged: onChangedSortMode),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: minFilterController,
                keyboardType: TextInputType.number,
                decoration: inputDecoration('____'),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('~', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink)),
            ),
            Expanded(
              child: TextField(
                controller: maxFilterController,
                keyboardType: TextInputType.number,
                decoration: inputDecoration('____'),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onSearch,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.lime,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('검색'),
            ),
          ],
        ),
      ],
    );
  }
}

InputDecoration inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFB5BDC8), fontWeight: FontWeight.w600),
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
  const SortSelector({super.key, required this.sortMode, required this.onChanged});

  final SortMode sortMode;
  final ValueChanged<SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, SortMode mode) {
      final active = sortMode == mode;
      return GestureDetector(
        onTap: () => onChanged(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.navy : const Color(0xFFF5F9FB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF8CA0B3),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E4EA)),
      ),
      child: Column(
        children: [
          chip('최신순', SortMode.latest),
          const SizedBox(height: 4),
          chip('인기순', SortMode.popular),
        ],
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onToggleLike,
    required this.onAddComment,
  });

  final Post post;
  final Future<void> Function() onToggleLike;
  final Future<void> Function(String text) onAddComment;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool expanded = false;
  bool commentsVisible = false;
  final TextEditingController commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEEF4F7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.createdAtLabel,
            style: const TextStyle(color: Color(0xFF8CA0B3), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => expanded = !expanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: _buildPostImage(post),
                  ),
                ),
                if (post.topFiveEnteredAt != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(
                      offset: const Offset(0, -4),
                      child: ClipPath(
                        clipper: BookmarkClipper(),
                        child: Container(
                          width: 76,
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                          color: const Color(0xFF2F7EF0),
                          child: Column(
                            children: [
                              const Text('인기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(
                                post.topFiveDateLabel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7D8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        post.priceLabel,
                        style: const TextStyle(color: Color(0xFF688716), fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: post.categories
                      .map(
                        (category) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F9FB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '#$category',
                            style: const TextStyle(color: Color(0xFF5C748D), fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFEDF2F5)),
            const SizedBox(height: 16),
            Text(
              post.content.isEmpty ? '사진 중심 게시글입니다.' : post.content,
              style: const TextStyle(height: 1.7, color: AppColors.ink, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ActionChipButton(
                  label: '${post.likedByMe ? '♥' : '♡'} 하트 ${post.likes}',
                  active: post.likedByMe,
                  onTap: widget.onToggleLike,
                ),
                const SizedBox(width: 10),
                ActionChipButton(
                  label: '댓글 ${post.comments.length}',
                  onTap: () async => setState(() => commentsVisible = !commentsVisible),
                ),
              ],
            ),
            if (commentsVisible) ...[
              const SizedBox(height: 14),
              ...post.comments.map(
                (comment) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      comment.text,
                      style: const TextStyle(color: Color(0xFF5D7286), fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: TextField(controller: commentController, decoration: inputDecoration('댓글을 입력해 주세요.'))),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () async {
                      final value = commentController.text.trim();
                      if (value.isEmpty) return;
                      await widget.onAddComment(value);
                      commentController.clear();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('등록'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

Widget _buildPostImage(Post post) {
  if (post.imageData != null && post.imageData!.isNotEmpty) {
    return Image.memory(
      base64Decode(post.imageData!),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => GradientPhoto(title: post.title),
    );
  }

  if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
    return Image.network(
      post.imageUrl!,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            GradientPhoto(title: post.title),
            const Center(child: CircularProgressIndicator(color: AppColors.limeDeep)),
          ],
        );
      },
      errorBuilder: (_, _, _) => GradientPhoto(title: post.title),
    );
  }

  return GradientPhoto(title: post.title);
}

class GradientPhoto extends StatelessWidget {
  const GradientPhoto({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4AE), Color(0xFFCEEFFF), Color(0xFFE3FFD1)],
        ),
      ),
      padding: const EdgeInsets.all(18),
      alignment: Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(224),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          title,
          style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }
}

class ActionChipButton extends StatelessWidget {
  const ActionChipButton({
    super.key,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFE7EC) : const Color(0xFFF6F9FC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFE44566) : const Color(0xFF52697F),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class ComposerSheet extends StatefulWidget {
  const ComposerSheet({super.key, required this.repository});

  final PostRepository repository;

  @override
  State<ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<ComposerSheet> {
  final ImagePicker picker = ImagePicker();
  final TextEditingController titleController = TextEditingController();
  final TextEditingController contentController = TextEditingController();
  final TextEditingController priceMinController = TextEditingController();
  final TextEditingController priceMaxController = TextEditingController();
  final TextEditingController customCategoryController = TextEditingController();
  final Set<String> selectedCategories = <String>{};
  final List<String> baseCategories = const ['달달', '매콤', '신', '짭잘', '건강'];

  Uint8List? selectedImageBytes;
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    priceMinController.dispose();
    priceMaxController.dispose();
    customCategoryController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 84);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => selectedImageBytes = bytes);
  }

  Future<void> scanProductCode() async {
    final rawValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProductScannerSheet(),
    );

    if (!mounted || rawValue == null || rawValue.trim().isEmpty) return;

    try {
      final result = await widget.repository.lookupProductByBarcode(rawValue);
      if (!mounted) return;

      setState(() {
        titleController.text = result.officialName;
        titleController.selection = TextSelection.collapsed(offset: titleController.text.length);
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
    final location = result.store == null || result.store!.isEmpty ? '' : ' · ${result.store}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.cached
              ? '등록된 상품명을 불러왔어요$location'
              : '외부 상품 정보에서 정식 상품명을 찾았어요$location',
        ),
      ),
    );
  }

  Future<void> submit() async {
    final title = titleController.text.trim();
    final content = contentController.text.trim();
    final minPrice = int.tryParse(priceMinController.text.trim());
    final maxPrice = int.tryParse(priceMaxController.text.trim());
    final customCategories = customCategoryController.text
        .split(RegExp(r'[\s,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => item.startsWith('#') ? item.substring(1) : item)
        .where((item) => item.isNotEmpty)
        .toList();
    final allCategories = <String>{...selectedCategories, ...customCategories}.toList();

    final hasImage = selectedImageBytes != null;
    final hasText = title.isNotEmpty && content.isNotEmpty;

    if (!hasImage && !hasText) {
      setState(() => error = '사진 또는 큰 제목과 자세한 내용을 모두 입력해야 해요.');
      return;
    }
    if (minPrice == null || maxPrice == null || minPrice <= 0 || maxPrice < minPrice) {
      setState(() => error = '가격 범위를 올바르게 입력해 주세요.');
      return;
    }
    if (allCategories.isEmpty) {
      setState(() => error = '카테고리를 하나 이상 선택하거나 직접 만들어 주세요.');
      return;
    }

    setState(() {
      submitting = true;
      error = null;
    });

    try {
      await widget.repository.createPost(
        PostDraft(
          title: title.isEmpty ? '제목 없는 꿀조합' : title,
          content: content,
          priceMin: minPrice,
          priceMax: maxPrice,
          categories: allCategories,
          imageBytes: selectedImageBytes,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = '게시하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('꿀조합 올리기', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 22)),
                          SizedBox(height: 8),
                          Text(
                            '사진 또는 제목+내용을 입력하고 가격대와 카테고리를 정해 주세요.',
                            style: TextStyle(color: Color(0xFF8CA0B3), fontWeight: FontWeight.w600),
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
                GestureDetector(
                  onTap: pickImage,
                  child: Container(
                    height: 230,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F8FB),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFCEDBE6)),
                    ),
                    child: selectedImageBytes == null
                        ? const Center(
                            child: Text(
                              '사진 첨부\n터치해서 이미지 선택',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF9DB0C0), fontWeight: FontWeight.w700, height: 1.6),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.memory(selectedImageBytes!, fit: BoxFit.cover),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleController,
                  decoration: inputDecoration('예: 딸기우유 + 프레첼 + 젤리 조합').copyWith(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton.icon(
                        onPressed: scanProductCode,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          backgroundColor: const Color(0xFFEAF2FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('QR', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 96, minHeight: 44),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'QR 버튼으로 상품 QR 또는 바코드를 찍으면 등록된 상품명은 자동으로 제목에 들어가요.',
                  style: TextStyle(color: Color(0xFF7C90A2), fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: inputDecoration('왜 맛있는지, 어떤 제품인지, 먹는 순서까지 자유롭게 적어주세요.'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceMinController,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('____'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('~', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: priceMaxController,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('____'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: baseCategories.map((category) {
                    final active = selectedCategories.contains(category);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (active) {
                            selectedCategories.remove(category);
                          } else {
                            selectedCategories.add(category);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? AppColors.lime : const Color(0xFFFBFEF4),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: active ? AppColors.lime : const Color(0xFFD5E3CB)),
                        ),
                        child: Text(
                          '#$category',
                          style: TextStyle(
                            color: active ? Colors.white : const Color(0xFF69831D),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customCategoryController,
                  decoration: inputDecoration("#을 치고 '기발한' 같은 새 카테고리"),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Color(0xFFD44444), fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: submitting ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.lime,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(submitting ? '게시 중...' : '게시'),
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

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDF3F7)),
      ),
      child: const Column(
        children: [
          Text('검색 결과가 없어요.', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 20)),
          SizedBox(height: 8),
          Text(
            '제목, #카테고리, 가격대를 조금 다르게 입력해 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF647B91), fontWeight: FontWeight.w600, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class ProductScannerSheet extends StatefulWidget {
  const ProductScannerSheet({super.key});

  @override
  State<ProductScannerSheet> createState() => _ProductScannerSheetState();
}

class _ProductScannerSheetState extends State<ProductScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );

  bool _handled = false;
  bool _showGuide = true;
  bool _starting = true;
  String? _scannerError;
  Timer? _guideTimer;

  @override
  void initState() {
    super.initState();
    _guideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showGuide = false);
    });
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startScanner());
      });
    } else {
      _starting = false;
    }
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startScanner() async {
    setState(() {
      _starting = true;
      _scannerError = null;
    });

    try {
      try {
        await _controller.stop();
      } catch (_) {}

      await _controller.start(cameraDirection: CameraFacing.back);
      if (!mounted) return;
      setState(() => _starting = false);
    } on MobileScannerException catch (error) {
      if (kIsWeb) {
        try {
          await _controller.start(cameraDirection: CameraFacing.front);
          if (!mounted) return;
          setState(() => _starting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('후면 카메라 시작이 어려워 기본 카메라로 다시 열었어요.')),
          );
          return;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _starting = false;
        _scannerError = error.errorDetails?.message ?? error.errorCode.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _scannerError = '카메라를 시작하지 못했어요. 브라우저 권한을 확인해 주세요.';
      });
    }
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(rawValue);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF8FF), Colors.white],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '상품 스캔',
                          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 22),
                        ),
                        const SizedBox(height: 6),
                        AnimatedOpacity(
                          opacity: _showGuide ? 1 : 0,
                          duration: const Duration(milliseconds: 500),
                          child: const Text(
                            '상품 QR이나 바코드를 화면 안에 맞춰 주세요.',
                            style: TextStyle(color: Color(0xFF64839B), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navy,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFD7EEF9), width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120D2742),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _controller,
                            onDetect: _handleDetection,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error) {
                              return _ScannerStatusCard(
                                title: '카메라를 열지 못했어요',
                                message: error.errorCode.message,
                                onRetry: _startScanner,
                                onShowHelp: _showPermissionHelp,
                              );
                            },
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x330C233D), Color(0x110C233D)],
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFA8DFFF), width: 3),
                                borderRadius: BorderRadius.circular(26),
                                color: Colors.transparent,
                              ),
                              margin: const EdgeInsets.symmetric(horizontal: 26, vertical: 52),
                            ),
                          ),
                          if (_starting)
                            const _ScannerLoadingCard(),
                          if (kIsWeb && !_starting && _scannerError == null && !_controller.value.isRunning)
                            Positioned.fill(
                              child: _ScannerStatusCard(
                                title: '카메라를 켜고 바코드를 스캔해 주세요',
                                message: '모바일 웹에서는 카메라 시작을 직접 눌러야 권한이 정상 동작하는 경우가 많아요.',
                                onRetry: _startScanner,
                                onShowHelp: _showPermissionHelp,
                                retryLabel: '카메라 켜기',
                              ),
                            ),
                          if (_scannerError != null)
                            Positioned.fill(
                              child: _ScannerStatusCard(
                                title: '카메라를 시작하지 못했어요',
                                message: _scannerError!,
                                onRetry: _startScanner,
                                onShowHelp: _showPermissionHelp,
                              ),
                            ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 18,
                            child: IgnorePointer(
                              ignoring: !_showGuide,
                              child: AnimatedOpacity(
                                opacity: _showGuide ? 1 : 0,
                                duration: const Duration(milliseconds: 700),
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0xEFFFFFFF),
                                    borderRadius: BorderRadius.all(Radius.circular(18)),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Text(
                                      '등록된 상품은 정식 상품명이 자동 입력되고, 처음 보는 바코드는 직접 수정해서 올릴 수 있어요.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w800,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPermissionHelp() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            '카메라 권한 확인',
            style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            '브라우저에서 한 번 거부된 카메라 권한은 웹페이지가 직접 허용으로 바꿀 수 없어요.\n\n'
            '1. 주소창 옆 자물쇠 또는 사이트 정보 버튼 누르기\n'
            '2. 카메라 권한을 허용으로 변경하기\n'
            '3. 이 화면으로 돌아와 "다시 시도" 누르기\n\n'
            '인앱 브라우저에서는 카메라가 막히는 경우가 많으니 Safari나 Chrome에서 여는 것이 더 안정적입니다.',
            style: TextStyle(color: Color(0xFF5E7891), fontWeight: FontWeight.w600, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerLoadingCard extends StatelessWidget {
  const _ScannerLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x330B223A),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xEEFFFFFF),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2.6),
                ),
                SizedBox(height: 12),
                Text(
                  '카메라 준비 중...',
                  style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerStatusCard extends StatelessWidget {
  const _ScannerStatusCard({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onShowHelp,
    this.retryLabel = '다시 시도',
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onShowHelp;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x660B223A),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD7EEF9)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: AppColors.navy, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64839B), fontWeight: FontWeight.w600, height: 1.5),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFBFE8FF),
                  foregroundColor: AppColors.navy,
                ),
                child: Text(retryLabel),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onShowHelp,
                child: const Text('권한 확인 방법'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final title = switch (tab) {
      AppTab.bot => '편봇',
      AppTab.health => '건강계산기',
      AppTab.scanner => '편의점 스캐너',
      AppTab.profile => '내 정보',
      AppTab.communication => '커뮤니케이션',
    };

    final description = switch (tab) {
      AppTab.bot => '개인 취향과 예산을 바탕으로 오늘 먹기 좋은 편의점 조합을 추천해주는 AI 공간입니다.',
      AppTab.health => '칼로리, 단백질, 당류, 나트륨을 빠르게 계산해 조합의 균형을 보는 기능입니다.',
      AppTab.scanner => '주변 편의점과 원하는 조합의 재고 가능성을 함께 찾는 기능입니다.',
      AppTab.profile => '좋아요, 저장한 글, 내가 쓴 글과 개인 설정을 관리하는 공간입니다.',
      AppTab.communication => '',
    };

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFEDF3F7)),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 24, offset: const Offset(0, 14)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 24)),
              const SizedBox(height: 10),
              Text(description, style: const TextStyle(color: Color(0xFF647B91), height: 1.7, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class BookmarkClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 14)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
