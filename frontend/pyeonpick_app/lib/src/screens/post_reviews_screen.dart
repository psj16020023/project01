import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/post.dart';
import '../models/pyeon_user.dart';

class PostReviewsScreen extends StatefulWidget {
  const PostReviewsScreen({
    super.key,
    required this.post,
    required this.currentUser,
    required this.onAddReview,
    required this.onUpdateReview,
    required this.onDeleteReview,
    this.scrollController,
  });

  final Post post;
  final PyeonUser currentUser;
  final Future<Post> Function(PostReview review) onAddReview;
  final Future<Post> Function(PostReview review) onUpdateReview;
  final Future<Post> Function(PostReview review) onDeleteReview;
  final ScrollController? scrollController;

  @override
  State<PostReviewsScreen> createState() => _PostReviewsScreenState();
}

class _PostReviewsScreenState extends State<PostReviewsScreen> {
  late Post _post;
  bool _sortByRating = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  Future<void> _writeReview() async {
    final review = await showModalBottomSheet<PostReview>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ReviewComposerSheet(currentUser: widget.currentUser),
    );
    if (review == null) return;
    try {
      final updated = await widget.onAddReview(review);
      if (mounted) setState(() => _post = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('후기를 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _openReview(PostReview review) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewDetailPage(
          review: review,
          currentUser: widget.currentUser,
          onEdit: (updatedReview) async {
            final updated = await widget.onUpdateReview(updatedReview);
            if (mounted) setState(() => _post = updated);
          },
          onDelete: () async {
            final updated = await widget.onDeleteReview(review);
            if (mounted) setState(() => _post = updated);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reviews = [..._post.reviews]
      ..sort(
        (a, b) => _sortByRating && a.rating != b.rating
            ? b.rating.compareTo(a.rating)
            : b.createdAt.compareTo(a.createdAt),
      );
    return Material(
      key: const Key('reviews-bottom-sheet'),
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD8DADC),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    '후기 ${reviews.length}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _sortByRating = false),
                    child: Text(
                      '최신순',
                      style: TextStyle(
                        color: !_sortByRating ? AppColors.ink : AppColors.muted,
                        fontWeight: !_sortByRating
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _sortByRating = true),
                    child: Text(
                      '평점순',
                      style: TextStyle(
                        color: _sortByRating ? AppColors.ink : AppColors.muted,
                        fontWeight: _sortByRating
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 20),
                children: reviews.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              '첫 후기를 남겨보세요.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        ),
                      ]
                    : reviews
                          .map(
                            (review) => _ReviewCard(
                              review: review,
                              onTap: () => _openReview(review),
                            ),
                          )
                          .toList(),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xFFF0F1F2),
                    child: Text(
                      widget.currentUser.nickname.isEmpty
                          ? '?'
                          : widget.currentUser.nickname.characters.first,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('review-compose-input'),
                      readOnly: true,
                      onTap: _writeReview,
                      decoration: const InputDecoration(
                        hintText: '후기 남기기...',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _writeReview,
                    tooltip: '후기 쓰기',
                    icon: const Icon(Icons.edit_outlined, size: 21),
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

class ReviewComposerSheet extends StatefulWidget {
  const ReviewComposerSheet({
    super.key,
    required this.currentUser,
    this.initialReview,
    this.pageMode = false,
  });

  final PyeonUser currentUser;
  final PostReview? initialReview;
  final bool pageMode;

  @override
  State<ReviewComposerSheet> createState() => _ReviewComposerSheetState();
}

class ReviewComposerPage extends StatelessWidget {
  const ReviewComposerPage({
    super.key,
    required this.currentUser,
    this.initialReview,
  });

  final PyeonUser currentUser;
  final PostReview? initialReview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      body: SafeArea(
        child: ReviewComposerSheet(
          currentUser: currentUser,
          initialReview: initialReview,
          pageMode: true,
        ),
      ),
    );
  }
}

class _ReviewComposerSheetState extends State<ReviewComposerSheet> {
  final _textController = TextEditingController();
  final _cautionController = TextEditingController();
  final _tags = <String>{};
  double _rating = 3;
  int _sweet = 3;
  int _salty = 3;
  int _spicy = 3;
  int _sour = 3;

  @override
  void initState() {
    super.initState();
    final review = widget.initialReview;
    if (review == null) return;
    _textController.text = review.text;
    _cautionController.text = review.caution;
    _tags.addAll(review.tags);
    _rating = review.rating;
    _sweet = review.sweet;
    _salty = review.salty;
    _spicy = review.spicy;
    _sour = review.sour;
  }

  @override
  void dispose() {
    _textController.dispose();
    _cautionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_textController.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      PostReview(
        id:
            widget.initialReview?.id ??
            'review-${DateTime.now().microsecondsSinceEpoch}',
        authorId: widget.currentUser.id,
        authorNickname: widget.currentUser.nickname,
        text: _textController.text.trim(),
        rating: _rating,
        tags: _tags.toList(),
        sweet: _sweet,
        salty: _salty,
        spicy: _spicy,
        sour: _sour,
        caution: _cautionController.text.trim(),
        createdAt: widget.initialReview?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        widget.pageMode ? 18 : 14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.pageMode
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.pageMode) ...[
                const Center(
                  child: SizedBox(
                    width: 54,
                    child: Divider(thickness: 5, color: Color(0xFFD6E0E6)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initialReview == null ? '후기 쓰기' : '후기 편집',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.ink,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _textController,
                maxLines: 3,
                decoration: _reviewInputDecoration('간단한 후기를 적어 주세요'),
              ),
              const SizedBox(height: 16),
              _ScorePicker(
                label: '평점',
                value: _rating.round(),
                onChanged: (value) =>
                    setState(() => _rating = value.toDouble()),
                star: true,
              ),
              const SizedBox(height: 16),
              const Text(
                '어디에 해당하나요?',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: communityReviewTags.map((tag) {
                  final selected = _tags.contains(tag);
                  return FilterChip(
                    selected: selected,
                    label: Text(tag),
                    onSelected: (_) => setState(() {
                      selected ? _tags.remove(tag) : _tags.add(tag);
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              _ScorePicker(
                label: '달달',
                value: _sweet,
                onChanged: (value) => setState(() => _sweet = value),
              ),
              _ScorePicker(
                label: '짭짤',
                value: _salty,
                onChanged: (value) => setState(() => _salty = value),
              ),
              _ScorePicker(
                label: '매운',
                value: _spicy,
                onChanged: (value) => setState(() => _spicy = value),
              ),
              _ScorePicker(
                label: '새콤',
                value: _sour,
                onChanged: (value) => setState(() => _sour = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cautionController,
                maxLines: 2,
                decoration: _reviewInputDecoration('주의사항이 있다면 적어 주세요'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.skyBlue,
                    foregroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '후기 등록',
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

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.star = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool star;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
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
                star
                    ? (score <= value
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded)
                    : (score <= value
                          ? Icons.circle_rounded
                          : Icons.circle_outlined),
                color: star ? const Color(0xFFF4B942) : const Color(0xFF79B9C9),
                size: star ? 27 : 18,
              ),
            );
          }),
          Text(
            '$value/5',
            style: const TextStyle(
              color: Color(0xFF708596),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        5,
        (index) => Icon(
          index < value.round()
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          color: const Color(0xFFF4B942),
          size: 25,
        ),
      ),
    );
  }
}

class _TasteBar extends StatelessWidget {
  const _TasteBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = <String, Color>{
      '달달': const Color(0xFFFF91B7),
      '짭짤': const Color(0xFF58C7D6),
      '매운': const Color(0xFFFF765F),
      '새콤': const Color(0xFFF0CF39),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 17,
                value: value / 5,
                backgroundColor: const Color(0xFFEDF2F4),
                valueColor: AlwaysStoppedAnimation(colors[label]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              value == 0 ? '-' : value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.onTap});
  final PostReview review;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = review.createdAt.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFF0F1F2),
            child: Text(
              review.authorNickname.isEmpty
                  ? '?'
                  : review.authorNickname.characters.first,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${review.authorNickname} · ${date.month}.${date.day}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  review.text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFF8A9298),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      review.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    if (review.tags.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          review.tags.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (review.caution.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      review.caution,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              onPressed: onTap,
              tooltip: '후기 상세',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 19,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewDetailPage extends StatefulWidget {
  const ReviewDetailPage({
    super.key,
    required this.review,
    required this.currentUser,
    required this.onEdit,
    required this.onDelete,
  });

  final PostReview review;
  final PyeonUser currentUser;
  final Future<void> Function(PostReview review) onEdit;
  final Future<void> Function() onDelete;

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<ReviewDetailPage> {
  late PostReview _review;

  @override
  void initState() {
    super.initState();
    _review = widget.review;
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<PostReview>(
      MaterialPageRoute<PostReview>(
        builder: (context) => ReviewComposerPage(
          currentUser: widget.currentUser,
          initialReview: _review,
        ),
      ),
    );
    if (updated == null) return;
    await widget.onEdit(updated);
    if (mounted) setState(() => _review = updated);
  }

  Future<void> _delete() async {
    await widget.onDelete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isMine = _review.authorId == widget.currentUser.id;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        title: const Text(
          '후기 세부사항',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (isMine)
            PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? _edit() : _delete(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('후기 편집')),
                PopupMenuItem(value: 'delete', child: Text('후기 삭제')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE3EDF2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFE7F2D5),
                      child: Text(
                        _review.authorNickname.isEmpty
                            ? '?'
                            : _review.authorNickname.substring(0, 1),
                        style: const TextStyle(
                          color: Color(0xFF668318),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _review.authorNickname,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            isMine
                                ? '@${widget.currentUser.username} · 내 후기'
                                : '편pick 회원 · ${_review.createdAtLabel}',
                            style: const TextStyle(
                              color: Color(0xFF7C90A1),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Stars(value: _review.rating),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  _review.text,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                ),
                if (_review.tags.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _review.tags
                        .map((tag) => Chip(label: Text(tag)))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 24),
                _TasteBar(label: '달달', value: _review.sweet.toDouble()),
                _TasteBar(label: '짭짤', value: _review.salty.toDouble()),
                _TasteBar(label: '매운', value: _review.spicy.toDouble()),
                _TasteBar(label: '새콤', value: _review.sour.toDouble()),
                if (_review.caution.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1ED),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '주의사항\n${_review.caution}',
                      style: const TextStyle(
                        color: Color(0xFFB75342),
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _reviewInputDecoration(String hint) {
  return InputDecoration(
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
  );
}
