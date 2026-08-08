import '../core/app_environment.dart';
import '../models/post.dart';
import '../models/post_feature_index.dart';
import '../models/post_draft.dart';
import '../models/post_page.dart';
import '../models/product_lookup_result.dart';
import '../models/sort_mode.dart';
import 'mock_post_repository.dart';
import 'remote_post_repository.dart';

abstract class PostRepository {
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
  });

  Future<List<PostFeatureInfo>> fetchPostFeatureIndex();

  Future<List<Post>> fetchPostCatalog({String? currentUserId});

  Future<PostAudienceStats> fetchPostAudienceStats(String postId);

  Future<Post> toggleLike(String id, String currentUserId);

  Future<Post> toggleDislike(String id, String currentUserId);

  Future<Post> addComment(
    String id,
    String text, {
    required String authorId,
    required String authorNickname,
  });

  Future<Post> addReview(String id, PostReview review);

  Future<Post> updateReview(String postId, PostReview review);

  Future<Post> deleteReview(
    String postId,
    String reviewId, {
    required String authorId,
  });

  Future<void> createPost(PostDraft draft);

  Future<void> updatePost(String id, PostDraft draft);

  Future<void> deletePost(String id, String authorId);

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
