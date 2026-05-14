import 'dart:convert';

import '../data/mock_posts.dart';
import '../data/product_catalog.dart' as catalog;
import '../models/post.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'post_repository.dart';

class MockPostRepository implements PostRepository {
  MockPostRepository() : _posts = mockPosts.map((post) => post.copyWith()).toList() {
    _applyTopFiveBadges();
  }

  final List<Post> _posts;

  @override
  Future<void> addComment(String id, String text) async {
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) return;

    final post = _posts[index];
    _posts[index] = post.copyWith(
      comments: [
        ...post.comments,
        PostComment(text: text.trim(), createdAt: DateTime.now()),
      ],
    );
  }

  @override
  Future<void> createPost(PostDraft draft) async {
    final now = DateTime.now();
    _posts.insert(
      0,
      Post(
        id: 'local-${now.microsecondsSinceEpoch}',
        title: draft.title.isEmpty ? '제목 없는 꿀조합' : draft.title,
        content: draft.content,
        priceMin: draft.priceMin,
        priceMax: draft.priceMax,
        categories: draft.categories,
        likes: 0,
        comments: const [],
        createdAt: now,
        imageData: draft.imageBytes == null ? null : base64Encode(draft.imageBytes!),
        imageUrl: null,
        likedByMe: false,
        topFiveEnteredAt: null,
      ),
    );
    _applyTopFiveBadges();
  }

  @override
  Future<List<Post>> fetchPosts({
    String? query,
    int? minPrice,
    int? maxPrice,
    required SortMode sortMode,
  }) async {
    final normalized = (query ?? '').trim().toLowerCase();

    final filtered = _posts.where((post) {
      final matchesQuery = normalized.isEmpty
          ? true
          : normalized.startsWith('#')
              ? post.categories.any((category) => category.toLowerCase().contains(normalized.substring(1)))
              : post.title.toLowerCase().contains(normalized);

      final matchesMin = minPrice == null || post.priceMax >= minPrice;
      final matchesMax = maxPrice == null || post.priceMin <= maxPrice;
      return matchesQuery && matchesMin && matchesMax;
    }).toList();

    filtered.sort((a, b) {
      if (sortMode == SortMode.popular) {
        return b.likes - a.likes != 0 ? b.likes - a.likes : b.createdAt.compareTo(a.createdAt);
      }
      return b.createdAt.compareTo(a.createdAt);
    });

    return filtered.map((post) => post.copyWith()).toList();
  }

  @override
  Future<void> toggleLike(String id) async {
    final index = _posts.indexWhere((post) => post.id == id);
    if (index < 0) return;

    final post = _posts[index];
    final toggled = !post.likedByMe;
    _posts[index] = post.copyWith(
      likedByMe: toggled,
      likes: toggled ? post.likes + 1 : (post.likes > 0 ? post.likes - 1 : 0),
    );
    _applyTopFiveBadges();
  }

  @override
  Future<ProductLookupResult> lookupProductByBarcode(String barcode) async {
    final result = catalog.ProductCatalog.resolve(barcode);
    return ProductLookupResult(
      officialName: result.productName,
      scannedCode: result.scannedCode,
      source: result.matchedFromCatalog ? 'mock-catalog' : 'manual-needed',
      cached: true,
      store: '편pick 샘플',
    );
  }

  void _applyTopFiveBadges() {
    final ranked = [..._posts]
      ..sort((a, b) => b.likes - a.likes != 0 ? b.likes - a.likes : b.createdAt.compareTo(a.createdAt));
    final topIds = ranked.take(5).map((post) => post.id).toSet();
    final now = DateTime.now();

    for (var index = 0; index < _posts.length; index += 1) {
      final post = _posts[index];
      if (topIds.contains(post.id) && post.topFiveEnteredAt == null) {
        _posts[index] = post.copyWith(topFiveEnteredAt: now);
      }
    }
  }
}
