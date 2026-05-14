import 'package:intl/intl.dart';

class PostComment {
  const PostComment({
    required this.text,
    required this.createdAt,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    return PostComment(
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PostComment copyWith({
    String? text,
    DateTime? createdAt,
  }) {
    return PostComment(
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Post {
  const Post({
    required this.id,
    required this.title,
    required this.content,
    required this.priceMin,
    required this.priceMax,
    required this.categories,
    required this.likes,
    required this.comments,
    required this.createdAt,
    required this.imageData,
    required this.imageUrl,
    required this.likedByMe,
    required this.topFiveEnteredAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      title: json['title'] as String? ?? '제목 없는 꿀조합',
      content: json['content'] as String? ?? '',
      priceMin: json['priceMin'] as int? ?? 0,
      priceMax: json['priceMax'] as int? ?? 0,
      categories: (json['categories'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      likes: json['likes'] as int? ?? 0,
      comments: (json['comments'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => PostComment.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      imageData: json['imageData'] as String?,
      imageUrl: json['imageUrl'] as String?,
      likedByMe: json['likedByMe'] as bool? ?? false,
      topFiveEnteredAt: json['topFiveEnteredAt'] == null
          ? null
          : DateTime.tryParse(json['topFiveEnteredAt'] as String),
    );
  }

  final String id;
  final String title;
  final String content;
  final int priceMin;
  final int priceMax;
  final List<String> categories;
  final int likes;
  final List<PostComment> comments;
  final DateTime createdAt;
  final String? imageData;
  final String? imageUrl;
  final bool likedByMe;
  final DateTime? topFiveEnteredAt;

  String get createdAtLabel => DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(createdAt);

  String get priceLabel =>
      '${NumberFormat.decimalPattern('ko_KR').format(priceMin)}~${NumberFormat.decimalPattern('ko_KR').format(priceMax)}원';

  String get topFiveDateLabel =>
      topFiveEnteredAt == null ? '' : DateFormat('yyyy.MM.dd', 'ko_KR').format(topFiveEnteredAt!);

  Post copyWith({
    String? id,
    String? title,
    String? content,
    int? priceMin,
    int? priceMax,
    List<String>? categories,
    int? likes,
    List<PostComment>? comments,
    DateTime? createdAt,
    String? imageData,
    String? imageUrl,
    bool? likedByMe,
    DateTime? topFiveEnteredAt,
  }) {
    return Post(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
      categories: categories ?? this.categories,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      imageData: imageData ?? this.imageData,
      imageUrl: imageUrl ?? this.imageUrl,
      likedByMe: likedByMe ?? this.likedByMe,
      topFiveEnteredAt: topFiveEnteredAt ?? this.topFiveEnteredAt,
    );
  }
}
