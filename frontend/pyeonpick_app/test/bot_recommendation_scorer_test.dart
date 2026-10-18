import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/models/post.dart';
import 'package:pyeonpick_app/src/models/pyeon_user.dart';
import 'package:pyeonpick_app/src/services/bot_recommendation_scorer.dart';

Post post({
  required String id,
  required List<String> categories,
  int likes = 0,
}) {
  return Post(
    id: id,
    authorId: 'author',
    authorNickname: '작성자',
    title: '초코 요거트',
    content: '간단한 조합',
    priceMin: 3500,
    priceMax: 3500,
    categories: categories,
    likes: likes,
    dislikes: 0,
    comments: const <PostComment>[],
    createdAt: DateTime(2026),
    imageData: null,
    imageUrl: null,
    imageDatas: const <String>[],
    imageUrls: const <String>[],
    details: const PostDetails(
      eatingSteps: <String>[],
      tips: <String>[],
      cautions: <String>[],
      situationTags: <String>[],
      reviewPoints: <String>[],
      prepTimeTag: '',
    ),
    likedByMe: false,
    dislikedByMe: false,
    topFiveEnteredAt: null,
    topWorstEnteredAt: null,
    calories: 400,
  );
}

void main() {
  const setup = BotSetup(
    age: 20,
    gender: '여자',
    tasteRatings: <String, int>{'달달': 3, '매콤': 3, '새콤': 3, '짭짤': 3},
    priorityValues: <String>['가성비', '저칼로리'],
  );

  test('deleted situation tags never become recommendation score inputs', () {
    final requested = BotRecommendationScorer.requestedTastes('운동 후 야식 추천');
    expect(requested, isEmpty);

    final legacy = post(
      id: 'legacy',
      categories: const <String>['달달', '가성비', '야식 추천'],
      likes: 999,
    );
    final clean = post(id: 'clean', categories: const <String>['달달', '가성비']);
    final legacyScore = BotRecommendationScorer.score(
      post: legacy,
      setup: setup,
      prompt: '달달한 것 추천',
      requestedTastes: const <String>{'달달'},
      emotionTastes: const <String>{'달달', '새콤'},
      useAgeCalorieGuide: false,
    );
    final cleanScore = BotRecommendationScorer.score(
      post: clean,
      setup: setup,
      prompt: '달달한 것 추천',
      requestedTastes: const <String>{'달달'},
      emotionTastes: const <String>{'달달', '새콤'},
      useAgeCalorieGuide: false,
    );

    expect(legacyScore, 43);
    expect(cleanScore, legacyScore);
  });

  test('emotion taste is weak and adapts stress to the spicy setup', () {
    const spicySetup = BotSetup(
      age: 20,
      gender: '남자',
      tasteRatings: <String, int>{'달달': 3, '매콤': 4, '새콤': 3, '짭짤': 3},
      priorityValues: <String>[],
    );
    expect(
      BotRecommendationScorer.emotionTastes(const ['stress'], spicySetup),
      const <String>{'매콤'},
    );
    expect(
      BotRecommendationScorer.emotionTastes(const ['sick'], spicySetup),
      isEmpty,
    );
  });
}
