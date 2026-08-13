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
  });

  final Post post;
  final PyeonUser currentUser;
  final Future<Post> Function(PostReview review) onAddReview;
  final Future<Post> Function(PostReview review) onUpdateReview;
  final Future<Post> Function(PostReview review) onDeleteReview;

  @override
  State<PostReviewsScreen> createState() => _PostReviewsScreenState();
}

class _PostReviewsScreenState extends State<PostReviewsScreen> {
  late Post _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  Future<void> _writeReview() async {
    final review = await Navigator.of(context).push<PostReview>(
      MaterialPageRoute<PostReview>(
        builder: (context) =>
            ReviewComposerPage(currentUser: widget.currentUser),
      ),
    );
    if (review == null) return;
    final updated = await widget.onAddReview(review);
    if (!mounted) return;
    setState(() => _post = updated);
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

  double _average(double Function(PostReview review) value) {
    if (_post.reviews.isEmpty) return 0;
    return _post.reviews.fold<double>(0, (sum, item) => sum + value(item)) /
        _post.reviews.length;
  }

  @override
  Widget build(BuildContext context) {
    final tagCounts = <String, int>{
      for (final tag in communityReviewTags) tag: 0,
    };
    for (final review in _post.reviews) {
      for (final tag in review.tags) {
        if (tagCounts.containsKey(tag)) tagCounts[tag] = tagCounts[tag]! + 1;
      }
    }
    final rankedTags = tagCounts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count != 0
            ? count
            : communityReviewTags
                  .indexOf(a.key)
                  .compareTo(communityReviewTags.indexOf(b.key));
      });
    final rating = _average((review) => review.rating);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        title: const Text(
          '후기 모아보기',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _writeReview,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.rate_review_rounded),
        label: const Text(
          '후기 쓰기',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
        children: [
          Text(
            _post.title,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
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
                const Text(
                  '후기 평균 데이터',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _post.reviews.isEmpty
                      ? '아직 등록된 후기가 없어요.'
                      : '후기 ${_post.reviews.length}개 기준',
                  style: const TextStyle(
                    color: Color(0xFF768A9B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      rating == 0 ? '-' : rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Stars(value: rating),
                  ],
                ),
                const SizedBox(height: 22),
                _TasteBar(
                  label: '달달',
                  value: _average((item) => item.sweet.toDouble()),
                ),
                _TasteBar(
                  label: '짭짤',
                  value: _average((item) => item.salty.toDouble()),
                ),
                _TasteBar(
                  label: '매운',
                  value: _average((item) => item.spicy.toDouble()),
                ),
                _TasteBar(
                  label: '새콤',
                  value: _average((item) => item.sour.toDouble()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E7),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '후기 태그 순위',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                ...rankedTags.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(
                            '${entry.key + 1}등',
                            style: const TextStyle(
                              color: Color(0xFF668318),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value.key,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value.value}표',
                          style: const TextStyle(
                            color: Color(0xFF718394),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '모든 후기',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (_post.reviews.isEmpty)
            const Text(
              '첫 번째 후기를 남겨보세요.',
              style: TextStyle(
                color: Color(0xFF7D90A0),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ..._post.reviews.reversed.map(
              (review) =>
                  _ReviewCard(review: review, onTap: () => _openReview(review)),
            ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5EDF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    review.authorNickname,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _Stars(value: review.rating),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              review.text,
              style: const TextStyle(
                color: AppColors.ink,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (review.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: review.tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (review.caution.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '주의: ${review.caution}',
                style: const TextStyle(
                  color: Color(0xFFD0614E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                '세부사항 보기 ›',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
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
    filled: true,
    fillColor: const Color(0xFFF5F8FA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide.none,
    ),
  );
}
