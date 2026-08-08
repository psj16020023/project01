import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/post.dart';
import '../models/post_feature_index.dart';
import '../models/post_draft.dart';
import '../models/post_page.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'post_repository.dart';

class RemotePostRepository implements PostRepository {
  RemotePostRepository({required this.baseUrl});

  final String baseUrl;

  @override
  Future<Post> addReview(String id, PostReview review) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$id/reviews'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(review.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('후기 등록 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<Post> updateReview(String postId, PostReview review) async {
    final response = await http.put(
      Uri.parse('$baseUrl/posts/$postId/reviews/${review.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(review.toJson()),
    );
    if (response.statusCode != 200) throw Exception('후기 수정 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<Post> deleteReview(
    String postId,
    String reviewId, {
    required String authorId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/posts/$postId/reviews/$reviewId',
    ).replace(queryParameters: {'authorId': authorId});
    final response = await http.delete(uri);
    if (response.statusCode != 200) throw Exception('후기 삭제 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<Post> addComment(
    String id,
    String text, {
    required String authorId,
    required String authorNickname,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$id/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'authorId': authorId,
        'authorNickname': authorNickname,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('댓글 등록 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<void> createPost(PostDraft draft) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'authorId': draft.authorId,
        'authorNickname': draft.authorNickname,
        'title': draft.title,
        'content': draft.content,
        'priceMin': draft.priceMin,
        'priceMax': draft.priceMax,
        'categories': draft.categories,
        'imageDatas': draft.imageBytes.map(base64Encode).toList(),
        'imageUrls': draft.imageUrls,
        'details': draft.details.toJson(),
        'calories': draft.calories,
        'rating': draft.rating,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('게시글 작성 실패');
    }
  }

  @override
  Future<void> deletePost(String id, String authorId) async {
    final uri = Uri.parse(
      '$baseUrl/posts/$id',
    ).replace(queryParameters: {'authorId': authorId});
    final response = await http.delete(uri);
    if (response.statusCode != 200) {
      throw Exception('게시글 삭제 실패');
    }
  }

  @override
  Future<PostPage> fetchPosts({
    String? query,
    List<String>? selectedTags,
    int? minPrice,
    int? maxPrice,
    String? likedGenderMajority,
    String? currentUserId,
    String? cursor,
    int? limit,
    required SortMode sortMode,
  }) async {
    final uri = Uri.parse('$baseUrl/posts').replace(
      queryParameters: {
        if (query != null && query.isNotEmpty) 'query': query,
        if (selectedTags != null && selectedTags.isNotEmpty)
          'tags': selectedTags.join(','),
        if (minPrice != null) 'minPrice': '$minPrice',
        if (maxPrice != null) 'maxPrice': '$maxPrice',
        if (likedGenderMajority != null && likedGenderMajority.isNotEmpty)
          'likedGenderMajority': likedGenderMajority,
        if (currentUserId != null && currentUserId.isNotEmpty)
          'viewerId': currentUserId,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
        'sort': switch (sortMode) {
          SortMode.latest => 'latest',
          SortMode.popular => 'popular',
          SortMode.worst => 'worst',
        },
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('게시글 조회 실패');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['posts'] as List<dynamic>;
    return PostPage(
      posts: items
          .map((item) => Post.fromJson(item as Map<String, dynamic>))
          .toList(),
      hasMore: json['hasMore'] as bool? ?? false,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  @override
  Future<List<PostFeatureInfo>> fetchPostFeatureIndex() async {
    final response = await http.get(Uri.parse('$baseUrl/posts/feature-index'));
    if (response.statusCode != 200) {
      throw Exception('게시글 기능 인덱스 조회 실패');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['posts'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .map((item) => PostFeatureInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Post>> fetchPostCatalog({String? currentUserId}) async {
    final uri = Uri.parse('$baseUrl/posts/catalog').replace(
      queryParameters: {
        if (currentUserId != null && currentUserId.isNotEmpty)
          'viewerId': currentUserId,
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('게시글 카탈로그 조회 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['posts'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .map((item) => Post.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PostAudienceStats> fetchPostAudienceStats(String postId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$postId/audience'),
    );
    if (response.statusCode != 200) {
      throw Exception('게시글 성비 조회 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PostAudienceStats.fromJson(json);
  }

  @override
  Future<Post> toggleLike(String id, String currentUserId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$id/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': currentUserId}),
    );
    if (response.statusCode != 200) {
      throw Exception('좋아요 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<Post> toggleDislike(String id, String currentUserId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$id/dislike'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': currentUserId}),
    );
    if (response.statusCode != 200) {
      throw Exception('싫어요 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<ProductLookupResult> lookupProductByBarcode(String barcode) async {
    final normalized = barcode.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final response = await http.get(
      Uri.parse('$baseUrl/products/lookup/$normalized'),
    );
    if (response.statusCode != 200) {
      throw Exception('상품 조회 실패');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ProductLookupResult.fromJson(
      json['product'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> updatePost(String id, PostDraft draft) async {
    final response = await http.put(
      Uri.parse('$baseUrl/posts/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'authorId': draft.authorId,
        'authorNickname': draft.authorNickname,
        'title': draft.title,
        'content': draft.content,
        'priceMin': draft.priceMin,
        'priceMax': draft.priceMax,
        'categories': draft.categories,
        'imageDatas': draft.imageBytes.map(base64Encode).toList(),
        'imageUrls': draft.imageUrls,
        'details': draft.details.toJson(),
        'calories': draft.calories,
        'rating': draft.rating,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('게시글 수정 실패');
    }
  }
}
