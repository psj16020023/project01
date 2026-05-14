import '../core/app_environment.dart';
import '../models/post.dart';
import '../models/post_draft.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'mock_post_repository.dart';
import 'remote_post_repository.dart';

abstract class PostRepository {
  Future<List<Post>> fetchPosts({
    String? query,
    int? minPrice,
    int? maxPrice,
    required SortMode sortMode,
  });

  Future<void> toggleLike(String id);

  Future<void> addComment(String id, String text);

  Future<void> createPost(PostDraft draft);

  Future<ProductLookupResult> lookupProductByBarcode(String barcode);
}

PostRepository createPostRepository(AppEnvironment environment) {
  switch (environment.dataMode) {
    case DataMode.remote:
      return RemotePostRepository(baseUrl: environment.apiBaseUrl);
    case DataMode.mock:
      return MockPostRepository();
  }
}
