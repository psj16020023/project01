import 'dart:typed_data';

import 'post.dart';

class PostDraft {
  const PostDraft({
    required this.authorId,
    required this.authorNickname,
    required this.title,
    required this.content,
    required this.priceMin,
    required this.priceMax,
    required this.categories,
    required this.imageBytes,
    this.imageUrls = const <String>[],
    required this.details,
    this.calories,
    this.rating = 0,
  });

  final String authorId;
  final String authorNickname;
  final String title;
  final String content;
  final int priceMin;
  final int priceMax;
  final List<String> categories;
  final List<Uint8List> imageBytes;
  final List<String> imageUrls;
  final PostDetails details;
  final int? calories;
  final double rating;
}
