import 'dart:typed_data';

class PostDraft {
  const PostDraft({
    required this.title,
    required this.content,
    required this.priceMin,
    required this.priceMax,
    required this.categories,
    required this.imageBytes,
  });

  final String title;
  final String content;
  final int priceMin;
  final int priceMax;
  final List<String> categories;
  final Uint8List? imageBytes;
}
