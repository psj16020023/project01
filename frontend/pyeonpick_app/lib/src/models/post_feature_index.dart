import 'post.dart';

class PostFeatureInfo {
  const PostFeatureInfo({
    required this.id,
    required this.authorId,
    required this.title,
    this.usedProducts = const <String>[],
    required this.likes,
    required this.dislikes,
    required this.commentCount,
    required this.reviewCount,
    required this.recentLikeCount,
    required this.maleLikeCount,
    required this.femaleLikeCount,
    required this.createdAt,
    required this.topFiveEnteredAt,
    required this.topWorstEnteredAt,
    this.imageUrl,
  });

  factory PostFeatureInfo.fromJson(Map<String, dynamic> json) {
    return PostFeatureInfo(
      id: json['id'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      title: json['title'] as String? ?? '제목 없는 꿀조합',
      usedProducts:
          (json['usedProducts'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      reviewCount: json['reviewCount'] as int? ?? 0,
      recentLikeCount: json['recentLikeCount'] as int? ?? 0,
      maleLikeCount: json['maleLikeCount'] as int? ?? 0,
      femaleLikeCount: json['femaleLikeCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      topFiveEnteredAt: json['topFiveEnteredAt'] == null
          ? null
          : DateTime.tryParse(json['topFiveEnteredAt'] as String),
      topWorstEnteredAt: json['topWorstEnteredAt'] == null
          ? null
          : DateTime.tryParse(json['topWorstEnteredAt'] as String),
      imageUrl: json['imageUrl'] as String?,
    );
  }

  factory PostFeatureInfo.fromPost(Post post) {
    return PostFeatureInfo(
      id: post.id,
      authorId: post.authorId,
      title: post.title,
      usedProducts: post.details.usedProducts,
      likes: post.likes,
      dislikes: post.dislikes,
      commentCount: post.comments.length,
      reviewCount: post.reviews.length,
      recentLikeCount: 0,
      maleLikeCount: 0,
      femaleLikeCount: 0,
      createdAt: post.createdAt,
      topFiveEnteredAt: post.topFiveEnteredAt,
      topWorstEnteredAt: post.topWorstEnteredAt,
      imageUrl: post.allImageDatas.isNotEmpty
          ? post.allImageDatas.first
          : (post.allImageUrls.isNotEmpty ? post.allImageUrls.first : null),
    );
  }

  final String id;
  final String authorId;
  final String title;
  final List<String> usedProducts;
  final int likes;
  final int dislikes;
  final int commentCount;
  final int reviewCount;
  final int recentLikeCount;
  final int maleLikeCount;
  final int femaleLikeCount;
  final DateTime createdAt;
  final DateTime? topFiveEnteredAt;
  final DateTime? topWorstEnteredAt;
  final String? imageUrl;

  int get genderLikeTotal => maleLikeCount + femaleLikeCount;

  double get maleLikeRatio =>
      genderLikeTotal == 0 ? 0 : maleLikeCount / genderLikeTotal;

  double get femaleLikeRatio =>
      genderLikeTotal == 0 ? 0 : femaleLikeCount / genderLikeTotal;

  PostFeatureInfo copyWith({int? maleLikeCount, int? femaleLikeCount}) {
    return PostFeatureInfo(
      id: id,
      authorId: authorId,
      title: title,
      usedProducts: usedProducts,
      likes: likes,
      dislikes: dislikes,
      commentCount: commentCount,
      reviewCount: reviewCount,
      recentLikeCount: recentLikeCount,
      maleLikeCount: maleLikeCount ?? this.maleLikeCount,
      femaleLikeCount: femaleLikeCount ?? this.femaleLikeCount,
      createdAt: createdAt,
      topFiveEnteredAt: topFiveEnteredAt,
      topWorstEnteredAt: topWorstEnteredAt,
      imageUrl: imageUrl,
    );
  }
}
