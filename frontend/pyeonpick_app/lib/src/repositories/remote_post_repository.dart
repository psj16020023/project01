import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/combination_battle.dart';
import '../models/battle_results.dart';
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
  static const _authTokenKey = 'pyeonpick_auth_token_v1';

  Future<Map<String, String>> _battleHeaders({bool contentType = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);
    if (token == null || token.isEmpty) {
      throw StateError('로그인이 필요합니다.');
    }
    return <String, String>{
      if (contentType) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<BattleResultsPage> fetchBattleResults(String currentUserId) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/battles/results'),
          headers: await _battleHeaders(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('픽쇼츠 결과 조회 실패');
    return BattleResultsPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<String>> markBattleResultsRead(
    String currentUserId,
    List<String> matchIds,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/battles/results/read'),
          headers: await _battleHeaders(contentType: true),
          body: jsonEncode({'matchIds': matchIds}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('픽쇼츠 결과 확인 실패');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['readIds']
            as List<dynamic>)
        .cast<String>();
  }

  @override
  Future<CombinationBattleState> fetchBattleState() async {
    final response = await http.get(
      Uri.parse('$baseUrl/battles'),
      headers: await _battleHeaders(),
    );
    if (response.statusCode != 200) throw Exception('픽 쇼츠 조회 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CombinationBattleState(
      matches: (json['matches'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (item) => BattleMatchEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  @override
  Future<List<BattleMatchEntry>> fetchBattleHighlights() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/battles/highlights'),
          headers: await _battleHeaders(),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('픽쇼츠 화제 결과 조회 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['matches'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => BattleMatchEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BattleMatchEntry> createBattle(BattleMatchEntry match) async {
    final response = await http.post(
      Uri.parse('$baseUrl/battles'),
      headers: await _battleHeaders(contentType: true),
      body: jsonEncode(match.toJson()),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('픽 쇼츠 작성 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return BattleMatchEntry.fromJson(json['match'] as Map<String, dynamic>);
  }

  @override
  Future<BattleMatchEntry> castBattleVote(
    String matchId,
    BattleVoteSide side,
    String currentUserId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/battles/$matchId/vote'),
      headers: await _battleHeaders(contentType: true),
      body: jsonEncode(<String, dynamic>{'side': side.name}),
    );
    if (response.statusCode != 200) throw Exception('픽 쇼츠 투표 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return BattleMatchEntry.fromJson(json['match'] as Map<String, dynamic>);
  }

  @override
  Future<BattleMatchEntry> updateBattle(BattleMatchEntry match) async {
    final response = await http.put(
      Uri.parse('$baseUrl/battles/${match.id}'),
      headers: await _battleHeaders(contentType: true),
      body: jsonEncode(match.toJson()),
    );
    if (response.statusCode != 200) throw Exception('픽 쇼츠 수정 실패');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return BattleMatchEntry.fromJson(json['match'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteBattle(String matchId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/battles/$matchId'),
      headers: await _battleHeaders(),
    );
    if (response.statusCode != 200) throw Exception('픽 쇼츠 삭제 실패');
  }

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
    List<String>? authorIds,
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
        if (authorIds != null && authorIds.isNotEmpty)
          'authorIds': authorIds.join(','),
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

    final response = await http.get(uri).timeout(const Duration(seconds: 12));
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
    final response = await http
        .post(
          Uri.parse('$baseUrl/posts/$id/like'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': currentUserId}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('좋아요 실패');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Post.fromJson(json['post'] as Map<String, dynamic>);
  }

  @override
  Future<Post> toggleDislike(String id, String currentUserId) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/posts/$id/dislike'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': currentUserId}),
        )
        .timeout(const Duration(seconds: 8));
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
