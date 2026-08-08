import 'package:intl/intl.dart';

const List<String> communityReviewTags = <String>[
  '저칼로리',
  '가성비',
  '시간절약',
  '호불호',
  '트렌드',
];

class PostReview {
  const PostReview({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    required this.text,
    required this.rating,
    required this.tags,
    required this.sweet,
    required this.salty,
    required this.spicy,
    required this.sour,
    required this.caution,
    required this.createdAt,
  });

  factory PostReview.fromJson(Map<String, dynamic> json) {
    return PostReview(
      id: json['id'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      authorNickname: json['authorNickname'] as String? ?? '익명',
      text: json['text'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      sweet: json['sweet'] as int? ?? 1,
      salty: json['salty'] as int? ?? 1,
      spicy: json['spicy'] as int? ?? 1,
      sour: json['sour'] as int? ?? 1,
      caution: json['caution'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String authorId;
  final String authorNickname;
  final String text;
  final double rating;
  final List<String> tags;
  final int sweet;
  final int salty;
  final int spicy;
  final int sour;
  final String caution;
  final DateTime createdAt;

  String get createdAtLabel => DateFormat('yyyy.MM.dd HH:mm').format(createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorId': authorId,
    'authorNickname': authorNickname,
    'text': text,
    'rating': rating,
    'tags': tags,
    'sweet': sweet,
    'salty': salty,
    'spicy': spicy,
    'sour': sour,
    'caution': caution,
    'createdAt': createdAt.toIso8601String(),
  };

  PostReview copyWith({
    String? text,
    double? rating,
    List<String>? tags,
    int? sweet,
    int? salty,
    int? spicy,
    int? sour,
    String? caution,
  }) {
    return PostReview(
      id: id,
      authorId: authorId,
      authorNickname: authorNickname,
      text: text ?? this.text,
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
      sweet: sweet ?? this.sweet,
      salty: salty ?? this.salty,
      spicy: spicy ?? this.spicy,
      sour: sour ?? this.sour,
      caution: caution ?? this.caution,
      createdAt: createdAt,
    );
  }
}

class PostComment {
  const PostComment({
    required this.authorId,
    required this.authorNickname,
    this.authorProfileImageUrl,
    required this.text,
    required this.createdAt,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    return PostComment(
      authorId: json['authorId'] as String? ?? '',
      authorNickname: json['authorNickname'] as String? ?? '익명',
      authorProfileImageUrl: json['authorProfileImageUrl'] as String?,
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String authorId;
  final String authorNickname;
  final String? authorProfileImageUrl;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'authorId': authorId,
      'authorNickname': authorNickname,
      'authorProfileImageUrl': authorProfileImageUrl,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PostComment copyWith({
    String? authorId,
    String? authorNickname,
    String? authorProfileImageUrl,
    String? text,
    DateTime? createdAt,
  }) {
    return PostComment(
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class PostDetails {
  const PostDetails({
    required this.eatingSteps,
    required this.tips,
    required this.cautions,
    required this.situationTags,
    required this.reviewPoints,
    required this.prepTimeTag,
  });

  factory PostDetails.fromJson(Map<String, dynamic>? json) {
    return PostDetails(
      eatingSteps: (json?['eatingSteps'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      tips: (json?['tips'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      cautions: (json?['cautions'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      situationTags:
          (json?['situationTags'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      reviewPoints:
          (json?['reviewPoints'] as List<dynamic>? ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      prepTimeTag: (json?['prepTimeTag'] as String? ?? '').trim(),
    );
  }

  final List<String> eatingSteps;
  final List<String> tips;
  final List<String> cautions;
  final List<String> situationTags;
  final List<String> reviewPoints;
  final String prepTimeTag;

  Map<String, dynamic> toJson() {
    return {
      'eatingSteps': eatingSteps,
      'tips': tips,
      'cautions': cautions,
      'situationTags': situationTags,
      'reviewPoints': reviewPoints,
      'prepTimeTag': prepTimeTag,
    };
  }
}

class PostAudienceStats {
  const PostAudienceStats({required this.maleCount, required this.femaleCount});

  factory PostAudienceStats.fromJson(Map<String, dynamic> json) {
    return PostAudienceStats(
      maleCount: (json['maleCount'] as num?)?.toInt() ?? 0,
      femaleCount: (json['femaleCount'] as num?)?.toInt() ?? 0,
    );
  }

  final int maleCount;
  final int femaleCount;

  int get totalWithGender => maleCount + femaleCount;
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    this.authorProfileImageUrl,
    required this.title,
    required this.content,
    required this.priceMin,
    required this.priceMax,
    required this.categories,
    required this.likes,
    required this.dislikes,
    required this.comments,
    required this.createdAt,
    required this.imageData,
    required this.imageUrl,
    required this.imageDatas,
    required this.imageUrls,
    required this.details,
    required this.likedByMe,
    required this.dislikedByMe,
    required this.topFiveEnteredAt,
    required this.topWorstEnteredAt,
    this.calories,
    this.rating = 0,
    this.reviews = const <PostReview>[],
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      authorId: json['authorId'] as String? ?? 'seed-author',
      authorNickname: json['authorNickname'] as String? ?? '편pick',
      authorProfileImageUrl: json['authorProfileImageUrl'] as String?,
      title: json['title'] as String? ?? '제목 없는 꿀조합',
      content: json['content'] as String? ?? '',
      priceMin: json['priceMin'] as int? ?? 0,
      priceMax: json['priceMax'] as int? ?? 0,
      categories: (json['categories'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
      comments: (json['comments'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => PostComment.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      imageData: json['imageData'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imageDatas: (json['imageDatas'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      imageUrls: (json['imageUrls'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      details: PostDetails.fromJson(json['details'] as Map<String, dynamic>?),
      likedByMe: json['likedByMe'] as bool? ?? false,
      dislikedByMe: json['dislikedByMe'] as bool? ?? false,
      topFiveEnteredAt: json['topFiveEnteredAt'] == null
          ? null
          : DateTime.tryParse(json['topFiveEnteredAt'] as String),
      topWorstEnteredAt: json['topWorstEnteredAt'] == null
          ? null
          : DateTime.tryParse(json['topWorstEnteredAt'] as String),
      calories: json['calories'] as int?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviews: (json['reviews'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => PostReview.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final String authorId;
  final String authorNickname;
  final String? authorProfileImageUrl;
  final String title;
  final String content;
  final int priceMin;
  final int priceMax;
  final List<String> categories;
  final int likes;
  final int dislikes;
  final List<PostComment> comments;
  final DateTime createdAt;
  final String? imageData;
  final String? imageUrl;
  final List<String> imageDatas;
  final List<String> imageUrls;
  final PostDetails details;
  final bool likedByMe;
  final bool dislikedByMe;
  final DateTime? topFiveEnteredAt;
  final DateTime? topWorstEnteredAt;
  final int? calories;
  final double rating;
  final List<PostReview> reviews;

  String get createdAtLabel =>
      DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(createdAt);

  String get priceLabel {
    if (priceMin <= 0 && priceMax <= 0) {
      return '가격 미입력';
    }
    final min = NumberFormat.decimalPattern('ko_KR').format(priceMin);
    final max = NumberFormat.decimalPattern('ko_KR').format(priceMax);
    if (priceMin == priceMax) {
      return '$min원';
    }
    return '$min~$max원';
  }

  String get topFiveDateLabel => topFiveEnteredAt == null
      ? ''
      : DateFormat('yyyy.MM.dd', 'ko_KR').format(topFiveEnteredAt!);

  String get topWorstDateLabel => topWorstEnteredAt == null
      ? ''
      : DateFormat('yyyy.MM.dd', 'ko_KR').format(topWorstEnteredAt!);

  List<String> get allImageDatas => imageDatas.isNotEmpty
      ? imageDatas
      : (imageData == null || imageData!.isEmpty ? const [] : [imageData!]);
  List<String> get allImageUrls => imageUrls.isNotEmpty
      ? imageUrls
      : (imageUrl == null || imageUrl!.isEmpty ? const [] : [imageUrl!]);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'authorNickname': authorNickname,
      'authorProfileImageUrl': authorProfileImageUrl,
      'title': title,
      'content': content,
      'priceMin': priceMin,
      'priceMax': priceMax,
      'categories': categories,
      'likes': likes,
      'dislikes': dislikes,
      'comments': comments.map((item) => item.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'imageData': imageData,
      'imageUrl': imageUrl,
      'imageDatas': imageDatas,
      'imageUrls': imageUrls,
      'details': details.toJson(),
      'likedByMe': likedByMe,
      'dislikedByMe': dislikedByMe,
      'topFiveEnteredAt': topFiveEnteredAt?.toIso8601String(),
      'topWorstEnteredAt': topWorstEnteredAt?.toIso8601String(),
      'calories': calories,
      'rating': rating,
      'reviews': reviews.map((item) => item.toJson()).toList(),
    };
  }

  Post copyWith({
    String? id,
    String? authorId,
    String? authorNickname,
    String? authorProfileImageUrl,
    String? title,
    String? content,
    int? priceMin,
    int? priceMax,
    List<String>? categories,
    int? likes,
    int? dislikes,
    List<PostComment>? comments,
    DateTime? createdAt,
    String? imageData,
    String? imageUrl,
    List<String>? imageDatas,
    List<String>? imageUrls,
    PostDetails? details,
    bool? likedByMe,
    bool? dislikedByMe,
    DateTime? topFiveEnteredAt,
    DateTime? topWorstEnteredAt,
    bool clearTopFiveEnteredAt = false,
    bool clearTopWorstEnteredAt = false,
    int? calories,
    double? rating,
    List<PostReview>? reviews,
  }) {
    return Post(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorNickname: authorNickname ?? this.authorNickname,
      authorProfileImageUrl:
          authorProfileImageUrl ?? this.authorProfileImageUrl,
      title: title ?? this.title,
      content: content ?? this.content,
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
      categories: categories ?? this.categories,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      imageData: imageData ?? this.imageData,
      imageUrl: imageUrl ?? this.imageUrl,
      imageDatas: imageDatas ?? this.imageDatas,
      imageUrls: imageUrls ?? this.imageUrls,
      details: details ?? this.details,
      likedByMe: likedByMe ?? this.likedByMe,
      topFiveEnteredAt: clearTopFiveEnteredAt
          ? null
          : (topFiveEnteredAt ?? this.topFiveEnteredAt),
      dislikedByMe: dislikedByMe ?? this.dislikedByMe,
      topWorstEnteredAt: clearTopWorstEnteredAt
          ? null
          : (topWorstEnteredAt ?? this.topWorstEnteredAt),
      calories: calories ?? this.calories,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
    );
  }
}
