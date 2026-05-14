import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/post.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'post_repository.dart';

class RemotePostRepository implements PostRepository {
  RemotePostRepository({required this.baseUrl});

  final String baseUrl;

  @override
  Future<void> addComment(String id, String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$id/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 200) {
      throw Exception('댓글 등록 실패');
    }
  }

  @override
  Future<void> createPost(PostDraft draft) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': draft.title,
        'content': draft.content,
        'priceMin': draft.priceMin,
        'priceMax': draft.priceMax,
        'categories': draft.categories,
        'imageData': draft.imageBytes == null ? null : base64Encode(draft.imageBytes!),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('게시글 작성 실패');
    }
  }

  @override
  Future<List<Post>> fetchPosts({
    String? query,
    int? minPrice,
    int? maxPrice,
    required SortMode sortMode,
  }) async {
    final uri = Uri.parse('$baseUrl/posts').replace(queryParameters: {
      if (query != null && query.isNotEmpty) 'query': query,
      if (minPrice != null) 'minPrice': '$minPrice',
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      'sort': sortMode == SortMode.latest ? 'latest' : 'popular',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('게시글 조회 실패');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['posts'] as List<dynamic>;
    return items.map((item) => Post.fromJson(item as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> toggleLike(String id) async {
    final response = await http.post(Uri.parse('$baseUrl/posts/$id/like'));
    if (response.statusCode != 200) {
      throw Exception('좋아요 실패');
    }
  }

  @override
  Future<ProductLookupResult> lookupProductByBarcode(String barcode) async {
    final normalized = barcode.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final response = await http.get(Uri.parse('$baseUrl/products/lookup/$normalized'));
    if (response.statusCode != 200) {
      throw Exception('상품 조회 실패');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ProductLookupResult.fromJson(json['product'] as Map<String, dynamic>);
  }
}
