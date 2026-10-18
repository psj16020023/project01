import '../models/post.dart';
import '../models/pyeon_user.dart';

abstract final class BotRecommendationScorer {
  static const tastes = <String>['달달', '매콤', '새콤', '짭짤'];

  static Set<String> requestedTastes(
    String prompt, {
    Iterable<String> analyzedTastes = const <String>[],
  }) {
    final normalized = prompt.toLowerCase();
    final result = analyzedTastes
        .map(normalizeTaste)
        .where(tastes.contains)
        .toSet();
    const patterns = <String, List<String>>{
      '달달': ['달달', '달콤', '단맛', '단 거', '초코'],
      '매콤': ['매콤', '매운', '불닭', '마라'],
      '새콤': ['새콤', '상큼', '신맛', '레몬'],
      '짭짤': ['짭짤', '짠맛', '짠 거'],
    };
    for (final entry in patterns.entries) {
      if (entry.value.any(normalized.contains)) result.add(entry.key);
    }
    return result;
  }

  static Set<String> emotionTastes(Iterable<String> moods, BotSetup setup) {
    final result = <String>{};
    for (final mood in moods) {
      switch (mood) {
        case 'happy':
          result.addAll(const ['달달', '새콤']);
          break;
        case 'down':
          result.add('달달');
          break;
        case 'stress':
          result.add(setup.tasteLevel('매콤') >= 4 ? '매콤' : '달달');
          break;
        case 'anxious':
          result.add('짭짤');
          break;
        case 'surprised':
        case 'disgust':
        case 'hot':
          result.add('새콤');
          break;
        case 'tired':
          result.addAll(const ['새콤', '짭짤']);
          break;
        case 'sick':
          // 몸이 아픈 상태는 맛 선호로 단정하지 않는다.
          break;
      }
    }
    return result;
  }

  static int score({
    required Post post,
    required BotSetup setup,
    required String prompt,
    required Set<String> requestedTastes,
    required Set<String> emotionTastes,
    required bool useAgeCalorieGuide,
  }) {
    var score = 0;
    final categories = post.categories.map(normalizeTaste).toSet();
    final text = '${post.title} ${post.content}'.toLowerCase();
    final ratings = _postTasteRatings(post);

    bool matchesTaste(String taste) =>
        categories.contains(taste) || (ratings[taste] ?? 0) >= 4;

    for (final taste in requestedTastes) {
      if (matchesTaste(taste)) score += 8;
    }
    for (final taste in emotionTastes.difference(requestedTastes)) {
      if (matchesTaste(taste)) score += 3;
    }

    final wantsDiet = _hasAny(prompt, const [
      '다이어트',
      '살 빼',
      '살빼',
      '감량',
      '칼로리',
      '저칼로리',
    ]);
    final wantsProtein = _hasAny(prompt, const [
      '단백질',
      'protein',
      '근손실',
      '운동 후',
      '운동끝',
      '헬스',
    ]);
    final wantsLightMeal = _hasAny(prompt, const [
      '가볍게',
      '부담 없',
      '안 무거운',
      '속 편한',
      '클린',
    ]);
    final wantsSatiety = _hasAny(prompt, const [
      '포만감',
      '든든',
      '배부른',
      '허기',
      '허기짐',
    ]);
    final avoidsSugar = _hasAny(prompt, const [
      '당 줄',
      '당류',
      '단 거 말고',
      '덜 단',
      '무가당',
    ]);
    final wantsFullMeal = _hasAny(prompt, const [
      '한끼',
      '한 끼',
      '식사',
      '끼니',
      '아침',
      '점심',
      '저녁',
      '밥',
      '배고',
      '든든',
    ]);
    final minutesMatch = RegExp(r'(\d+)\s*분').firstMatch(prompt);
    final minutes = int.tryParse(minutesMatch?.group(1) ?? '');
    final needsSpeed =
        _hasAny(prompt, const ['빨리', '당장', '지금 바로', '시간없', '급해']) ||
        (minutes != null && minutes <= 10);
    final isLowCalorie =
        categories.contains('저칼로리') ||
        categories.contains('건강') ||
        (post.calories != null && post.calories! <= 450);
    final isProtein = _hasAny(text, const ['닭가슴살', '계란', '구운계란', '요거트', '단백질']);
    final isLight =
        isLowCalorie ||
        _hasAny(text, const ['요거트', '컵과일', '탄산수', '계란', '샐러드', '닭가슴살']);
    final isFilling = _hasAny(text, const [
      '김밥',
      '도시락',
      '라면',
      '핫바',
      '샌드위치',
      '닭가슴살',
      '계란',
    ]);
    final isFast =
        categories.contains('시간절약') ||
        _hasAny(text, const ['바로', '간단', '전자레인지', '빠르게']) ||
        post.details.prepTimeTag.contains('5분');

    if (wantsDiet && isLowCalorie) score += 8;
    if (wantsProtein && isProtein) score += 8;
    if (wantsLightMeal && isLight) score += 8;
    if (wantsSatiety && isFilling) score += 8;
    if (avoidsSugar && matchesTaste('달달')) score -= 8;
    if (needsSpeed && isFast) score += 8;

    for (final entry in setup.priorityValues.asMap().entries) {
      final priority = entry.value;
      final weight = entry.key == 0 ? 9 : 6;
      final matches = switch (priority) {
        '저칼로리' => isLowCalorie,
        '가성비' =>
          categories.contains('가성비') ||
              (post.priceMax > 0 && post.priceMax <= 4000),
        '시간절약' => isFast,
        '호불호' =>
          categories.contains('호불호') || (post.likes + post.dislikes >= 12),
        '트렌드' => categories.contains('트렌드') || post.likes >= 15,
        _ => false,
      };
      if (matches) score += weight;
    }

    var allTastesWithinOne = true;
    for (final taste in tastes) {
      final difference = (setup.tasteLevel(taste) - (ratings[taste] ?? 3))
          .abs();
      if (difference > 1) allTastesWithinOne = false;
      score += switch (difference) {
        0 => 4,
        1 => 2,
        2 => -3,
        _ => -7,
      };
    }
    if (allTastesWithinOne) score += 12;

    final mealCalorieRange = setup.mealCalorieRange;
    final calories = post.calories;
    if (useAgeCalorieGuide && mealCalorieRange != null && calories != null) {
      final isWithinRange =
          calories >= mealCalorieRange.minCalories &&
          calories <= mealCalorieRange.maxCalories;
      if (isWithinRange) {
        score += wantsFullMeal ? 12 : 5;
      } else if (calories > mealCalorieRange.maxCalories) {
        final excessRatio = calories / mealCalorieRange.maxCalories;
        score += wantsFullMeal
            ? (excessRatio > 1.25 ? -14 : -7)
            : (excessRatio > 1.25 ? -5 : -2);
      } else if (wantsFullMeal &&
          calories < (mealCalorieRange.minCalories * 0.8).round()) {
        score -= 6;
      }
    }
    return score;
  }

  static String normalizeTaste(String value) {
    final normalized = value.replaceAll('#', '').trim();
    if (normalized == '신' || normalized == '상큼') return '새콤';
    if (normalized.contains('짭')) return '짭짤';
    return normalized;
  }

  static Map<String, int> _postTasteRatings(Post post) {
    if (post.reviews.isNotEmpty) {
      int average(int Function(PostReview review) pick) =>
          (post.reviews.map(pick).reduce((a, b) => a + b) / post.reviews.length)
              .round()
              .clamp(1, 5);
      return <String, int>{
        '달달': average((review) => review.sweet),
        '매콤': average((review) => review.spicy),
        '새콤': average((review) => review.sour),
        '짭짤': average((review) => review.salty),
      };
    }

    final text = '${post.title} ${post.content} ${post.categories.join(' ')}';
    return <String, int>{
      '달달': _hasAny(text, const ['달달', '초코', '바닐라', '젤리', '디저트']) ? 4 : 2,
      '매콤': _hasAny(text, const ['매콤', '매운', '불닭', '고추']) ? 4 : 2,
      '새콤': _hasAny(text, const ['새콤', '상큼', '레몬', '탄산']) ? 4 : 2,
      '짭짤': _hasAny(text, const ['짭짤', '라면', '김밥', '핫바', '치즈']) ? 4 : 2,
    };
  }

  static bool _hasAny(String source, List<String> needles) =>
      needles.any(source.contains);
}
