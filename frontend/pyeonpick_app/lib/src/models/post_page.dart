import 'post.dart';

class PostPage {
  const PostPage({
    required this.posts,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<Post> posts;
  final bool hasMore;
  final String? nextCursor;
}
